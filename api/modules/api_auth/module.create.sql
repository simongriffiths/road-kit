whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback

-- The agent sign-in exchange (spec-patch-15 section 4.5): a tool trades an API key for a short-lived
-- JWT, which it then sends as a bearer token like any other. PUBLIC, beside /jwt-auth/login: the key
-- is the credential, and requiring a session to get a session is circular. On
-- bin/check-handler-coverage.sh's allowlist for that reason.

begin
  ords.delete_module(p_module_name => 'hello_api.api_auth');
exception
  when others then
    null;
end;
/

begin
  ords.define_module(
    p_module_name    => 'hello_api.api_auth',
    p_base_path      => '/api-auth/',
    p_items_per_page => 0,
    p_status         => 'PUBLISHED',
    p_comments       => 'Agent sign-in: API key for a short-lived token (spec-patch-15)');
  ords.define_template(p_module_name => 'hello_api.api_auth', p_pattern => 'tokens');
  ords.define_handler(
    p_module_name   => 'hello_api.api_auth',
    p_pattern       => 'tokens',
    p_method        => 'POST',
    p_mimes_allowed => 'application/json',
    p_source_type   => ords.source_type_plsql,
    p_source        => q'[
      declare
        l_status         number;
        l_body           clob;
        l_status_code    number;
        l_error_response clob;
      begin
        road_agent_api.exchange(:body_text, l_status, l_body);
        owa_util.mime_header('application/json', false);
        owa_util.status_line(l_status, null, true);
        htp.p(l_body);
      exception
        when others then
          error_api.handle_unknown(sqlerrm, dbms_utility.format_error_backtrace,
                                   'api_auth.tokens', l_status_code, l_error_response);
          owa_util.status_line(l_status_code);
          htp.p(l_error_response);
      end;
    ]');
  commit;
end;
/
