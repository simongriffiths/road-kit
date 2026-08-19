whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback

-- ROAD role administration (spec-patch-06 section 5, spec-patch-07 section 7).
--
-- Byte-identical to road-cal's api/modules/admin/module.create.sql apart from the module name and
-- the absence of POST /admin/purge/, which is a calendar operation. The file is NOT on the parity
-- list -- ORDS modules diverge deliberately, because they name an application -- so that identity
-- is a convention to maintain by hand, not one the check will enforce.
--
-- The module was named road_cal_api.admin here until 2026-08-19: an unrenamed copy-paste from the
-- patch 06 backport, while every other road-kit module is hello_api.*. ORDS module names are
-- schema-scoped so it worked, but road-kit's admin API announced itself as road-cal's.
--
-- Every handler here follows the same two-line preamble: establish session context, or 401. ORDS
-- exposes no schema-callable pre-dispatch hook, so this is per handler by necessity
-- (spec-patch-06 section 6.3) and bin/check-handler-coverage.sh is what stops one being forgotten.
--
-- The handlers are thin. They bind path parameters and the body into one JSON payload and call
-- road_admin_api, which enforces the permission requirement itself -- so the authorisation travels
-- with the operation rather than living only in the handler.

-- Both names: hello_api.admin is current, road_cal_api.admin is what this module was called until
-- 2026-08-19. Without the second delete, a schema deployed before the rename keeps serving the old
-- module alongside the new one, on the same base path.
begin
  ords.delete_module(p_module_name => 'hello_api.admin');
exception
  when others then
    null;
end;
/

begin
  ords.delete_module(p_module_name => 'road_cal_api.admin');
exception
  when others then
    null;
end;
/

