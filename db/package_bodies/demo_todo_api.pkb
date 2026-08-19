create or replace package body demo_todo_api as

  c_app_schema constant varchar2(30) := 'ROAD_KIT_DEMO';

  c_default_limit constant number := 25;
  c_max_limit     constant number := 100;

  -- A search term is user input reaching a LIKE pattern, so its wildcards have to be neutralised
  -- or a user typing '%' silently matches everything. Escape the escape character first, or
  -- escaping the wildcards re-introduces it. Lifted verbatim from road_admin_api.like_term -- the
  -- demo copies the framework's idioms rather than inventing its own.
  function like_term(p_term in varchar2) return varchar2 is
  begin
    return '%' || replace(replace(replace(lower(p_term), '\', '\\'), '%', '\%'), '_', '\_') || '%';
  end like_term;

  function parse_ts(p_text in varchar2, p_field in varchar2) return timestamp with time zone is
  begin
    if p_text is null then
      return null;
    end if;
    return to_timestamp_tz(p_text, 'YYYY-MM-DD"T"HH24:MI:SS.FFTZH:TZM');
  exception
    when others then
      raise_application_error(c_validation, p_field || ' must be ISO 8601 with a UTC offset');
  end parse_ts;

  -- The canonical todo object (spec-patch-08 section 6).
  --
  -- owner_principal_id is returned; owner email and display_name are not. The id is an opaque
  -- internal number, and an administrator who needs to put a name to it can resolve it through
  -- /admin/principals/, which they already hold road.role.grant for. Duplicating principal PII
  -- into a second endpoint widens the audience for it and gains nothing.
  function build_todo_json(p_todo_id in number) return json is
    l_result json;
  begin
    select json_object(
             'todo_id'            value t.todo_id,
             'owner_principal_id' value t.owner_principal_id,
             'title'              value t.title,
             'notes'              value t.notes,
             'due_at'             value t.due_at,
             'status'             value t.status,
             'created_at'         value t.created_at,
             'updated_at'         value t.updated_at
             returning json
           )
      into l_result
      from demo_todos t
     where t.todo_id = p_todo_id;

    return l_result;
  end build_todo_json;

  -- Resolves a todo the caller is entitled to see, or raises NOT_FOUND.
  --
  -- 404 rather than 403 for another owner's row, DELIBERATELY, and it is the one place the demo
  -- departs from the framework's own 403-on-refusal contract (spec-patch-08 section 6.1, decided
  -- 2026-08-19). There, the PERMISSION is missing and saying so is useful. Here the permission is
  -- held and the ROW is out of scope -- a 403 would confirm the row exists, which the caller has
  -- not earned. Same reason a login form should not say "no such user".
  function owned_todo_id(p_todo_id in number) return number is
    l_owner number;
  begin
    if p_todo_id is null then
      raise_application_error(c_validation, 'todo_id is required');
    end if;

    begin
      select owner_principal_id into l_owner from demo_todos where todo_id = p_todo_id;
    exception
      when no_data_found then
        raise_application_error(c_not_found, 'Todo ' || p_todo_id || ' not found');
    end;

    if l_owner != road_ctx_pkg.principal_id
       and not road_ctx_pkg.has_permission('todo.list_all') then
      raise_application_error(c_not_found, 'Todo ' || p_todo_id || ' not found');
    end if;

    return p_todo_id;
  end owned_todo_id;

  -- Shared by update_todo and delete_todo. Both mutate a row the caller read, so both must prove
  -- the read is still current (spec-patch-08 section 6.2).
  procedure require_fresh(p_todo_id in number, p_request in json) is
    l_token_txt varchar2(100);
    l_token     raw(16);
    l_updated   timestamp with time zone;
  begin
    l_token_txt := json_value(p_request, '$.read_token');
    if l_token_txt is null then
      raise_application_error(c_validation, 'read_token is required');
    end if;

    begin
      l_token := hextoraw(l_token_txt);
    exception
      when others then
        raise_application_error(c_validation, 'read_token is not a valid token');
    end;

    select updated_at into l_updated from demo_todos where todo_id = p_todo_id;

    if not road_audit_api.check_fresh(
         p_guid               => l_token,
         p_app_schema         => c_app_schema,
         p_entity_type        => 'DEMO_TODOS',
         p_entity_id          => to_char(p_todo_id),
         p_current_updated_at => l_updated
       )
    then
      raise_application_error(c_conflict, c_conflict_message);
    end if;
  end require_fresh;

  function get_todos(p_request in json default null) return json is
    l_offset      number;
    l_limit       number;
    l_status      varchar2(10 char);
    l_q           varchar2(200 char);
    l_owner       number;
    l_caller_type varchar2(30);
    l_caller_ref  varchar2(200);
    l_read_token  raw(16);
    l_pattern     varchar2(400 char);
    l_items       json;
    l_fetched     number;
  begin
    road_ctx_pkg.require_permission('todo.list');

    select nvl(json_value(p_request, '$.offset' returning number), 0),
           nvl(json_value(p_request, '$.limit'  returning number), c_default_limit),
           upper(json_value(p_request, '$.status')),
           json_value(p_request, '$.q'),
           json_value(p_request, '$.owner' returning number),
           nvl(json_value(p_request, '$.caller_type'), 'BROWSER'),
           json_value(p_request, '$.caller_ref')
      into l_offset, l_limit, l_status, l_q, l_owner, l_caller_type, l_caller_ref
      from dual;

    if l_offset < 0 then
      raise_application_error(c_validation, 'offset must not be negative');
    end if;
    l_limit := least(greatest(l_limit, 1), c_max_limit);

    if l_status is not null and l_status not in ('OPEN', 'DONE', 'DELETED') then
      raise_application_error(c_validation, 'status must be one of OPEN, DONE, DELETED');
    end if;

    -- THE authorisation case this demo exists to show. Reading your own rows needs todo.list;
    -- reading anyone else's needs todo.list_all as well. Note the check is on the VALUE, not on
    -- whether the parameter was supplied -- passing your own id explicitly is not an escalation
    -- and must not be treated as one.
    l_owner := nvl(l_owner, road_ctx_pkg.principal_id);
    if l_owner != road_ctx_pkg.principal_id then
      road_ctx_pkg.require_permission('todo.list_all');
    end if;

    if l_q is not null and length(trim(l_q)) > 0 then
      l_pattern := like_term(trim(l_q));
    end if;

    -- One pass, lifted from road_admin_api.get_principals: row_number over the filtered set lets
    -- the page and the "is there another page" answer come from the same predicate. Two statements
    -- would mean two copies of the WHERE clause, which is exactly the pair that drifts. limit+1
    -- rows are counted and the extra is dropped by the CASE (json_arrayagg is ABSENT ON NULL by
    -- default), so hasMore costs no second scan.
    --
    -- like_term is called ABOVE, not inside the query: a private packaged function may not be used
    -- in a SQL statement (PLS-00231). Same for parse_ts in the writers below.
    select nvl(json_arrayagg(
             case when rn <= l_limit then
               json_object(
                 'todo_id'            value todo_id,
                 'owner_principal_id' value owner_principal_id,
                 'title'              value title,
                 'notes'              value notes,
                 'due_at'             value to_char(due_at, 'YYYY-MM-DD"T"HH24:MI:SSTZH:TZM'),
                 'status'             value status,
                 'created_at'         value to_char(created_at, 'YYYY-MM-DD"T"HH24:MI:SSTZH:TZM'),
                 'updated_at'         value to_char(updated_at, 'YYYY-MM-DD"T"HH24:MI:SSTZH:TZM')
                 returning json
               )
             end
             order by rn returning json
           ), json('[]')),
           count(*)
      into l_items, l_fetched
      from (
        select t.todo_id,
               t.owner_principal_id,
               t.title,
               t.notes,
               t.due_at,
               t.status,
               t.created_at,
               t.updated_at,
               row_number() over (order by t.created_at desc, t.todo_id desc) as rn
          from demo_todos t
         where t.owner_principal_id = l_owner
           and (   (l_status is null and t.status != 'DELETED')
                or t.status = l_status)
           and (l_pattern is null or lower(t.title) like l_pattern escape '\')
      )
     where rn > l_offset
       and rn <= l_offset + l_limit + 1;

    l_read_token := road_audit_api.issue_read_token(
      p_caller_type => l_caller_type,
      p_app_schema  => c_app_schema,
      p_endpoint    => 'get_todos',
      p_caller_ref  => l_caller_ref
    );

    return json_object(
             'items'      value l_items,
             'hasMore'    value case when l_fetched > l_limit then 'true' else 'false' end
                                format json,
             'limit'      value l_limit,
             'offset'     value l_offset,
             'count'      value least(l_fetched, l_limit),
             'read_token' value rawtohex(l_read_token)
             returning json
           );
  end get_todos;

  function create_todo(p_request in json) return json is
    l_title   varchar2(200 char);
    l_notes   varchar2(4000 char);
    l_due_txt varchar2(100);
    l_due     timestamp with time zone;
    l_todo_id number;
  begin
    road_ctx_pkg.require_permission('todo.create');

    -- An attempt to nominate the owner is REFUSED, not ignored. Silently dropping it would tell a
    -- caller probing for the hole that their forgery was accepted.
    if json_exists(p_request, '$.owner_principal_id') then
      raise_application_error(c_validation,
        'owner_principal_id is taken from the session and must not be supplied');
    end if;

    select json_value(p_request, '$.title'),
           json_value(p_request, '$.notes'),
           json_value(p_request, '$.due_at')
      into l_title, l_notes, l_due_txt
      from dual;

    if l_title is null then
      raise_application_error(c_validation, 'title is required');
    end if;

    l_due := parse_ts(l_due_txt, 'due_at');

    insert into demo_todos (owner_principal_id, title, notes, due_at)
    values (road_ctx_pkg.principal_id, l_title, l_notes, l_due)
    returning todo_id into l_todo_id;

    return build_todo_json(l_todo_id);
  end create_todo;

  function get_todo(p_request in json) return json is
    l_todo_id     number;
    l_caller_type varchar2(30);
    l_caller_ref  varchar2(200);
    l_read_token  raw(16);
  begin
    road_ctx_pkg.require_permission('todo.get');

    select json_value(p_request, '$.todo_id' returning number),
           nvl(json_value(p_request, '$.caller_type'), 'BROWSER'),
           json_value(p_request, '$.caller_ref')
      into l_todo_id, l_caller_type, l_caller_ref
      from dual;

    l_todo_id := owned_todo_id(l_todo_id);

    l_read_token := road_audit_api.issue_read_token(
      p_caller_type => l_caller_type,
      p_app_schema  => c_app_schema,
      p_endpoint    => 'get_todo',
      p_caller_ref  => l_caller_ref
    );

    return json_object(
             'todo'       value build_todo_json(l_todo_id),
             'read_token' value rawtohex(l_read_token)
             returning json
           );
  end get_todo;

  function update_todo(p_request in json) return json is
    l_todo_id   number;
    l_status    varchar2(10 char);
    l_has_due   boolean;
    l_due       timestamp with time zone;
  begin
    road_ctx_pkg.require_permission('todo.update');

    l_todo_id := owned_todo_id(json_value(p_request, '$.todo_id' returning number));
    require_fresh(l_todo_id, p_request);

    l_status := upper(json_value(p_request, '$.status'));

    -- DELETED is deliberately not reachable here. "I finished it" and "I want it gone" are
    -- different intentions and the audit trail should keep them apart.
    if l_status is not null and l_status not in ('OPEN', 'DONE') then
      raise_application_error(c_validation,
        'status must be OPEN or DONE - use DELETE /todos/{todo_id}/ to remove a todo');
    end if;

    l_has_due := json_exists(p_request, '$.due_at');
    if l_has_due then
      l_due := parse_ts(json_value(p_request, '$.due_at'), 'due_at');
    end if;

    update demo_todos
       set title  = case when json_exists(p_request, '$.title')
                         then json_value(p_request, '$.title') else title end,
           notes  = case when json_exists(p_request, '$.notes')
                         then json_value(p_request, '$.notes') else notes end,
           due_at = case when l_has_due then l_due else due_at end,
           status = nvl(l_status, status)
     where todo_id = l_todo_id;

    return build_todo_json(l_todo_id);
  end update_todo;

  function delete_todo(p_request in json) return json is
    l_todo_id number;
    l_status  varchar2(10 char);
  begin
    road_ctx_pkg.require_permission('todo.delete');

    l_todo_id := owned_todo_id(json_value(p_request, '$.todo_id' returning number));
    require_fresh(l_todo_id, p_request);

    select status into l_status from demo_todos where todo_id = l_todo_id;

    if l_status = 'DELETED' then
      -- Idempotent, not an error: same shape as grant_role and attach_permission.
      return json_object('todo_id' value l_todo_id, 'deleted' value 'false' format json
                         returning json);
    end if;

    update demo_todos set status = 'DELETED' where todo_id = l_todo_id;

    return json_object('todo_id' value l_todo_id, 'deleted' value 'true' format json
                       returning json);
  end delete_todo;

  function purge(p_request in json) return json is
    l_before_txt varchar2(100);
    l_before     timestamp with time zone;
    l_purged     number;
  begin
    -- todo.purge is RESERVED. Nothing here reads that flag -- the reservation governs who may
    -- attach the permission to a role, not what the handler does once someone holds it. The
    -- guard is road_reserved_composition, in the database, one layer down.
    road_ctx_pkg.require_permission('todo.purge');

    l_before_txt := json_value(p_request, '$.before');
    if l_before_txt is null then
      raise_application_error(c_validation, 'before is required');
    end if;
    l_before := parse_ts(l_before_txt, 'before');

    -- Across ALL owners, and no ownership filter anywhere: that is what makes this the dangerous
    -- operation worth reserving.
    delete from demo_todos
     where status in ('DONE', 'DELETED')
       and updated_at < l_before;
    l_purged := sql%rowcount;

    road_audit_api.log_admin_action(
      p_endpoint    => 'purge',
      p_entity_type => 'DEMO_TODOS',
      p_entity_id   => to_char(l_purged),
      p_outcome     => 'OK'
    );

    return json_object('purged' value l_purged returning json);
  end purge;

end demo_todo_api;
/
