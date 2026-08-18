whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback

begin
  ords.enable_schema(
    p_enabled             => true,
    p_schema              => user,
    p_url_mapping_type    => 'BASE_PATH',
    p_url_mapping_pattern => 'hello_api',
    p_auto_rest_auth      => false
  );
exception
  when others then
    null;
end;
/

begin
  ords.delete_module(p_module_name => 'hello_api.session');
exception
  when others then
    null;
end;
/

begin
  ords.define_module(
    p_module_name    => 'hello_api.session',
    p_base_path      => '/api/v1/session/',
    p_items_per_page => 25,
    p_status         => 'PUBLISHED',
    p_comments       => 'ROAD protected session module'
  );

  ords.define_template(
    p_module_name => 'hello_api.session',
    p_pattern     => 'me/',
    p_comments    => 'Protected session endpoint'
  );

  -- Converted from a collection_item query to PL/SQL by the spec patch 06 backport. A SELECT-based
  -- handler cannot establish session context or return 401 on failure, and this endpoint is the
  -- one place the UI asks "who am I" -- so it should answer from the resolved principal rather
  -- than by echoing the token's subject back.
  --
  -- Every field the previous shape returned is still returned, with the same names and the same
  -- values; principal_id, roles and permissions are added. The existing endpoint assertions check
  -- for fragments, so additive fields do not break them.
  ords.define_handler(
    p_module_name => 'hello_api.session',
    p_pattern     => 'me/',
    p_method      => 'GET',
    p_source_type => ords.source_type_plsql,
    -- NOTE the q'~ ~' delimiter instead of the repo's usual q'[ ]'. This handler's body contains
    -- json('[]'), and the two characters ]' terminate a q'[ ]' literal -- so the PL/SQL silently
    -- ended early, the remainder leaked out as SQL*Plus input, and the only symptom was
    -- "SP2-0552: Bind variable CURRENT_USER not declared" from a completely different line.
    p_source      => q'~
      declare
        l_response       json;
        l_status_code    number;
        l_error_response clob;
        l_principal_id   number;
        l_roles          json;
        l_permissions    json;
      begin
        if not road_ctx_pkg.begin_request(:current_user) then
          owa_util.status_line(401);
          htp.p('{"error":"UNAUTHORIZED","message":"No session could be established"}');
          return;
        end if;
        -- No require_permission: reading your own identity is inherently self-scoped, and road-kit
        -- ships no application permissions to gate it with. An adopting application may add one --
        -- road-cal gates this on session.read as part of its own taxonomy -- but the framework only
        -- requires that a session exists.
        l_principal_id := road_ctx_pkg.principal_id;

        -- Built as locals rather than inline scalar subqueries: NVL does not accept JSON-typed
        -- arguments inside SQL, and JSON_ARRAYAGG returns NULL rather than an empty array when the
        -- principal holds nothing. The UI expects [] in that case, not null.
        select json_arrayagg(pr.role_name order by pr.role_name returning json)
          into l_roles
          from road_principal_roles pr
         where pr.principal_id = l_principal_id;

        -- JSON_ARRAYAGG does not accept DISTINCT, so de-duplication happens in an inline view. A
        -- principal holding two roles that share a permission would otherwise list it twice.
        select json_arrayagg(x.permission_name order by x.permission_name returning json)
          into l_permissions
          from (
            select distinct rp.permission_name
              from road_principal_roles pr
              join road_role_permissions rp on rp.role_name = pr.role_name
             where pr.principal_id = l_principal_id
          ) x;

        if l_roles is null then
          l_roles := json('[]');
        end if;
        if l_permissions is null then
          l_permissions := json('[]');
        end if;

        select json_object(
                 'principal'     value session_api.get_principal(:current_user),
                 'issuer'        value road_ctx_pkg.issuer,
                 'audience'      value session_api.get_audience,
                 'scope'         value session_api.get_scope,
                 'authenticated' value case when road_ctx_pkg.is_authenticated then 'true'
                                            else 'false' end,
                 'current_user'  value :current_user,
                 'db_user'       value sys_context('USERENV', 'CURRENT_USER'),
                 'principal_id'  value l_principal_id,
                 'roles'         value l_roles,
                 'permissions'   value l_permissions
                 returning json
               )
          into l_response
          from dual;

        owa_util.status_line(200);
        htp.p(json_serialize(l_response));
      exception
        when others then
          if sqlcode between -20999 and -20000 then
            error_api.handle_known(sqlcode, sqlerrm, l_status_code, l_error_response);
          else
            error_api.handle_unknown(sqlerrm, dbms_utility.format_error_backtrace,
                                     'session.me', l_status_code, l_error_response);
          end if;
          owa_util.status_line(l_status_code);
          htp.p(l_error_response);
      end;
    ~',
    p_comments    => 'Returns the authenticated session identity, roles and effective permissions'
  );

  commit;
end;
/
