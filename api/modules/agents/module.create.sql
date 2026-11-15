whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback

-- Agents and their API keys (spec-patch-15, ledger B-04). Every handler establishes the session or
-- answers 401, makes one road_agent_api call and sends what it returns: governed actions answer 200
-- whatever they decide, with the decision in the body; wrong calls and failures go through error_api.
-- Who may do what is decided in road_agent_api, not here.

begin
  ords.delete_module(p_module_name => 'hello_api.agents');
exception
  when others then
    null;
end;
/

begin
  ords.define_module(
    p_module_name    => 'hello_api.agents',
    p_base_path      => '/api/v1/agents/',
    p_items_per_page => 0,
    p_status         => 'PUBLISHED',
    p_comments       => 'Agents and their API keys (spec-patch-15)');
  ords.define_template(p_module_name => 'hello_api.agents', p_pattern => '/');
  ords.define_template(p_module_name => 'hello_api.agents', p_pattern => ':id/');
  ords.define_template(p_module_name => 'hello_api.agents', p_pattern => ':id/keys/');
  ords.define_template(p_module_name => 'hello_api.agents', p_pattern => ':id/keys/:key_id/');

  ords.define_handler(
    p_module_name => 'hello_api.agents',
    p_pattern     => '/',
    p_method      => 'GET',
    p_source_type => ords.source_type_plsql,
    p_source      => q'[
      declare
        l_out            clob;
        l_status_code    number;
        l_error_response clob;
      begin
        if not road_ctx_pkg.begin_request(:current_user) then
          owa_util.status_line(401);
          htp.p('{"error":"UNAUTHORIZED","message":"No session could be established"}');
          return;
        end if;
        l_out := road_agent_api.list_agents(:all);
        owa_util.mime_header('application/json', false);
        owa_util.status_line(200, null, true);
        htp.p(l_out);
      exception
        when others then
          if sqlcode between -20999 and -20000 then
            error_api.handle_known(sqlcode, sqlerrm, l_status_code, l_error_response);
          else
            error_api.handle_unknown(sqlerrm, dbms_utility.format_error_backtrace,
                                     'agents.list', l_status_code, l_error_response);
          end if;
          owa_util.status_line(l_status_code);
          htp.p(l_error_response);
      end;
    ]'
  );

  ords.define_handler(
    p_module_name => 'hello_api.agents',
    p_pattern     => '/',
    p_method      => 'POST',
    p_source_type => ords.source_type_plsql,
    p_source      => q'[
      declare
        l_out            clob;
        l_status_code    number;
        l_error_response clob;
      begin
        if not road_ctx_pkg.begin_request(:current_user) then
          owa_util.status_line(401);
          htp.p('{"error":"UNAUTHORIZED","message":"No session could be established"}');
          return;
        end if;
        l_out := json_serialize(road_agent_api.create_agent(json(:body_text), :idempotency_key) returning clob);
        owa_util.mime_header('application/json', false);
        owa_util.status_line(200, null, true);
        htp.p(l_out);
      exception
        when others then
          if sqlcode between -20999 and -20000 then
            error_api.handle_known(sqlcode, sqlerrm, l_status_code, l_error_response);
          else
            error_api.handle_unknown(sqlerrm, dbms_utility.format_error_backtrace,
                                     'agents.create', l_status_code, l_error_response);
          end if;
          owa_util.status_line(l_status_code);
          htp.p(l_error_response);
      end;
    ]'
  );
  ords.define_parameter(p_module_name => 'hello_api.agents', p_pattern => '/', p_method => 'POST',
    p_name => 'Idempotency-Key', p_bind_variable_name => 'idempotency_key', p_source_type => 'HEADER', p_param_type => 'STRING', p_access_method => 'IN');

  ords.define_handler(
    p_module_name => 'hello_api.agents',
    p_pattern     => ':id/',
    p_method      => 'DELETE',
    p_source_type => ords.source_type_plsql,
    p_source      => q'[
      declare
        l_out            clob;
        l_status_code    number;
        l_error_response clob;
      begin
        if not road_ctx_pkg.begin_request(:current_user) then
          owa_util.status_line(401);
          htp.p('{"error":"UNAUTHORIZED","message":"No session could be established"}');
          return;
        end if;
        l_out := json_serialize(road_agent_api.retire_agent(to_number(:id default null on conversion error), :idempotency_key) returning clob);
        owa_util.mime_header('application/json', false);
        owa_util.status_line(200, null, true);
        htp.p(l_out);
      exception
        when others then
          if sqlcode between -20999 and -20000 then
            error_api.handle_known(sqlcode, sqlerrm, l_status_code, l_error_response);
          else
            error_api.handle_unknown(sqlerrm, dbms_utility.format_error_backtrace,
                                     'agents.retire', l_status_code, l_error_response);
          end if;
          owa_util.status_line(l_status_code);
          htp.p(l_error_response);
      end;
    ]'
  );
  ords.define_parameter(p_module_name => 'hello_api.agents', p_pattern => ':id/', p_method => 'DELETE',
    p_name => 'Idempotency-Key', p_bind_variable_name => 'idempotency_key', p_source_type => 'HEADER', p_param_type => 'STRING', p_access_method => 'IN');

  ords.define_handler(
    p_module_name => 'hello_api.agents',
    p_pattern     => ':id/keys/',
    p_method      => 'POST',
    p_source_type => ords.source_type_plsql,
    p_source      => q'[
      declare
        l_out            clob;
        l_status_code    number;
        l_error_response clob;
      begin
        if not road_ctx_pkg.begin_request(:current_user) then
          owa_util.status_line(401);
          htp.p('{"error":"UNAUTHORIZED","message":"No session could be established"}');
          return;
        end if;
        l_out := json_serialize(road_agent_api.create_key(to_number(:id default null on conversion error), json(:body_text), :idempotency_key) returning clob);
        owa_util.mime_header('application/json', false);
        owa_util.status_line(200, null, true);
        htp.p(l_out);
      exception
        when others then
          if sqlcode between -20999 and -20000 then
            error_api.handle_known(sqlcode, sqlerrm, l_status_code, l_error_response);
          else
            error_api.handle_unknown(sqlerrm, dbms_utility.format_error_backtrace,
                                     'api_keys.create', l_status_code, l_error_response);
          end if;
          owa_util.status_line(l_status_code);
          htp.p(l_error_response);
      end;
    ]'
  );
  ords.define_parameter(p_module_name => 'hello_api.agents', p_pattern => ':id/keys/', p_method => 'POST',
    p_name => 'Idempotency-Key', p_bind_variable_name => 'idempotency_key', p_source_type => 'HEADER', p_param_type => 'STRING', p_access_method => 'IN');

  ords.define_handler(
    p_module_name => 'hello_api.agents',
    p_pattern     => ':id/keys/:key_id/',
    p_method      => 'DELETE',
    p_source_type => ords.source_type_plsql,
    p_source      => q'[
      declare
        l_out            clob;
        l_status_code    number;
        l_error_response clob;
      begin
        if not road_ctx_pkg.begin_request(:current_user) then
          owa_util.status_line(401);
          htp.p('{"error":"UNAUTHORIZED","message":"No session could be established"}');
          return;
        end if;
        l_out := json_serialize(road_agent_api.revoke_key(to_number(:id default null on conversion error), to_number(:key_id default null on conversion error), :idempotency_key) returning clob);
        owa_util.mime_header('application/json', false);
        owa_util.status_line(200, null, true);
        htp.p(l_out);
      exception
        when others then
          if sqlcode between -20999 and -20000 then
            error_api.handle_known(sqlcode, sqlerrm, l_status_code, l_error_response);
          else
            error_api.handle_unknown(sqlerrm, dbms_utility.format_error_backtrace,
                                     'api_keys.delete', l_status_code, l_error_response);
          end if;
          owa_util.status_line(l_status_code);
          htp.p(l_error_response);
      end;
    ]'
  );
  ords.define_parameter(p_module_name => 'hello_api.agents', p_pattern => ':id/keys/:key_id/', p_method => 'DELETE',
    p_name => 'Idempotency-Key', p_bind_variable_name => 'idempotency_key', p_source_type => 'HEADER', p_param_type => 'STRING', p_access_method => 'IN');
  commit;
end;
/
