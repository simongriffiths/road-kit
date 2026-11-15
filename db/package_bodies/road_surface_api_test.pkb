create or replace package body road_surface_api_test as

  -- The tests that carry this package are test_natural_key (one token and record give one key, the
  -- next record another: a list read returns many records with one token), test_hidden_and_missing_alike
  -- (a record the caller may not see is refused exactly as a missing one is) and test_envelope
  -- (the standard fields on every view).

  c_issuer constant varchar2(64)  := 'urn:road:test:surface';
  c_action constant varchar2(200) := 'test.road_surface.action';

  l_pass number := 0;
  l_fail number := 0;

  procedure fail(p_message in varchar2) is
  begin
    raise_application_error(-20000, p_message);
  end fail;

  procedure assert_eq(p_label in varchar2, p_expected in varchar2, p_actual in varchar2) is
  begin
    if nvl(p_actual, '<null>') != nvl(p_expected, '<null>') then
      fail(p_label || ': expected [' || p_expected || '] got [' || p_actual || ']');
    end if;
  end assert_eq;

  procedure login(p_subject in varchar2) is
  begin
    if not road_ctx_pkg.begin_request(p_subject, c_issuer) then
      fail('could not establish ' || p_subject);
    end if;
  end login;

  -- Rejected rows are committed autonomously, so the runner's savepoint cannot remove them.
  procedure purge_test_decisions is
  begin
    delete from road_decisions where action_id like 'test.road_surface.%';
    commit;
  end purge_test_decisions;

  procedure setup is
  begin
    execute immediate 'alter session disable parallel dml';
    insert into road_principals (issuer, subject, display_name, status)
    select c_issuer, 'ALICE', 'road_surface test fixture', 'ACTIVE' from dual
     where not exists (select 1 from road_principals where issuer = c_issuer and subject = 'ALICE');
    commit;
    purge_test_decisions;
  end setup;

  procedure teardown is
  begin
    road_ctx_pkg.end_request;
    purge_test_decisions;
    delete from road_principals where issuer = c_issuer;
    commit;
  end teardown;

  procedure test_version is
    l_stored varchar2(20);
  begin
    select max(contract_version) into l_stored from road_contract;
    assert_eq('contract_version', nvl(l_stored, road_surface_api.c_framework_version),
              road_surface_api.contract_version);
    assert_eq('major_version', regexp_substr(road_surface_api.contract_version, '^[0-9]+'),
              road_surface_api.major_version);
    if not road_surface_api.version_ok(null) then fail('no Accept-Version must be accepted'); end if;
    if not road_surface_api.version_ok(road_surface_api.major_version || '.9') then
      fail('the same major version must be accepted');
    end if;
  end test_version;

  procedure test_natural_key is
    l_token varchar2(40) := rawtohex(sys_guid());
  begin
    assert_eq('same token and record', road_surface_api.natural_key(7, l_token),
              road_surface_api.natural_key(7, lower(' ' || l_token || ' ')));
    if road_surface_api.natural_key(7, l_token) = road_surface_api.natural_key(8, l_token) then
      fail('two records read with one token must have different keys');
    end if;
    if road_surface_api.natural_key(7, l_token) = road_surface_api.natural_key(7, rawtohex(sys_guid())) then
      fail('one record read twice must have different keys');
    end if;
    assert_eq('no token, no key', null, road_surface_api.natural_key(7, null));
  end test_natural_key;

  procedure test_token_raw_bad is
    l_raw raw(16);
  begin
    begin
      l_raw := road_surface_api.token_raw('not hex');
      fail('a malformed token must be a wrong call');
    exception
      when others then
        assert_eq('malformed', '-20001', to_char(sqlcode));
    end;
    begin
      l_raw := road_surface_api.token_raw(null);
      fail('a missing token must be a wrong call');
    exception
      when others then
        assert_eq('missing', '-20001', to_char(sqlcode));
    end;
  end test_token_raw_bad;

  procedure test_token_freshness is
    l_token varchar2(40);
  begin
    login('ALICE');
    l_token := road_surface_api.new_token('test_surface');
    assert_eq('token length', '32', to_char(length(l_token)));
    if not road_surface_api.is_fresh(road_surface_api.token_raw(l_token), 'TEST', 1,
                                     systimestamp - interval '1' minute) then
      fail('a record unchanged since the read must be fresh');
    end if;
    if road_surface_api.is_fresh(road_surface_api.token_raw(l_token), 'TEST', 1,
                                 systimestamp + interval '1' minute) then
      fail('a record changed since the read must not be fresh');
    end if;
    if road_surface_api.is_fresh(hextoraw(rawtohex(sys_guid())), 'TEST', 1, systimestamp) then
      fail('an unknown token must not be fresh');
    end if;
  end test_token_freshness;

  -- A record the caller may not see and one that does not exist are refused in the same words,
  -- so the refusal cannot be used to find out which records exist.
  procedure test_hidden_and_missing_alike is
    l_hidden  json;
    l_missing json;
  begin
    login('ALICE');
    l_hidden  := road_surface_api.record_not_found(c_action, 'THING_NOT_FOUND', 'No such thing.', 'k-hidden');
    l_missing := road_surface_api.record_not_found(c_action, 'THING_NOT_FOUND', 'No such thing.', 'k-missing');
    assert_eq('decision', 'rejected', json_value(l_hidden, '$.decision'));
    assert_eq('rule', 'THING_NOT_FOUND', json_value(l_hidden, '$.rejections[0].rule_id'));
    assert_eq('retryable', 'false', json_value(l_hidden, '$.rejections[0].retryable'));
    if json_exists(l_hidden, '$.rejections[0].ids') then fail('a not-found refusal must carry no ids'); end if;
    assert_eq('same message', json_value(l_hidden, '$.rejections[0].message'),
              json_value(l_missing, '$.rejections[0].message'));
    assert_eq('same contract version', json_value(l_hidden, '$.contract_version'),
              json_value(l_missing, '$.contract_version'));
    assert_eq('contract version is the surface''s', road_surface_api.contract_version,
              json_value(l_hidden, '$.contract_version'));
  end test_hidden_and_missing_alike;

  procedure test_accept_uses_surface_version is
    l_out json;
  begin
    login('ALICE');
    l_out := road_surface_api.accept(c_action, '{"id":1}', json('[1]'), 'k-accept');
    assert_eq('decision', 'accepted', json_value(l_out, '$.decision'));
    assert_eq('contract_version', road_surface_api.contract_version, json_value(l_out, '$.contract_version'));
    assert_eq('result.id', '1', json_value(l_out, '$.result.id'));
  end test_accept_uses_surface_version;

  procedure test_envelope is
    l_view clob;
  begin
    l_view := road_surface_api.envelope(json('{"items":[1,2]}'), 'Only yours.');
    assert_eq('contract_version', road_surface_api.contract_version, json_value(l_view, '$.contract_version'));
    assert_eq('scope', 'Only yours.', json_value(l_view, '$.scope'));
    if json_value(l_view, '$.as_at') not like '____-__-__T__:__:__.___Z' then fail('as_at is not ISO 8601 UTC'); end if;
    if json_exists(l_view, '$.change_number') then fail('no change_number unless the view states one'); end if;
    if not json_exists(l_view, '$.items[1]') then fail('the body must be kept'); end if;
    l_view := road_surface_api.envelope(json('{"items":[]}'), p_change_number => 41);
    assert_eq('change_number', '41', json_value(l_view, '$.change_number'));
    assert_eq('default scope', road_surface_api.c_default_scope, json_value(l_view, '$.scope'));
  end test_envelope;

  procedure test_with_version is
  begin
    assert_eq('added', road_surface_api.contract_version,
              json_value(road_surface_api.with_version('{"error":"NOT_FOUND"}'), '$.contract_version'));
    assert_eq('kept', 'NOT_FOUND',
              json_value(road_surface_api.with_version('{"error":"NOT_FOUND"}'), '$.error'));
    assert_eq('not an object', '[1]', road_surface_api.with_version('[1]'));
    assert_eq('null', null, road_surface_api.with_version(null));
  end test_with_version;

  procedure run_all is
    procedure rollback_if_possible is
    begin
      rollback to savepoint sp_surface;
    exception
      when others then
        if sqlcode != -1086 then
          raise;
        end if;
    end rollback_if_possible;

    procedure exec(p_name in varchar2) is
    begin
      savepoint sp_surface;
      case p_name
        when 'version'           then test_version;
        when 'natural_key'       then test_natural_key;
        when 'token_raw_bad'     then test_token_raw_bad;
        when 'token_freshness'   then test_token_freshness;
        when 'hidden_and_missing' then test_hidden_and_missing_alike;
        when 'accept_version'    then test_accept_uses_surface_version;
        when 'envelope'          then test_envelope;
        when 'with_version'      then test_with_version;
        else fail('unknown test ' || p_name);
      end case;
      dbms_output.put_line('PASS ' || p_name);
      l_pass := l_pass + 1;
      rollback_if_possible;
      road_ctx_pkg.end_request;
    exception
      when others then
        dbms_output.put_line('FAIL ' || p_name || ': ' || sqlerrm);
        l_fail := l_fail + 1;
        rollback_if_possible;
        road_ctx_pkg.end_request;
    end exec;
  begin
    l_pass := 0;
    l_fail := 0;
    setup;

    exec('version');
    exec('natural_key');
    exec('token_raw_bad');
    exec('token_freshness');
    exec('hidden_and_missing');
    exec('accept_version');
    exec('envelope');
    exec('with_version');

    teardown;
    dbms_output.put_line('road_surface_api_test: ' || l_pass || ' passed, ' || l_fail || ' failed');
  end run_all;

end road_surface_api_test;
/
