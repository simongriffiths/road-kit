whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback

-- The demo application's API (spec-patch-08 section 6).
--
-- Registered by deploy/create/97_demo.sql, NOT by deploy/create/90_rest.sql -- an adopter
-- deploying the framework does not get these routes.
--
-- Every handler follows the framework's two-line preamble: establish session context, or 401.
-- ORDS exposes no schema-callable pre-dispatch hook, so this is per handler by necessity
-- (spec-patch-06 section 6.3) and bin/check-handler-coverage.sh is what stops one being forgotten.
--
-- The handlers are thin. They bind path and query parameters and the body into one JSON payload
-- and call demo_todo_api, which enforces the permission requirement ITSELF -- so authorisation
-- travels with the operation rather than living only in the handler. An adopter copying this demo
-- should copy that arrangement and throw the domain away.
--
-- "query" not "q": ORDS reserves q globally for its AutoREST JSON filter syntax and returns a
-- platform-level 400 for any non-JSON value, even on a plain PL/SQL-source handler. Same
-- deviation, same reason, as GET /admin/principals/ and road-cal's GET /events/search/.

begin
  ords.delete_module(p_module_name => 'hello_api.todos');
exception
  when others then
    null;
end;
/

begin
  ords.define_module(
    p_module_name    => 'hello_api.todos',
    p_base_path      => '/api/v1/todos/',
    p_items_per_page => 25,
    p_status         => 'PUBLISHED',
    p_comments       => 'Demo application (spec patch 08)'
  );

  ---------------------------------------------------------------------------
  -- GET / POST /todos/
  ---------------------------------------------------------------------------
  ords.define_template(
    p_module_name => 'hello_api.todos',
    p_pattern     => '/',
    p_comments    => 'Todo collection'
  );

  ords.define_handler(
    p_module_name => 'hello_api.todos',
    p_pattern     => '/',
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
                 'owner'  value to_number(:owner  default null on conversion error),
                 'q'      value :query,
                 'status' value :status
                 returning json
               )
          into l_request from dual;
        l_response := demo_todo_api.get_todos(l_request);
        owa_util.status_line(200);
        htp.p(json_serialize(l_response));
      exception
        when others then
          if sqlcode between -20999 and -20000 then
            error_api.handle_known(sqlcode, sqlerrm, l_status_code, l_error_response);
          else
            error_api.handle_unknown(sqlerrm, dbms_utility.format_error_backtrace,
                                     'todos.list', l_status_code, l_error_response);
          end if;
          owa_util.status_line(l_status_code);
          htp.p(l_error_response);
      end;
    ]',
    p_comments    => 'Lists the caller''s todos; ?owner= another principal requires todo.list_all'
  );

  ords.define_handler(
    p_module_name => 'hello_api.todos',
    p_pattern     => '/',
    p_method      => 'POST',
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
        -- The body goes through UNCHANGED, owner_principal_id included if the caller sent one.
        -- demo_todo_api refuses it with a 400 rather than stripping it here: a caller probing for
        -- the hole should be told no, not told nothing.
        l_response := demo_todo_api.create_todo(json(:body_text));
        owa_util.status_line(201);
        htp.p(json_serialize(l_response));
      exception
        when others then
          if sqlcode between -20999 and -20000 then
            error_api.handle_known(sqlcode, sqlerrm, l_status_code, l_error_response);
          else
            error_api.handle_unknown(sqlerrm, dbms_utility.format_error_backtrace,
                                     'todos.create', l_status_code, l_error_response);
          end if;
          owa_util.status_line(l_status_code);
          htp.p(l_error_response);
      end;
    ]',
    p_comments    => 'Creates a todo owned by the caller'
  );

  ---------------------------------------------------------------------------
  -- POST /todos/purge/
  ---------------------------------------------------------------------------
  -- Static segment, declared before :todo_id/ for readability only -- ORDS resolves static
  -- segments ahead of templates regardless of declaration order.
  --
  -- Gated on todo.purge, which is RESERVED. Nothing in this handler or in demo_todo_api reads
  -- that flag: reservation governs who may ATTACH the permission to a role, not what happens once
  -- someone holds it. The guard is road_reserved_composition, in the database, one layer down.
  ords.define_template(
    p_module_name => 'hello_api.todos',
    p_pattern     => 'purge/',
    p_comments    => 'Irreversible bulk delete'
  );

  ords.define_handler(
    p_module_name => 'hello_api.todos',
    p_pattern     => 'purge/',
    p_method      => 'POST',
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
        l_response := demo_todo_api.purge(json(:body_text));
        owa_util.status_line(200);
        htp.p(json_serialize(l_response));
      exception
        when others then
          if sqlcode between -20999 and -20000 then
            error_api.handle_known(sqlcode, sqlerrm, l_status_code, l_error_response);
          else
            error_api.handle_unknown(sqlerrm, dbms_utility.format_error_backtrace,
                                     'todos.purge', l_status_code, l_error_response);
          end if;
          owa_util.status_line(l_status_code);
          htp.p(l_error_response);
      end;
    ]',
    p_comments    => 'Hard-deletes finished todos across all owners. Requires todo.purge.'
  );

  ---------------------------------------------------------------------------
  -- GET / PATCH / DELETE /todos/:todo_id/
  ---------------------------------------------------------------------------
  ords.define_template(
    p_module_name => 'hello_api.todos',
    p_pattern     => ':todo_id/',
    p_comments    => 'One todo'
  );

  ords.define_handler(
    p_module_name => 'hello_api.todos',
    p_pattern     => ':todo_id/',
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
                 'todo_id' value to_number(:todo_id default null on conversion error)
                 returning json
               )
          into l_request from dual;
        l_response := demo_todo_api.get_todo(l_request);
        owa_util.status_line(200);
        htp.p(json_serialize(l_response));
      exception
        when others then
          if sqlcode between -20999 and -20000 then
            error_api.handle_known(sqlcode, sqlerrm, l_status_code, l_error_response);
          else
            error_api.handle_unknown(sqlerrm, dbms_utility.format_error_backtrace,
                                     'todos.get', l_status_code, l_error_response);
          end if;
          owa_util.status_line(l_status_code);
          htp.p(l_error_response);
      end;
    ]',
    p_comments    => 'Reads one todo and issues a read_token'
  );

  ords.define_handler(
    p_module_name => 'hello_api.todos',
    p_pattern     => ':todo_id/',
    p_method      => 'PATCH',
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
        -- todo_id from the path, everything else from the body. A body that also carries todo_id
        -- is ignored in favour of the path -- the URL is what the caller addressed.
        select json_transform(
                 json(:body_text),
                 set '$.todo_id' = to_number(:todo_id default null on conversion error)
               )
          into l_request from dual;
        l_response := demo_todo_api.update_todo(l_request);
        owa_util.status_line(200);
        htp.p(json_serialize(l_response));
      exception
        when others then
          if sqlcode between -20999 and -20000 then
            error_api.handle_known(sqlcode, sqlerrm, l_status_code, l_error_response);
          else
            error_api.handle_unknown(sqlerrm, dbms_utility.format_error_backtrace,
                                     'todos.update', l_status_code, l_error_response);
          end if;
          owa_util.status_line(l_status_code);
          htp.p(l_error_response);
      end;
    ]',
    p_comments    => 'Updates a todo. Requires the read_token from the read that showed it.'
  );

  ords.define_handler(
    p_module_name => 'hello_api.todos',
    p_pattern     => ':todo_id/',
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
        -- read_token as a query parameter: DELETE carries no body in the ORDS handler contract,
        -- same shape as road-cal's DELETE /events/{instance_id}?read_token=.
        select json_object(
                 'todo_id'    value to_number(:todo_id default null on conversion error),
                 'read_token' value :read_token
                 returning json
               )
          into l_request from dual;
        l_response := demo_todo_api.delete_todo(l_request);
        owa_util.status_line(200);
        htp.p(json_serialize(l_response));
      exception
        when others then
          if sqlcode between -20999 and -20000 then
            error_api.handle_known(sqlcode, sqlerrm, l_status_code, l_error_response);
          else
            error_api.handle_unknown(sqlerrm, dbms_utility.format_error_backtrace,
                                     'todos.delete', l_status_code, l_error_response);
          end if;
          owa_util.status_line(l_status_code);
          htp.p(l_error_response);
      end;
    ]',
    p_comments    => 'Soft-deletes a todo. Requires a read_token.'
  );

  commit;
end;
/
