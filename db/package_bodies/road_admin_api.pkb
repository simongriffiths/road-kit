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
    insert into road_role_permissions (role_name, permission_name)
    select p_role_name, p.permission_name
      from road_permissions p
     where p.permission_name not like 'road.%'
       and not exists (
             select 1
               from road_role_permissions x
              where x.role_name = p_role_name
                and x.permission_name = p.permission_name
           );
  end grant_all_app_permissions;

end road_admin_api;
/
