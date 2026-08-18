whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback

-- ROAD role administration (spec-patch-06 section 5).
--
-- Framework surface. road-cal additionally mounts POST /admin/purge/ here as its worked example of
-- an admin-only operation; that handler is deliberately NOT part of the backport, because
-- events.purge is application-shaped and road-kit ships no application.
--
-- Every handler here follows the same two-line preamble: establish session context, or 401. ORDS
-- exposes no schema-callable pre-dispatch hook, so this is per handler by necessity
-- (spec-patch-06 section 6.3) and bin/check-handler-coverage.sh is what stops one being forgotten.
--
-- The handlers are thin. They bind path parameters and the body into one JSON payload and call
-- road_admin_api, which enforces the permission requirement itself -- so the authorisation travels
-- with the operation rather than living only in the handler.

begin
  ords.delete_module(p_module_name => 'road_cal_api.admin');
exception
  when others then
    null;
end;
/

begin
  ords.define_module(
    p_module_name    => 'road_cal_api.admin',
    p_base_path      => '/api/v1/admin/',
    p_items_per_page => 25,
    p_status         => 'PUBLISHED',
    p_comments       => 'ROAD role administration'
  );

  ---------------------------------------------------------------------------
  -- GET /admin/roles/
  ---------------------------------------------------------------------------
  ords.define_template(
    p_module_name => 'road_cal_api.admin',
    p_pattern     => 'roles/',
    p_comments    => 'Role catalogue'
  );

  ords.define_handler(
    p_module_name => 'road_cal_api.admin',
    p_pattern     => 'roles/',
    p_method      => 'GET',
    p_source_type => ords.source_type_plsql,
    p_source      => q'[
      declare
        l_response       json;
        l_status_code    number;
        l_error_response clob;
      begin
        if not road_ctx_pkg.begin_request(:current_user) then
          owa_util.status_line(401);
          htp.p('{"error":"UNAUTHORIZED","message":"No session could be established"}');
          return;
        end if;
        l_response := road_admin_api.get_roles;
        owa_util.status_line(200);
        htp.p(json_serialize(l_response));
      exception
        when others then
          if sqlcode between -20999 and -20000 then
            error_api.handle_known(sqlcode, sqlerrm, l_status_code, l_error_response);
          else
            error_api.handle_unknown(sqlerrm, dbms_utility.format_error_backtrace,
                                     'admin.roles.list', l_status_code, l_error_response);
          end if;
          owa_util.status_line(l_status_code);
          htp.p(l_error_response);
      end;
    ]',
    p_comments    => 'Lists roles and the permissions they compose'
  );

  ords.define_handler(
    p_module_name => 'road_cal_api.admin',
    p_pattern     => 'roles/',
    p_method      => 'POST',
    p_source_type => ords.source_type_plsql,
    p_source      => q'[
      declare
        l_request        json;
        l_response       json;
        l_status_code    number;
        l_error_response clob;
      begin
        if not road_ctx_pkg.begin_request(:current_user) then
          owa_util.status_line(401);
          htp.p('{"error":"UNAUTHORIZED","message":"No session could be established"}');
          return;
        end if;
        l_request := json(:body_text);
        l_response := road_admin_api.define_role(l_request);
        owa_util.status_line(201);
        htp.p(json_serialize(l_response));
      exception
        when others then
          if sqlcode between -20999 and -20000 then
            error_api.handle_known(sqlcode, sqlerrm, l_status_code, l_error_response);
          else
            error_api.handle_unknown(sqlerrm, dbms_utility.format_error_backtrace,
                                     'admin.roles.define', l_status_code, l_error_response);
          end if;
          owa_util.status_line(l_status_code);
          htp.p(l_error_response);
      end;
    ]',
    p_comments    => 'Defines a new application role'
  );

  ---------------------------------------------------------------------------
  -- GET / POST /admin/principals/:principal_id/roles/
  ---------------------------------------------------------------------------
  ords.define_template(
    p_module_name => 'road_cal_api.admin',
    p_pattern     => 'principals/:principal_id/roles/',
    p_comments    => 'Roles held by one principal'
  );

  ords.define_handler(
    p_module_name => 'road_cal_api.admin',
    p_pattern     => 'principals/:principal_id/roles/',
    p_method      => 'GET',
    p_source_type => ords.source_type_plsql,
    p_source      => q'[
      declare
        l_request        json;
        l_response       json;
        l_status_code    number;
        l_error_response clob;
      begin
        if not road_ctx_pkg.begin_request(:current_user) then
          owa_util.status_line(401);
          htp.p('{"error":"UNAUTHORIZED","message":"No session could be established"}');
          return;
        end if;
        select json_object('principal_id' value to_number(:principal_id) returning json)
          into l_request from dual;
        l_response := road_admin_api.get_principal_roles(l_request);
        owa_util.status_line(200);
        htp.p(json_serialize(l_response));
      exception
        when others then
          if sqlcode between -20999 and -20000 then
            error_api.handle_known(sqlcode, sqlerrm, l_status_code, l_error_response);
          else
            error_api.handle_unknown(sqlerrm, dbms_utility.format_error_backtrace,
                                     'admin.principal.roles.list', l_status_code, l_error_response);
          end if;
          owa_util.status_line(l_status_code);
          htp.p(l_error_response);
      end;
    ]',
    p_comments    => 'Lists the roles held by a principal'
  );

  ords.define_handler(
    p_module_name => 'road_cal_api.admin',
    p_pattern     => 'principals/:principal_id/roles/',
    p_method      => 'POST',
    p_source_type => ords.source_type_plsql,
    p_source      => q'[
      declare
        l_request        json;
        l_response       json;
        l_status_code    number;
        l_error_response clob;
      begin
        if not road_ctx_pkg.begin_request(:current_user) then
          owa_util.status_line(401);
          htp.p('{"error":"UNAUTHORIZED","message":"No session could be established"}');
          return;
        end if;
        -- principal_id comes from the path, role_name from the body. granted_by is deliberately
        -- NOT accepted from either: road_admin_api takes it from the session.
        select json_object(
                 'principal_id' value to_number(:principal_id),
                 'role_name'    value json_value(:body_text, '$.role_name')
                 returning json
               )
          into l_request from dual;
        l_response := road_admin_api.grant_role(l_request);
        owa_util.status_line(200);
        htp.p(json_serialize(l_response));
      exception
        when others then
          if sqlcode between -20999 and -20000 then
            error_api.handle_known(sqlcode, sqlerrm, l_status_code, l_error_response);
          else
            error_api.handle_unknown(sqlerrm, dbms_utility.format_error_backtrace,
                                     'admin.principal.roles.grant', l_status_code, l_error_response);
          end if;
          owa_util.status_line(l_status_code);
          htp.p(l_error_response);
      end;
    ]',
    p_comments    => 'Grants a role to a principal'
  );

  ---------------------------------------------------------------------------
  -- DELETE /admin/principals/:principal_id/roles/:role_name/
  ---------------------------------------------------------------------------
  ords.define_template(
    p_module_name => 'road_cal_api.admin',
    p_pattern     => 'principals/:principal_id/roles/:role_name/',
    p_comments    => 'One role grant'
  );

  ords.define_handler(
    p_module_name => 'road_cal_api.admin',
    p_pattern     => 'principals/:principal_id/roles/:role_name/',
    p_method      => 'DELETE',
    p_source_type => ords.source_type_plsql,
    p_source      => q'[
      declare
        l_request        json;
        l_response       json;
        l_status_code    number;
        l_error_response clob;
      begin
        if not road_ctx_pkg.begin_request(:current_user) then
          owa_util.status_line(401);
          htp.p('{"error":"UNAUTHORIZED","message":"No session could be established"}');
          return;
        end if;
        select json_object(
                 'principal_id' value to_number(:principal_id),
                 'role_name'    value :role_name
                 returning json
               )
          into l_request from dual;
        l_response := road_admin_api.revoke_role(l_request);
        owa_util.status_line(200);
        htp.p(json_serialize(l_response));
      exception
        when others then
          if sqlcode between -20999 and -20000 then
            error_api.handle_known(sqlcode, sqlerrm, l_status_code, l_error_response);
          else
            error_api.handle_unknown(sqlerrm, dbms_utility.format_error_backtrace,
                                     'admin.principal.roles.revoke', l_status_code, l_error_response);
          end if;
          owa_util.status_line(l_status_code);
          htp.p(l_error_response);
      end;
    ]',
    p_comments    => 'Revokes a role from a principal'
  );

  commit;
end;
/
