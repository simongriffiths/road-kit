create or replace package body jwt_scaffold_auth_api_test as

  -- Exercises the login path through authenticate_json, which is the procedure the ORDS handler
  -- calls. Every test builds its own principal and credential and rolls them back, so this suite
  -- never depends on -- or disturbs -- whatever real principals a deployment holds.
  --
  -- THE PASSWORD BELOW IS A FIXTURE, NOT A CREDENTIAL. It authenticates a principal that exists
  -- only inside an uncommitted transaction. It is safe in source for the same reason a test's
  -- expected value is: nothing outside this suite can ever authenticate with it.
  c_test_password constant varchar2(64) := 'fixture-password-not-a-secret';
  c_test_subject  constant varchar2(64) := 'ZZ_TEST_PRINCIPAL';

  procedure assert_eq(p_label in varchar2, p_expected in varchar2, p_actual in varchar2) is
  begin
    if p_actual is null and p_expected is null then
      return;
    end if;
    if p_actual is null or p_expected is null or p_actual != p_expected then
      raise_application_error(
        -20000,
        p_label || ': expected [' || p_expected || '] got [' || p_actual || ']'
      );
    end if;
  end assert_eq;

  procedure assert_true(p_label in varchar2, p_condition in boolean) is
  begin
    if not nvl(p_condition, false) then
      raise_application_error(-20000, p_label || ': expected true');
    end if;
  end assert_true;

  function current_issuer return varchar2 is
    l_issuer varchar2(512 char);
  begin
    select issuer into l_issuer from user_ords_jwt_profile;
    return l_issuer;
  end current_issuer;

  -- Creates the fixture principal. p_with_credential false covers the real case of a principal
  -- created through the admin screens for whom no password has been set yet.
  function make_principal(
    p_status          in varchar2 default 'ACTIVE',
    p_with_credential in boolean  default true,
    p_password        in varchar2 default c_test_password
  ) return number is
    l_principal_id number;
    l_salt         raw(16);
    -- Materialised rather than called inline: PLS-00231, a package-private function may not be
    -- used inside a SQL statement.
    l_issuer       varchar2(512 char) := current_issuer;
  begin
    insert into road_principals (issuer, subject, display_name, status)
    values (l_issuer, c_test_subject, 'Fixture principal', p_status)
    returning principal_id into l_principal_id;

    if p_with_credential then
      l_salt := jwt_scaffold_crypto.random_salt;
      insert into jwt_scaffold_credentials (
        principal_id, salt, password_hash, iterations, algorithm
      ) values (
        l_principal_id,
        l_salt,
        -- 1000 rather than the 10,000 default: this runs ten times across the suite and the cost
        -- function is the point of the algorithm, not of the test. The table's floor is 1000.
        jwt_scaffold_crypto.pbkdf2_sha256(p_password, l_salt, 1000, 32),
        1000,
        jwt_scaffold_crypto.c_algorithm
      );
    end if;

    return l_principal_id;
  end make_principal;

  function login_body(p_username in varchar2, p_password in varchar2) return clob is
    l_body clob;
  begin
    -- SELECT ... INTO rather than a direct expression: JSON_OBJECT with RETURNING CLOB is not a
    -- valid PL/SQL expression (PLS-00684).
    select json_object('username' value p_username, 'password' value p_password returning clob)
      into l_body
      from dual;
    return l_body;
  end login_body;

  procedure attempt(
    p_username    in  varchar2,
    p_password    in  varchar2,
    p_status      out number,
    p_error       out varchar2,
    p_token       out varchar2
  ) is
    l_token_type varchar2(40);
    l_expires_in number;
    l_kid        varchar2(255);
    l_error_desc varchar2(4000);
  begin
    jwt_scaffold_auth_api.authenticate_json(
      p_body              => login_body(p_username, p_password),
      p_access_token      => p_token,
      p_token_type        => l_token_type,
      p_expires_in        => l_expires_in,
      p_kid               => l_kid,
      p_error             => p_error,
      p_error_description => l_error_desc,
      p_http_status       => p_status
    );
  end attempt;

  -- Decodes the sub claim, so the test asserts what the token SAYS rather than what the code was
  -- asked to put in it.
  function sub_of(p_token in varchar2) return varchar2 is
    l_payload_b64 varchar2(32767);
    l_padded      varchar2(32767);
  begin
    l_payload_b64 := regexp_substr(p_token, '[^.]+', 1, 2);
    l_payload_b64 := replace(replace(l_payload_b64, '-', '+'), '_', '/');
    l_padded := l_payload_b64 || rpad('=', mod(4 - mod(length(l_payload_b64), 4), 4), '=');
    return json_value(
      utl_raw.cast_to_varchar2(utl_encode.base64_decode(utl_raw.cast_to_raw(l_padded))),
      '$.sub'
    );
  end sub_of;

  procedure test_valid_credentials_issue_a_token is
    l_status number;
    l_error  varchar2(4000);
    l_token  varchar2(32767);
  begin
    if make_principal() is null then null; end if;
    attempt(c_test_subject, c_test_password, l_status, l_error, l_token);
    assert_eq('http status', '200', to_char(l_status));
    assert_eq('error', null, l_error);
    assert_true('token issued', l_token is not null);
    assert_eq('sub is the principal subject', c_test_subject, sub_of(l_token));
  end test_valid_credentials_issue_a_token;

  procedure test_wrong_password_refused is
    l_status number;
    l_error  varchar2(4000);
    l_token  varchar2(32767);
  begin
    if make_principal() is null then null; end if;
    attempt(c_test_subject, 'not the password', l_status, l_error, l_token);
    assert_eq('http status', '401', to_char(l_status));
    assert_eq('error', 'invalid_credentials', l_error);
    assert_true('no token issued', l_token is null);
  end test_wrong_password_refused;

  procedure test_unknown_subject_refused is
    l_status number;
    l_error  varchar2(4000);
    l_token  varchar2(32767);
  begin
    attempt('ZZ_NO_SUCH_PRINCIPAL', c_test_password, l_status, l_error, l_token);
    assert_eq('http status', '401', to_char(l_status));
    assert_eq('error', 'invalid_credentials', l_error);
    assert_true('no token issued', l_token is null);
  end test_unknown_subject_refused;

  -- The case the old constant-based check could not even express: a principal exists but has no
  -- password. Normal for anyone created through the admin screens, and normal under external_oidc.
  procedure test_principal_without_credential_refused is
    l_status number;
    l_error  varchar2(4000);
    l_token  varchar2(32767);
  begin
    if make_principal(p_with_credential => false) is null then null; end if;
    attempt(c_test_subject, c_test_password, l_status, l_error, l_token);
    assert_eq('http status', '401', to_char(l_status));
    assert_eq('error', 'invalid_credentials', l_error);
  end test_principal_without_credential_refused;

  -- ROAD_PRINCIPALS.STATUS has carried these values since patch 06 with nothing enforcing them.
  -- A correct password must not admit a suspended principal.
  procedure test_suspended_principal_refused is
    l_status number;
    l_error  varchar2(4000);
    l_token  varchar2(32767);
  begin
    if make_principal(p_status => 'SUSPENDED') is null then null; end if;
    attempt(c_test_subject, c_test_password, l_status, l_error, l_token);
    assert_eq('http status', '401', to_char(l_status));
    assert_eq('error', 'invalid_credentials', l_error);
    assert_true('no token issued', l_token is null);
  end test_suspended_principal_refused;

  procedure test_retired_principal_refused is
    l_status number;
    l_error  varchar2(4000);
    l_token  varchar2(32767);
  begin
    if make_principal(p_status => 'RETIRED') is null then null; end if;
    attempt(c_test_subject, c_test_password, l_status, l_error, l_token);
    assert_eq('http status', '401', to_char(l_status));
  end test_retired_principal_refused;

  procedure test_username_is_case_insensitive is
    l_status number;
    l_error  varchar2(4000);
    l_token  varchar2(32767);
  begin
    if make_principal() is null then null; end if;
    attempt(lower(c_test_subject), c_test_password, l_status, l_error, l_token);
    assert_eq('http status', '200', to_char(l_status));
    assert_eq('sub is stored form, not typed form', c_test_subject, sub_of(l_token));
  end test_username_is_case_insensitive;

  procedure test_missing_fields_are_400 is
    l_status number;
    l_error  varchar2(4000);
    l_token  varchar2(32767);
  begin
    attempt(null, c_test_password, l_status, l_error, l_token);
    assert_eq('missing username status', '400', to_char(l_status));
    assert_eq('missing username error', 'invalid_request', l_error);

    attempt(c_test_subject, null, l_status, l_error, l_token);
    assert_eq('missing password status', '400', to_char(l_status));
    assert_eq('missing password error', 'invalid_request', l_error);
  end test_missing_fields_are_400;

  -- A password stored at a non-default cost must verify at that cost. This is what makes raising
  -- c_default_iterations safe for rows already written.
  procedure test_row_iterations_are_honoured is
    l_status number;
    l_error  varchar2(4000);
    l_token  varchar2(32767);
    l_id     number;
    l_salt   raw(16);
  begin
    l_id := make_principal(p_with_credential => false);
    l_salt := jwt_scaffold_crypto.random_salt;
    insert into jwt_scaffold_credentials (principal_id, salt, password_hash, iterations, algorithm)
    values (l_id, l_salt,
            jwt_scaffold_crypto.pbkdf2_sha256(c_test_password, l_salt, 2500, 32),
            2500, jwt_scaffold_crypto.c_algorithm);

    attempt(c_test_subject, c_test_password, l_status, l_error, l_token);
    assert_eq('non-default iteration count verifies', '200', to_char(l_status));
  end test_row_iterations_are_honoured;

  -- Decodes the scope claim the same way sub_of decodes sub, so these tests assert what the
  -- TOKEN carries, not what a helper function returned.
  function scope_of(p_token in varchar2) return varchar2 is
    l_payload_b64 varchar2(32767);
    l_padded      varchar2(32767);
  begin
    l_payload_b64 := regexp_substr(p_token, '[^.]+', 1, 2);
    l_payload_b64 := replace(replace(l_payload_b64, '-', '+'), '_', '/');
    l_padded := l_payload_b64 || rpad('=', mod(4 - mod(length(l_payload_b64), 4), 4), '=');
    return json_value(
      utl_raw.cast_to_varchar2(utl_encode.base64_decode(utl_raw.cast_to_raw(l_padded))),
      '$.scope'
    );
  end scope_of;

  -- A principal holding ONLY road.system_admin -- no 'user' role, unlike a real bootstrap
  -- administrator, which the build's own 95_data.sql always grants both -- gets road.admin.rw in
  -- scope. Proves the join reaches ROAD_PERMISSIONS through ROAD_ROLE_PERMISSIONS rather than
  -- stopping at role membership.
  procedure test_admin_scope_includes_admin_rw is
    l_status number;
    l_error  varchar2(4000);
    l_token  varchar2(32767);
    l_id     number;
  begin
    l_id := make_principal();
    insert into road_principal_roles (principal_id, role_name) values (l_id, 'road.system_admin');

    attempt(c_test_subject, c_test_password, l_status, l_error, l_token);
    assert_eq('http status', '200', to_char(l_status));
    assert_true('scope contains road.admin.rw',
                instr(scope_of(l_token), 'road.admin.rw') > 0);
  end test_admin_scope_includes_admin_rw;

  -- The regression this whole phase exists to prevent: road.user_admin holds road.role.grant and
  -- road.role.revoke, neither of which is an ORDS privilege name, so without an explicit
  -- road.admin.rw grant on that role its scope would be empty and every one of its calls would be
  -- refused by ORDS before require_permission ever saw them. Found in 95_data.sql while wiring this
  -- phase; this test is what stops it regressing silently.
  procedure test_user_admin_scope_includes_admin_rw is
    l_status number;
    l_error  varchar2(4000);
    l_token  varchar2(32767);
    l_id     number;
  begin
    l_id := make_principal();
    insert into road_principal_roles (principal_id, role_name) values (l_id, 'road.user_admin');

    attempt(c_test_subject, c_test_password, l_status, l_error, l_token);
    assert_true('road.user_admin reaches the admin URL space',
                instr(scope_of(l_token), 'road.admin.rw') > 0);
  end test_user_admin_scope_includes_admin_rw;

  -- 'user' holds session.me.read and (once the demo is deployed) todo.rw, but never
  -- road.admin.rw -- an ordinary principal must not reach the admin URL space regardless of what
  -- demo permissions get added around it.
  procedure test_plain_user_scope_excludes_admin_rw is
    l_status number;
    l_error  varchar2(4000);
    l_token  varchar2(32767);
    l_id     number;
  begin
    l_id := make_principal();
    insert into road_principal_roles (principal_id, role_name) values (l_id, 'user');

    attempt(c_test_subject, c_test_password, l_status, l_error, l_token);
    assert_true('scope contains session.me.read',
                instr(scope_of(l_token), 'session.me.read') > 0);
    assert_eq('scope excludes road.admin.rw', '0',
              to_char(instr(nvl(scope_of(l_token), ' '), 'road.admin.rw')));
  end test_plain_user_scope_excludes_admin_rw;

  -- A principal holding no role at all -- possible the instant after road_admin_api.grant_role
  -- creates one, before anything is attached -- must get an empty scope, not the old fixed list and
  -- not an error. json_object's default null handling OMITS the key entirely for a NULL value
  -- (there is no explicit NULL ON NULL), so this checks the claim is absent, not merely blank.
  procedure test_no_roles_yields_no_scope_claim is
    l_status number;
    l_error  varchar2(4000);
    l_token  varchar2(32767);
  begin
    if make_principal() is null then null; end if;
    attempt(c_test_subject, c_test_password, l_status, l_error, l_token);
    assert_eq('http status', '200', to_char(l_status));
    assert_true('scope claim is absent', scope_of(l_token) is null);
  end test_no_roles_yields_no_scope_claim;

  -- A fine-grained permission that is NOT also an ORDS privilege name must not leak into scope.
  -- road.role.define is real, attached to a real role, and gates an operation inside
  -- road_admin_api -- exactly the shape effective_ords_scope's join is supposed to filter out.
  procedure test_operation_only_permission_excluded_from_scope is
    l_status number;
    l_error  varchar2(4000);
    l_token  varchar2(32767);
    l_id     number;
  begin
    l_id := make_principal();
    insert into road_principal_roles (principal_id, role_name) values (l_id, 'road.system_admin');

    attempt(c_test_subject, c_test_password, l_status, l_error, l_token);
    assert_eq('road.role.define never appears in a scope claim', '0',
              to_char(instr(nvl(scope_of(l_token), ' '), 'road.role.define')));
  end test_operation_only_permission_excluded_from_scope;

  procedure test_no_credential_constants_remain is
    l_hits number;
  begin
    -- The regression guard for what phase 3 removed. If someone reintroduces a hardcoded digest,
    -- this fails rather than the password quietly working.
    select count(*)
      into l_hits
      from user_source
     where name = 'JWT_SCAFFOLD_AUTH_API'
       and type = 'PACKAGE BODY'
       and (regexp_like(text, 'hextoraw\s*\(\s*''[0-9A-Fa-f]{32,}', 'i')
            or upper(text) like '%C_ADMIN_HASH%'
            or upper(text) like '%C_USER1_HASH%'
            or upper(text) like '%C_USER2_HASH%');
    assert_eq('no credential constants in the package body', '0', to_char(l_hits));
  end test_no_credential_constants_remain;

  procedure run_all is
    l_pass number := 0;
    l_fail number := 0;

    procedure run(p_name in varchar2, p_proc in varchar2) is
    begin
      savepoint before_test;
      case p_proc
        when 'valid'        then test_valid_credentials_issue_a_token;
        when 'wrong_pw'     then test_wrong_password_refused;
        when 'unknown'      then test_unknown_subject_refused;
        when 'no_cred'      then test_principal_without_credential_refused;
        when 'suspended'    then test_suspended_principal_refused;
        when 'retired'      then test_retired_principal_refused;
        when 'case'         then test_username_is_case_insensitive;
        when 'missing'      then test_missing_fields_are_400;
        when 'row_iters'    then test_row_iterations_are_honoured;
        when 'admin_scope'  then test_admin_scope_includes_admin_rw;
        when 'ua_scope'     then test_user_admin_scope_includes_admin_rw;
        when 'user_scope'   then test_plain_user_scope_excludes_admin_rw;
        when 'no_scope'     then test_no_roles_yields_no_scope_claim;
        when 'op_excluded'  then test_operation_only_permission_excluded_from_scope;
        when 'no_constants' then test_no_credential_constants_remain;
      end case;
      rollback to savepoint before_test;
      dbms_output.put_line('PASS ' || p_name);
      l_pass := l_pass + 1;
    exception
      when others then
        rollback to savepoint before_test;
        dbms_output.put_line('FAIL ' || p_name || ': ' || sqlerrm);
        l_fail := l_fail + 1;
    end run;
  begin
    run('test_valid_credentials_issue_a_token', 'valid');
    run('test_wrong_password_refused', 'wrong_pw');
    run('test_unknown_subject_refused', 'unknown');
    run('test_principal_without_credential_refused', 'no_cred');
    run('test_suspended_principal_refused', 'suspended');
    run('test_retired_principal_refused', 'retired');
    run('test_username_is_case_insensitive', 'case');
    run('test_missing_fields_are_400', 'missing');
    run('test_row_iterations_are_honoured', 'row_iters');
    run('test_admin_scope_includes_admin_rw', 'admin_scope');
    run('test_user_admin_scope_includes_admin_rw', 'ua_scope');
    run('test_plain_user_scope_excludes_admin_rw', 'user_scope');
    run('test_no_roles_yields_no_scope_claim', 'no_scope');
    run('test_operation_only_permission_excluded_from_scope', 'op_excluded');
    run('test_no_credential_constants_remain', 'no_constants');

    dbms_output.put_line('jwt_scaffold_auth_api_test: ' || l_pass || ' passed, ' || l_fail || ' failed');
  end run_all;

end jwt_scaffold_auth_api_test;
/
