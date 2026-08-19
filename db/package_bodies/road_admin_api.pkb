create or replace package body road_admin_api as

  c_err_validation constant number := -20001;
  c_err_not_found  constant number := -20004;

  procedure assert_role_exists(p_role_name in varchar2) is
    l_count number;
  begin
    select count(*) into l_count from road_roles where role_name = p_role_name;
    if l_count = 0 then
      raise_application_error(c_err_not_found, 'Role not found: ' || p_role_name);
    end if;
  end assert_role_exists;

  procedure assert_principal_exists(p_principal_id in number) is
    l_count number;
  begin
    select count(*) into l_count from road_principals where principal_id = p_principal_id;
    if l_count = 0 then
      raise_application_error(c_err_not_found, 'Principal not found: ' || p_principal_id);
    end if;
  end assert_principal_exists;

  function is_reserved(p_role_name in varchar2) return boolean is
    l_reserved road_roles.is_reserved%type;
  begin
    select is_reserved into l_reserved from road_roles where role_name = p_role_name;
    return l_reserved = 'Y';
  exception
    when no_data_found then
      return false;
  end is_reserved;

  procedure assert_permission_exists(p_permission_name in varchar2) is
    l_count number;
  begin
    select count(*) into l_count from road_permissions where permission_name = p_permission_name;
    if l_count = 0 then
      raise_application_error(c_err_not_found, 'Permission not found: ' || p_permission_name);
    end if;
  end assert_permission_exists;

  function permission_is_reserved(p_permission_name in varchar2) return boolean is
    l_reserved road_permissions.is_reserved%type;
  begin
    select is_reserved into l_reserved
      from road_permissions
     where permission_name = p_permission_name;
    return l_reserved = 'Y';
  exception
    when no_data_found then
      return false;
  end permission_is_reserved;

  -- The two-tier split made explicit. road.role.grant lets a user_admin manage ordinary roles;
  -- touching a RESERVED role additionally needs road.role.define, which only road.system_admin
  -- holds. Nothing in the table structure prevents a user_admin granting road.system_admin --
  -- foreign keys do not know what the rows mean -- so it has to be a check, and a tested one.
  procedure assert_may_manage(p_role_name in varchar2) is
  begin
    if is_reserved(p_role_name) then
      road_ctx_pkg.require_permission('road.role.define');
    end if;
  end assert_may_manage;

  function get_principal_roles(p_request in json) return json is
    l_principal_id number;
    l_result       json;
  begin
    road_ctx_pkg.require_permission('road.role.grant');

    l_principal_id := json_value(p_request, '$.principal_id' returning number);
    if l_principal_id is null then
      raise_application_error(c_err_validation, 'principal_id is required');
    end if;
    assert_principal_exists(l_principal_id);

    select json_object(
             'principal_id' value p.principal_id,
             'subject'      value p.subject,
             'status'       value p.status,
             'roles'        value nvl((
               select json_arrayagg(
                        json_object(
                          'role_name'  value pr.role_name,
                          'granted_at' value to_char(pr.granted_at, 'YYYY-MM-DD"T"HH24:MI:SSTZH:TZM'),
                          'granted_by' value pr.granted_by
                        )
                        order by pr.role_name returning json
                      )
                 from road_principal_roles pr
                where pr.principal_id = p.principal_id
             ), json('[]'))
             returning json
           )
      into l_result
      from road_principals p
     where p.principal_id = l_principal_id;

    return l_result;
  end get_principal_roles;

  function grant_role(p_request in json) return json is
    l_principal_id number;
    l_role_name    varchar2(64 char);
    l_granted_by   number;
    l_existing     number;
    l_granted      boolean := false;
  begin
    road_ctx_pkg.require_permission('road.role.grant');

    l_principal_id := json_value(p_request, '$.principal_id' returning number);
    l_role_name    := json_value(p_request, '$.role_name' returning varchar2(64));

    if l_principal_id is null or l_role_name is null then
      raise_application_error(c_err_validation, 'principal_id and role_name are required');
    end if;

    assert_principal_exists(l_principal_id);
    assert_role_exists(l_role_name);
    assert_may_manage(l_role_name);

    -- Never from the request body. A caller who could nominate granted_by could forge the audit
    -- trail of who authorised a privilege escalation, which is the one field that would expose it.
    l_granted_by := road_ctx_pkg.principal_id;

    select count(*)
      into l_existing
      from road_principal_roles
     where principal_id = l_principal_id
       and role_name = l_role_name;

    if l_existing = 0 then
      insert into road_principal_roles (principal_id, role_name, granted_by)
      values (l_principal_id, l_role_name, l_granted_by);
      l_granted := true;
    end if;

    return json_object(
             'principal_id' value l_principal_id,
             'role_name'    value l_role_name,
             'granted'      value l_granted,
             'granted_by'   value l_granted_by
             returning json
           );
  end grant_role;

  function revoke_role(p_request in json) return json is
    l_principal_id number;
    l_role_name    varchar2(64 char);
    l_holders      number;
    l_revoked      boolean := false;
  begin
    road_ctx_pkg.require_permission('road.role.revoke');

    l_principal_id := json_value(p_request, '$.principal_id' returning number);
    l_role_name    := json_value(p_request, '$.role_name' returning varchar2(64));

    if l_principal_id is null or l_role_name is null then
      raise_application_error(c_err_validation, 'principal_id and role_name are required');
    end if;

    assert_principal_exists(l_principal_id);
    assert_role_exists(l_role_name);
    assert_may_manage(l_role_name);

    -- Refuse to remove the last system administrator. "The auth system works and nobody can
    -- administer it" is the failure mode patch section 10 question 1 exists to prevent, and it is
    -- reachable by an ordinary revoke as easily as by a bad deploy.
    if l_role_name = 'road.system_admin' then
      select count(*)
        into l_holders
        from road_principal_roles
       where role_name = 'road.system_admin';

      if l_holders <= 1 then
        raise_application_error(
          c_err_validation,
          'Refusing to revoke the last road.system_admin - grant it to another principal first'
        );
      end if;
    end if;

    delete from road_principal_roles
     where principal_id = l_principal_id
       and role_name = l_role_name;

    l_revoked := sql%rowcount > 0;

    return json_object(
             'principal_id' value l_principal_id,
             'role_name'    value l_role_name,
             'revoked'      value l_revoked
             returning json
           );
  end revoke_role;

  function get_roles(p_request in json default null) return json is
    l_result json;
  begin
    road_ctx_pkg.require_permission('road.role.grant');

    select json_object(
             'roles' value nvl((
               select json_arrayagg(
                        json_object(
                          'role_name'    value r.role_name,
                          'display_name' value r.display_name,
                          'description'  value r.description,
                          'is_reserved'  value r.is_reserved,
                          'permissions'  value nvl((
                            select json_arrayagg(rp.permission_name
                                                 order by rp.permission_name returning json)
                              from road_role_permissions rp
                             where rp.role_name = r.role_name
                          ), json('[]'))
                        )
                        order by r.role_name returning json
                      )
                 from road_roles r
             ), json('[]'))
             returning json
           )
      into l_result
      from dual;

    return l_result;
  end get_roles;

  -- A search term is user input reaching a LIKE pattern, so its wildcards have to be neutralised or
  -- a user typing '%' silently matches everything and a user typing '_' matches one of anything.
  -- Escape the escape character first, or escaping the wildcards re-introduces it.
  function like_term(p_term in varchar2) return varchar2 is
  begin
    return '%' || replace(replace(replace(lower(p_term), '\', '\\'), '%', '\%'), '_', '\_') || '%';
  end like_term;

  function get_principals(p_request in json default null) return json is
    c_default_limit constant number := 25;
    c_max_limit     constant number := 100;

    l_offset  number;
    l_limit   number;
    l_q       varchar2(4000 char);
    l_status  varchar2(20 char);
    l_pattern varchar2(4000 char);

    l_items   json;
    l_fetched number;
  begin
    road_ctx_pkg.require_permission('road.role.grant');

    l_offset := nvl(json_value(p_request, '$.offset' returning number), 0);
    l_limit  := nvl(json_value(p_request, '$.limit'  returning number), c_default_limit);
    l_q      := json_value(p_request, '$.q'      returning varchar2(4000));
    l_status := json_value(p_request, '$.status' returning varchar2(20));

    -- Clamped rather than rejected: an out-of-range page size is a client bug, not a caller error,
    -- and an unclamped limit is a denial-of-service parameter.
    l_offset := greatest(nvl(l_offset, 0), 0);
    l_limit  := least(greatest(nvl(l_limit, c_default_limit), 1), c_max_limit);

    -- An unrecognised status IS rejected, because silently ignoring it would return the unfiltered
    -- list and the caller would believe it had filtered.
    if l_status is not null
       and l_status not in ('ACTIVE', 'SUSPENDED', 'RETIRED') then
      raise_application_error(
        c_err_validation,
        'status must be one of ACTIVE, SUSPENDED, RETIRED: ' || l_status
      );
    end if;

    if l_q is not null and length(trim(l_q)) > 0 then
      l_pattern := like_term(trim(l_q));
    end if;

    -- One pass. row_number over the filtered set lets the page and the "is there another page"
    -- answer come from the same predicate -- two statements would mean two copies of the WHERE
    -- clause, which is exactly the pair that drifts. limit+1 rows are counted and the extra one is
    -- dropped from the array by the CASE (json_arrayagg is ABSENT ON NULL by default), so hasMore
    -- costs no second scan and no count(*) over the whole table.
    select nvl(json_arrayagg(
             case when rn <= l_limit then
               json_object(
                 'principal_id' value principal_id,
                 'issuer'       value issuer,
                 'subject'      value subject,
                 'email'        value email,
                 'display_name' value display_name,
                 'status'       value status,
                 'created_at'   value to_char(created_at, 'YYYY-MM-DD"T"HH24:MI:SSTZH:TZM'),
                 'roles'        value nvl((
                   -- {role_name, is_reserved} objects, not bare names (spec-patch-07 section 8.1):
                   -- PrincipalsPanel.tsx used to style pills by testing role.startsWith('road.'),
                   -- justified as cosmetic-only because this endpoint returned names only. Under
                   -- rule 6 that justification is weaker than it reads -- the flag is the answer,
                   -- the prefix is a convention it happens to follow today -- so the panel now
                   -- reads the flag, like PrincipalRolesDialog already does.
                   select json_arrayagg(
                            json_object('role_name' value pr.role_name, 'is_reserved' value r.is_reserved)
                            order by pr.role_name returning json
                          )
                     from road_principal_roles pr, road_roles r
                    where pr.principal_id = paged.principal_id
                      and r.role_name = pr.role_name
                 ), json('[]'))
                 returning json
               )
             end
             order by rn returning json
           ), json('[]')),
           count(*)
      into l_items, l_fetched
      from (
        select p.principal_id,
               p.issuer,
               p.subject,
               p.email,
               p.display_name,
               p.status,
               p.created_at,
               row_number() over (
                 order by lower(coalesce(p.display_name, p.subject)), p.principal_id
               ) - l_offset as rn
          from road_principals p
         where (l_status is null or p.status = l_status)
           and (l_pattern is null
                or lower(p.display_name) like l_pattern escape '\'
                or lower(p.email)        like l_pattern escape '\'
                or lower(p.subject)      like l_pattern escape '\')
      ) paged
     where rn between 1 and l_limit + 1;

    return json_object(
             'items'   value l_items,
             'hasMore' value case when l_fetched > l_limit then 'true' else 'false' end
                             format json,
             'limit'   value l_limit,
             'offset'  value l_offset,
             'count'   value least(l_fetched, l_limit)
             returning json
           );
  end get_principals;

  function define_role(p_request in json) return json is
    l_role_name    varchar2(64 char);
    l_display_name varchar2(255 char);
    l_description  varchar2(4000 char);
    l_existing     number;
  begin
    road_ctx_pkg.require_permission('road.role.define');

    l_role_name    := json_value(p_request, '$.role_name' returning varchar2(64));
    l_display_name := json_value(p_request, '$.display_name' returning varchar2(255));
    l_description  := json_value(p_request, '$.description' returning varchar2(4000));

    if l_role_name is null then
      raise_application_error(c_err_validation, 'role_name is required');
    end if;

    -- road. is the framework's reserved namespace (rule 5). An application defining a road.* role
    -- would be claiming framework authority for an application concern, and the reserved flag would
    -- then mean two different things.
    if lower(l_role_name) like 'road.%' then
      raise_application_error(
        c_err_validation,
        'The road. namespace is reserved for the framework: ' || l_role_name
      );
    end if;

    select count(*) into l_existing from road_roles where role_name = l_role_name;
    if l_existing > 0 then
      raise_application_error(c_err_validation, 'Role already exists: ' || l_role_name);
    end if;

    insert into road_roles (role_name, display_name, description, is_reserved)
    values (l_role_name, l_display_name, l_description, 'N');

    return json_object(
             'role_name'    value l_role_name,
             'display_name' value l_display_name,
             'description'  value l_description,
             'is_reserved'  value 'N'
             returning json
           );
  end define_role;

  procedure grant_all_app_permissions(p_role_name in varchar2) is
  begin
    assert_role_exists(p_role_name);

    -- Explicit rows, written once, for the permissions that exist RIGHT NOW. Anything added after
    -- this runs is not acquired -- that is the point (rule 4), not a limitation.
    --
    -- attached_by is written NULL explicitly (spec-patch-07 section 10 question 3) -- this is the
    -- deploy-attached case road_reserved_composition depends on being able to tell apart from a
    -- session attach via attach_permission below.
    insert into road_role_permissions (role_name, permission_name, attached_by)
    select p_role_name, p.permission_name, null
      from road_permissions p
     where p.permission_name not like 'road.%'
       and p.is_reserved = 'N'
       and not exists (
             select 1
               from road_role_permissions x
              where x.role_name = p_role_name
                and x.permission_name = p.permission_name
           );
  end grant_all_app_permissions;

  function get_permissions(p_request in json default null) return json is
    l_result json;
  begin
    road_ctx_pkg.require_permission('road.role.compose');

    select json_object(
             'permissions' value nvl((
               select json_arrayagg(
                        json_object(
                          'permission_name' value p.permission_name,
                          'description'     value p.description,
                          'is_reserved'     value p.is_reserved,
                          'roles'           value nvl((
                            select json_arrayagg(rp.role_name order by rp.role_name returning json)
                              from road_role_permissions rp
                             where rp.permission_name = p.permission_name
                          ), json('[]'))
                        )
                        order by p.permission_name returning json
                      )
                 from road_permissions p
             ), json('[]'))
             returning json
           )
      into l_result
      from dual;

    return l_result;
  end get_permissions;

  -- Shared refusal for attach/detach: a reserved permission or a reserved role, as a flat refusal
  -- rather than the road.role.define escalation tier assert_may_manage uses for roles. Composing
  -- the framework's own authority is composed at deploy time only, enforced in the database by
  -- road_reserved_composition -- this check exists to give a clean 403 on the ordinary path rather
  -- than surfacing the assertion's ORA-08601 (spec-patch-07 section 5.3, 5.5).
  procedure assert_may_compose(p_role_name in varchar2, p_permission_name in varchar2) is
  begin
    if permission_is_reserved(p_permission_name) then
      raise_application_error(
        road_ctx_pkg.c_forbidden,
        'Permission is reserved and cannot be composed at runtime: ' || p_permission_name
      );
    end if;
    if is_reserved(p_role_name) then
      raise_application_error(
        road_ctx_pkg.c_forbidden,
        'Role is reserved; its composition is framework-owned: ' || p_role_name
      );
    end if;
  end assert_may_compose;

  function attach_permission(p_request in json) return json is
    l_role_name       varchar2(64 char);
    l_permission_name varchar2(64 char);
    l_attached_by     number;
    l_existing        number;
    l_attached        boolean := false;
  begin
    road_ctx_pkg.require_permission('road.role.compose');

    l_role_name       := json_value(p_request, '$.role_name' returning varchar2(64));
    l_permission_name := json_value(p_request, '$.permission_name' returning varchar2(64));

    if l_role_name is null or l_permission_name is null then
      raise_application_error(c_err_validation, 'role_name and permission_name are required');
    end if;

    assert_role_exists(l_role_name);
    assert_permission_exists(l_permission_name);
    assert_may_compose(l_role_name, l_permission_name);

    -- Never from the request body -- see the package spec comment: a caller who could nominate
    -- attached_by could forge the audit trail of who authorised an escalation.
    l_attached_by := road_ctx_pkg.principal_id;

    select count(*)
      into l_existing
      from road_role_permissions
     where role_name = l_role_name
       and permission_name = l_permission_name;

    if l_existing = 0 then
      insert into road_role_permissions (role_name, permission_name, attached_by)
      values (l_role_name, l_permission_name, l_attached_by);
      l_attached := true;
    end if;

    return json_object(
             'role_name'       value l_role_name,
             'permission_name' value l_permission_name,
             'attached'        value l_attached
             returning json
           );
  end attach_permission;

  function detach_permission(p_request in json) return json is
    l_role_name       varchar2(64 char);
    l_permission_name varchar2(64 char);
    l_detached        boolean := false;
  begin
    road_ctx_pkg.require_permission('road.role.compose');

    l_role_name       := json_value(p_request, '$.role_name' returning varchar2(64));
    l_permission_name := json_value(p_request, '$.permission_name' returning varchar2(64));

    if l_role_name is null or l_permission_name is null then
      raise_application_error(c_err_validation, 'role_name and permission_name are required');
    end if;

    assert_role_exists(l_role_name);
    assert_permission_exists(l_permission_name);
    assert_may_compose(l_role_name, l_permission_name);

    -- No last-holder guard here for road.role.grant, unlike revoke_role's for road.system_admin --
    -- road_admin_reachable enforces it in the database, and it must: this table has other writers
    -- (grant_all_app_permissions) that a package-level check here would not cover.
    delete from road_role_permissions
     where role_name = l_role_name
       and permission_name = l_permission_name;

    l_detached := sql%rowcount > 0;

    return json_object(
             'role_name'       value l_role_name,
             'permission_name' value l_permission_name,
             'detached'        value l_detached
             returning json
           );
  end detach_permission;

end road_admin_api;
/
