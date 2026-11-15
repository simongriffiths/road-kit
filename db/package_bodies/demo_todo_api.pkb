create or replace package body demo_todo_api as

  c_entity        constant varchar2(30) := 'DEMO_TODOS';
  c_default_limit constant number := 25;
  c_max_limit     constant number := 100;

  -- A search term is user input reaching a LIKE pattern, so its wildcards have to be neutralised
  -- or a user typing '%' silently matches everything. Escape the escape character first, or
  -- escaping the wildcards re-introduces it. From road_admin_api.like_term.
  function like_term(p_term in varchar2) return varchar2 is
  begin
    return '%' || replace(replace(replace(lower(p_term), '\', '\\'), '%', '\%'), '_', '\_') || '%';
  end like_term;

  -- ISO 8601 with an offset, with or without fractional seconds, and Z for UTC.
  function parse_ts(p_text in varchar2, p_field in varchar2) return timestamp with time zone is
    l_text varchar2(100) := regexp_replace(trim(p_text), 'Z$', '+00:00');
  begin
    if l_text is null then
      return null;
    end if;
    begin
      return to_timestamp_tz(l_text, 'YYYY-MM-DD"T"HH24:MI:SS.FFTZH:TZM');
    exception
      when others then
        return to_timestamp_tz(l_text, 'YYYY-MM-DD"T"HH24:MI:SSTZH:TZM');
    end;
  exception
    when others then
      road_surface_api.bad_request(p_field || ' must be ISO 8601 with a UTC offset');
  end parse_ts;

  function ids(p_id in number) return json is
  begin
    return json('[' || p_id || ']');
  end ids;

  -- The idempotency key of an action that creates or purges: the header, required.
  function require_key(p_key in varchar2) return varchar2 is
  begin
    if trim(p_key) is null then
      road_surface_api.bad_request('The Idempotency-Key header is required');
    end if;
    return trim(p_key);
  end require_key;

  -- The canonical todo object. owner_principal_id is returned; owner email and display name are
  -- not: the id is opaque, and an administrator who needs a name resolves it through
  -- /admin/principals/. Duplicating principal PII into a second endpoint widens its audience.
  function build_todo_json(p_todo_id in number) return json is
    l_result json;
  begin
    select json_object(
             'todo_id'            value t.todo_id,
             'owner_principal_id' value t.owner_principal_id,
             'title'              value t.title,
             'notes'              value t.notes,
             'due_at'             value to_char(sys_extract_utc(t.due_at), 'YYYY-MM-DD"T"HH24:MI:SS.FF3"Z"'),
             'status'             value t.status,
             'created_at'         value to_char(sys_extract_utc(t.created_at), 'YYYY-MM-DD"T"HH24:MI:SS.FF3"Z"'),
             'updated_at'         value to_char(sys_extract_utc(t.updated_at), 'YYYY-MM-DD"T"HH24:MI:SS.FF3"Z"')
             returning json)
      into l_result
      from demo_todos t
     where t.todo_id = p_todo_id;
    return l_result;
  end build_todo_json;

  ---------------------------------------------------------------------------
  -- Views
  ---------------------------------------------------------------------------

  function list_todos(
    p_offset in number   default null,
    p_limit  in number   default null,
    p_status in varchar2 default null,
    p_query  in varchar2 default null,
    p_owner  in number   default null
  ) return clob is
    l_offset  number := nvl(p_offset, 0);
    l_limit   number := nvl(p_limit, c_default_limit);
    l_status  varchar2(10 char) := upper(trim(p_status));
    l_owner   number;
    l_pattern varchar2(400 char);
    l_items   json;
    l_fetched number;
    l_token   varchar2(40);
  begin
    road_ctx_pkg.require_permission('todo.list');

    if l_offset < 0 then
      road_surface_api.bad_request('offset must not be negative');
    end if;
    l_limit := least(greatest(l_limit, 1), c_max_limit);
    if l_status is not null and l_status not in ('OPEN', 'DONE', 'DELETED') then
      road_surface_api.bad_request('status must be one of OPEN, DONE, DELETED');
    end if;

    -- THE authorisation case this demo exists to show. Reading your own rows needs todo.list;
    -- reading anyone else's needs todo.list_all as well.
    l_owner := nvl(p_owner, road_ctx_pkg.principal_id);
    if l_owner != road_ctx_pkg.principal_id then
      road_ctx_pkg.require_permission('todo.list_all');
    end if;

    if p_query is not null and length(trim(p_query)) > 0 then
      l_pattern := like_term(trim(p_query));
    end if;

    -- One pass: row_number over the filtered set gives the page and the "is there another page"
    -- answer from the same predicate. limit+1 rows are counted and the extra is dropped by the CASE
    -- (json_arrayagg is ABSENT ON NULL by default). like_term is called ABOVE: a private packaged
    -- function may not be used in SQL (PLS-00231), so the timestamps are formatted with TO_CHAR here.
    select nvl(json_arrayagg(
             case when rn <= l_limit then
               json_object(
                 'todo_id'            value todo_id,
                 'owner_principal_id' value owner_principal_id,
                 'title'              value title,
                 'notes'              value notes,
                 'due_at'             value to_char(sys_extract_utc(due_at), 'YYYY-MM-DD"T"HH24:MI:SS.FF3"Z"'),
                 'status'             value status,
                 'created_at'         value to_char(sys_extract_utc(created_at), 'YYYY-MM-DD"T"HH24:MI:SS.FF3"Z"'),
                 'updated_at'         value to_char(sys_extract_utc(updated_at), 'YYYY-MM-DD"T"HH24:MI:SS.FF3"Z"')
                 returning json)
             end
             order by rn returning json), json('[]')),
           count(*)
      into l_items, l_fetched
      from (
        select t.todo_id, t.owner_principal_id, t.title, t.notes, t.due_at, t.status,
               t.created_at, t.updated_at,
               row_number() over (order by t.created_at desc, t.todo_id desc) as rn
          from demo_todos t
         where t.owner_principal_id = l_owner
           and (   (l_status is null and t.status != 'DELETED')
                or t.status = l_status)
           and (l_pattern is null or lower(t.title) like l_pattern escape '\')
      )
     where rn > l_offset
       and rn <= l_offset + l_limit + 1;

    -- Issued after the read, into a local: it logs the read, which a query may not do.
    l_token := road_surface_api.new_token('list_todos');

    return road_surface_api.envelope(
      json_object('items'      value l_items,
                  'hasMore'    value case when l_fetched > l_limit then 'true' else 'false' end format json,
                  'limit'      value l_limit,
                  'offset'     value l_offset,
                  'count'      value least(l_fetched, l_limit),
                  'read_token' value l_token
                  returning json),
      c_scope);
  end list_todos;

  function get_todo(p_todo_id in number) return clob is
    l_owner number;
    l_token varchar2(40);
  begin
    road_ctx_pkg.require_permission('todo.get');
    if p_todo_id is null then
      road_surface_api.bad_request('The todo id must be a number');
    end if;
    begin
      select owner_principal_id into l_owner
        from demo_todos where todo_id = p_todo_id and status != 'DELETED';
    exception
      when no_data_found then
        raise_application_error(road_surface_api.c_not_found, 'Todo ' || p_todo_id || ' not found');
    end;
    if l_owner != road_ctx_pkg.principal_id and not road_ctx_pkg.has_permission('todo.list_all') then
      raise_application_error(road_surface_api.c_not_found, 'Todo ' || p_todo_id || ' not found');
    end if;
    l_token := road_surface_api.new_token('get_todo');
    return road_surface_api.envelope(
      json_object('todo' value build_todo_json(p_todo_id), 'read_token' value l_token returning json),
      c_scope);
  end get_todo;

  ---------------------------------------------------------------------------
  -- Actions
  ---------------------------------------------------------------------------

  function create_todo(p_body in json, p_idempotency_key in varchar2) return json is
    l_key      varchar2(400);
    l_title    varchar2(4000);
    l_notes    varchar2(4000);
    l_due      timestamp with time zone;
    l_prior    json;
    l_existing number;
    l_id       number;
    l_token    varchar2(40);
  begin
    road_ctx_pkg.require_permission('todo.create');
    l_key := require_key(p_idempotency_key);

    -- An attempt to nominate the owner is REFUSED, not ignored.
    if json_exists(p_body, '$.owner_principal_id') then
      road_surface_api.bad_request('owner_principal_id is taken from the session and must not be supplied');
    end if;
    l_title := trim(json_value(p_body, '$.title'));
    l_notes := json_value(p_body, '$.notes');
    if l_title is null or length(l_title) > 200 then
      road_surface_api.bad_request('title is required, up to 200 characters');
    end if;
    if length(l_notes) > 4000 then
      road_surface_api.bad_request('notes may be up to 4000 characters');
    end if;
    l_due := parse_ts(json_value(p_body, '$.due_at'), 'due_at');

    l_prior := road_decision_api.prior_outcome(c_create, l_key);
    if l_prior is not null then
      return l_prior;
    end if;

    savepoint sp_create_todo;
    select min(todo_id) into l_existing
      from demo_todos
     where owner_principal_id = road_ctx_pkg.principal_id
       and status = 'OPEN'
       and lower(title) = lower(l_title);
    if l_existing is not null then
      rollback to savepoint sp_create_todo;
      return road_surface_api.reject(c_create,
        road_decision_api.rejection('TITLE_TAKEN', 'You already have an open todo with this title.',
                                    false, ids(l_existing)),
        p_idempotency_key => l_key);
    end if;

    insert into demo_todos (owner_principal_id, title, notes, due_at)
    values (road_ctx_pkg.principal_id, l_title, l_notes, l_due)
    returning todo_id into l_id;

    l_token := road_surface_api.new_token('create_todo');
    return road_surface_api.accept(c_create,
      json_object('todo_id' value l_id, 'title' value l_title, 'status' value 'OPEN',
                  'read_token' value l_token returning json),
      ids(l_id), l_key);
  exception
    when dup_val_on_index then
      rollback to savepoint sp_create_todo;
      return road_decision_api.prior_outcome(c_create, l_key);
  end create_todo;

  -- The four actions on a todo the caller read share one shape, so they share one implementation;
  -- p_action says which. Only the owner may act: another owner's todo, a deleted one and a missing
  -- one are refused alike.
  function decide(p_action in varchar2, p_todo_id in number, p_body in json) return json is
    l_token_text varchar2(100) := json_value(p_body, '$.read_token');
    l_token      raw(16);
    l_key        varchar2(400);
    l_prior      json;
    l_row        demo_todos%rowtype;
    l_title      varchar2(4000);
    l_notes      varchar2(4000);
    l_due        timestamp with time zone;
    l_set_title  boolean := false;
    l_set_notes  boolean := false;
    l_set_due    boolean := false;
    l_new_token  varchar2(40);
    l_status     varchar2(10 char);
  begin
    if p_todo_id is null then
      road_surface_api.bad_request('The todo id must be a number');
    end if;
    l_token := road_surface_api.token_raw(l_token_text);
    l_key := road_surface_api.natural_key(p_todo_id, l_token_text);

    if p_action = c_revise then
      l_set_title := json_exists(p_body, '$.title');
      l_set_notes := json_exists(p_body, '$.notes');
      l_set_due   := json_exists(p_body, '$.due_at');
      if not (l_set_title or l_set_notes or l_set_due) then
        road_surface_api.bad_request('Give at least one of title, notes and due_at');
      end if;
      if l_set_title then
        l_title := trim(json_value(p_body, '$.title'));
        if l_title is null or length(l_title) > 200 then
          road_surface_api.bad_request('title must be 1 to 200 characters');
        end if;
      end if;
      if l_set_notes then
        l_notes := json_value(p_body, '$.notes');
        if length(l_notes) > 4000 then
          road_surface_api.bad_request('notes may be up to 4000 characters');
        end if;
      end if;
      if l_set_due then
        l_due := parse_ts(json_value(p_body, '$.due_at'), 'due_at');
      end if;
    end if;

    l_prior := road_decision_api.prior_outcome(p_action, l_key);
    if l_prior is not null then
      return l_prior;
    end if;

    savepoint sp_decide_todo;

    -- Re-read and lock: the decision is made on the state as it is now, not as the caller saw it.
    begin
      select * into l_row
        from demo_todos
       where todo_id = p_todo_id
         and owner_principal_id = road_ctx_pkg.principal_id
         and status != 'DELETED'
         for update;
    exception
      when no_data_found then
        rollback to savepoint sp_decide_todo;
        return road_surface_api.record_not_found(p_action, 'TODO_NOT_FOUND', 'No such todo.', l_key);
    end;

    if not road_surface_api.is_fresh(l_token, c_entity, p_todo_id, l_row.updated_at) then
      rollback to savepoint sp_decide_todo;
      return road_surface_api.reject(p_action,
        road_decision_api.rejection('STALE_TOKEN',
          'The todo changed since you read it. Read it again and decide again.', true, ids(p_todo_id)),
        p_idempotency_key => l_key);
    end if;

    if p_action in (c_revise, c_complete) and l_row.status = 'DONE' then
      rollback to savepoint sp_decide_todo;
      return road_surface_api.reject(p_action,
        road_decision_api.rejection('TODO_DONE', 'The todo is done. Reopen it first.', false, ids(p_todo_id)),
        p_idempotency_key => l_key);
    end if;
    if p_action = c_reopen and l_row.status != 'DONE' then
      rollback to savepoint sp_decide_todo;
      return road_surface_api.reject(p_action,
        road_decision_api.rejection('TODO_NOT_DONE', 'The todo is not done, so there is nothing to reopen.',
                                    false, ids(p_todo_id)),
        p_idempotency_key => l_key);
    end if;

    if p_action = c_revise then
      update demo_todos
         set title  = case when l_set_title then l_title else title end,
             notes  = case when l_set_notes then l_notes else notes end,
             due_at = case when l_set_due then l_due else due_at end
       where todo_id = p_todo_id;
    elsif p_action = c_complete then
      update demo_todos set status = 'DONE' where todo_id = p_todo_id;
    elsif p_action = c_reopen then
      update demo_todos set status = 'OPEN' where todo_id = p_todo_id;
    else
      update demo_todos set status = 'DELETED' where todo_id = p_todo_id;
      return road_surface_api.accept(p_action, json_object('todo_id' value p_todo_id returning json),
                                     ids(p_todo_id), l_key);
    end if;

    -- A token for the todo as it is now, so a caller can act on it again without another read.
    l_new_token := road_surface_api.new_token(p_action);
    select title, status into l_title, l_status from demo_todos where todo_id = p_todo_id;
    return road_surface_api.accept(p_action,
      json_object('todo_id' value p_todo_id, 'title' value l_title, 'status' value l_status,
                  'read_token' value l_new_token returning json),
      ids(p_todo_id), l_key);
  exception
    when dup_val_on_index then
      rollback to savepoint sp_decide_todo;
      return road_decision_api.prior_outcome(p_action, l_key);
  end decide;

  function revise_todo(p_todo_id in number, p_body in json) return json is
  begin
    road_ctx_pkg.require_permission('todo.update');
    return decide(c_revise, p_todo_id, p_body);
  end revise_todo;

  function complete_todo(p_todo_id in number, p_body in json) return json is
  begin
    road_ctx_pkg.require_permission('todo.update');
    return decide(c_complete, p_todo_id, p_body);
  end complete_todo;

  function reopen_todo(p_todo_id in number, p_body in json) return json is
  begin
    road_ctx_pkg.require_permission('todo.update');
    return decide(c_reopen, p_todo_id, p_body);
  end reopen_todo;

  function delete_todo(p_todo_id in number, p_body in json) return json is
  begin
    road_ctx_pkg.require_permission('todo.delete');
    return decide(c_delete, p_todo_id, p_body);
  end delete_todo;

  function purge_todos(p_body in json, p_idempotency_key in varchar2) return json is
    l_key    varchar2(400);
    l_before timestamp with time zone;
    l_prior  json;
    l_purged number;
  begin
    -- todo.purge is RESERVED. Nothing here reads that flag: the reservation governs who may attach
    -- the permission to a role, not what the action does once someone holds it. The guard is
    -- road_reserved_composition, in the database, one layer down.
    road_ctx_pkg.require_permission('todo.purge');
    l_key := require_key(p_idempotency_key);
    if json_value(p_body, '$.before') is null then
      road_surface_api.bad_request('before is required');
    end if;
    l_before := parse_ts(json_value(p_body, '$.before'), 'before');

    l_prior := road_decision_api.prior_outcome(c_purge, l_key);
    if l_prior is not null then
      return l_prior;
    end if;

    savepoint sp_purge_todos;
    if l_before > systimestamp then
      rollback to savepoint sp_purge_todos;
      return road_surface_api.reject(c_purge,
        road_decision_api.rejection('PURGE_CUTOFF_IN_FUTURE',
          'The cutoff is in the future, which would purge todos that were only just finished.', false),
        p_idempotency_key => l_key);
    end if;

    -- Across ALL owners, with no ownership filter: that is what makes this the dangerous operation
    -- worth reserving. The decision record is its audit trail.
    delete from demo_todos
     where status in ('DONE', 'DELETED')
       and updated_at < l_before;
    l_purged := sql%rowcount;

    return road_surface_api.accept(c_purge, json_object('purged' value l_purged returning json),
                                   p_idempotency_key => l_key);
  exception
    when dup_val_on_index then
      rollback to savepoint sp_purge_todos;
      return road_decision_api.prior_outcome(c_purge, l_key);
  end purge_todos;

end demo_todo_api;
/