begin
  ords.define_module(
    p_module_name    => 'hello_api.admin',
    p_base_path      => '/api/v1/admin/',
    p_items_per_page => 25,
    p_status         => 'PUBLISHED',
    p_comments       => 'ROAD role administration'
  );

  ---------------------------------------------------------------------------
  -- GET /admin/roles/
  ---------------------------------------------------------------------------
  ords.define_template(
    p_module_name => 'hello_api.admin',
    p_pattern     => 'roles/',
    p_comments    => 'Role catalogue'
  );

  ords.define_handler(
    p_module_name => 'hello_api.admin',
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
    p_module_name => 'hello_api.admin',
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
  -- GET /admin/permissions/
  ---------------------------------------------------------------------------
  -- Not a convenience: there is no other way to list road_permissions at all, so nothing can
  -- offer a catalogue to compose from (spec-patch-07 section 7). Static segment, declared before
  -- roles/:role_name/permissions/ for readability only, same as principals/ below.
  ords.define_template(
    p_module_name => 'hello_api.admin',
    p_pattern     => 'permissions/',
    p_comments    => 'Permission catalogue'
  );

  ords.define_handler(
    p_module_name => 'hello_api.admin',
    p_pattern     => 'permissions/',
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
        l_response := road_admin_api.get_permissions;
        owa_util.status_line(200);
        htp.p(json_serialize(l_response));
      exception
        when others then
          if sqlcode between -20999 and -20000 then
            error_api.handle_known(sqlcode, sqlerrm, l_status_code, l_error_response);
          else
            error_api.handle_unknown(sqlerrm, dbms_utility.format_error_backtrace,
                                     'admin.permissions.list', l_status_code, l_error_response);
          end if;
          owa_util.status_line(l_status_code);
          htp.p(l_error_response);
      end;
    ]',
    p_comments    => 'Lists permissions and the roles that compose them'
  );

  ---------------------------------------------------------------------------
  -- POST / DELETE /admin/roles/:role_name/permissions/:permission_name/
  ---------------------------------------------------------------------------
  -- Both handlers below widen the usual "sqlcode between -20999 and -20000" routing check to also
  -- catch -8601: this is the only pair of handlers that writes to road_role_permissions through
  -- the admin API, so it is the only pair that can ever observe road_reserved_composition or
  -- road_admin_reachable fire in practice (spec-patch-07 section 5.5). road_admin_api's own
  -- is_reserved check raises -20403 first on the ordinary path -- reaching an actual ORA-08601
  -- here means that check was bypassed or has a bug (defence in depth, not the primary path).
  ords.define_template(
    p_module_name => 'hello_api.admin',
    p_pattern     => 'roles/:role_name/permissions/',
    p_comments    => 'Permissions composed onto one role'
  );

  ords.define_handler(
    p_module_name => 'hello_api.admin',
    p_pattern     => 'roles/:role_name/permissions/',
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
        -- role_name from the path, permission_name from the body. attached_by is deliberately NOT
        -- accepted from either: road_admin_api takes it from the session.
        select json_object(
                 'role_name'       value :role_name,
                 'permission_name' value json_value(:body_text, '$.permission_name')
                 returning json
               )
          into l_request from dual;
        l_response := road_admin_api.attach_permission(l_request);
        owa_util.status_line(200);
        htp.p(json_serialize(l_response));
      exception
        when others then
          if sqlcode between -20999 and -20000 or sqlcode = -8601 then
            error_api.handle_known(sqlcode, sqlerrm, l_status_code, l_error_response);
          else
            error_api.handle_unknown(sqlerrm, dbms_utility.format_error_backtrace,
                                     'admin.roles.permissions.attach', l_status_code, l_error_response);
          end if;
          owa_util.status_line(l_status_code);
          htp.p(l_error_response);
      end;
    ]',
    p_comments    => 'Attaches an existing permission to a role'
  );

  ords.define_template(
    p_module_name => 'hello_api.admin',
    p_pattern     => 'roles/:role_name/permissions/:permission_name/',
    p_comments    => 'One role/permission composition'
  );

  ords.define_handler(
    p_module_name => 'hello_api.admin',
    p_pattern     => 'roles/:role_name/permissions/:permission_name/',
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
                 'role_name'       value :role_name,
                 'permission_name' value :permission_name
                 returning json
               )
          into l_request from dual;
        l_response := road_admin_api.detach_permission(l_request);
        owa_util.status_line(200);
        htp.p(json_serialize(l_response));
      exception
        when others then
          if sqlcode between -20999 and -20000 or sqlcode = -8601 then
            error_api.handle_known(sqlcode, sqlerrm, l_status_code, l_error_response);
          else
            error_api.handle_unknown(sqlerrm, dbms_utility.format_error_backtrace,
                                     'admin.roles.permissions.detach', l_status_code, l_error_response);
          end if;
          owa_util.status_line(l_status_code);
          htp.p(l_error_response);
      end;
    ]',
    p_comments    => 'Detaches a permission from a role'
  );

  ---------------------------------------------------------------------------
  -- GET /admin/principals/
  ---------------------------------------------------------------------------
  -- The listing endpoint any roles screen needs, absent until now
  -- (ui-authorisation-design-v1.md section 5). Framework surface: it is identity, which
  -- spec-patch-06 rule 1 assigns to road-kit, so it lives in road_admin_api beside the rest.
  --
  -- Static segment, declared BEFORE principals/:principal_id/roles/ for readability only -- ORDS
  -- resolves static segments ahead of templates regardless of declaration order.
  --
  -- NOTE on the "query" parameter name: this repeats the deviation documented at length on
  -- GET /events/search/. ORDS reserves "q" globally for its AutoREST JSON filter syntax and returns
  -- a platform-level 400 for any non-JSON value, even on a plain PL/SQL-source handler. The
  -- external parameter is therefore "query"; road_admin_api's own JSON contract still uses "q", and
  -- the mapping is contained here at the ORDS layer.
  --
  -- offset/limit keep their spec-mandated external names (ords-api-design-standards-v1.md section
  -- 6.1). ORDS reserves BOTH for pagination and validates them as numeric before dispatching, so a
  -- ?limit=abc never reaches this block: it comes back as ORDS's own 400, with ORDS's envelope
  -- ("code":"BadRequest") rather than error_api's. Verified against dev 2026-08-19 -- the same
  -- class of platform behaviour as the reserved "q" above, found the same way.
  --
  -- DEFAULT NULL ON CONVERSION ERROR therefore cannot fire for these two today. It stays because it
  -- is right for any bind ORDS does not pre-validate and because relying on an undocumented
  -- platform guard is how a 500 arrives later; but do not read it as live cover. The behaviour that
  -- IS live is pinned by test/endpoint/admin-principals.endpoint.sh.
  ords.define_template(
    p_module_name => 'hello_api.admin',
    p_pattern     => 'principals/',
    p_comments    => 'Principal directory'
  );

  ords.define_handler(
    p_module_name => 'hello_api.admin',
    p_pattern     => 'principals/',
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
        select json_object(
                 'offset' value to_number(:offset default null on conversion error),
                 'limit'  value to_number(:limit  default null on conversion error),
                 'q'      value :query,
                 'status' value :status
                 returning json
               )
          into l_request from dual;
        l_response := road_admin_api.get_principals(l_request);
        owa_util.status_line(200);
        htp.p(json_serialize(l_response));
      exception
        when others then
          if sqlcode between -20999 and -20000 then
            error_api.handle_known(sqlcode, sqlerrm, l_status_code, l_error_response);
          else
            error_api.handle_unknown(sqlerrm, dbms_utility.format_error_backtrace,
                                     'admin.principals.list', l_status_code, l_error_response);
          end if;
          owa_util.status_line(l_status_code);
          htp.p(l_error_response);
      end;
    ]',
    p_comments    => 'Lists principals with their roles. "query" not "q" -- see comment above.'
  );

  ---------------------------------------------------------------------------
  -- GET / POST /admin/principals/:principal_id/roles/
  ---------------------------------------------------------------------------
  ords.define_template(
    p_module_name => 'hello_api.admin',
    p_pattern     => 'principals/:principal_id/roles/',
    p_comments    => 'Roles held by one principal'
  );

  ords.define_handler(
    p_module_name => 'hello_api.admin',
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
    p_module_name => 'hello_api.admin',
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
    p_module_name => 'hello_api.admin',
    p_pattern     => 'principals/:principal_id/roles/:role_name/',
    p_comments    => 'One role grant'
  );

  ords.define_handler(
    p_module_name => 'hello_api.admin',
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

end;
/
