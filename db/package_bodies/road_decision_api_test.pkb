create or replace package body road_decision_api_test as

  -- The tests that carry this package are test_accept_rolls_back_with_caller and
  -- test_reject_survives_rollback: together they are GSC definition section 6.7.3 and 6.7.4, and
  -- ledger D-05's reason for an autonomous refusal record.

  c_issuer  constant varchar2(64)  := 'urn:road:test:decision';
  c_action  constant varchar2(200) := 'test.road_decision.action';
  c_version constant varchar2(40)  := '1.0.0';

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

  function principal_of(p_subject in varchar2) return number is
    l_id number;
  begin
    select principal_id into l_id
      from road_principals where issuer = c_issuer and subject = p_subject;
    return l_id;
  end principal_of;

  procedure login(p_subject in varchar2) is
  begin
    if not road_ctx_pkg.begin_request(p_subject, c_issuer) then
      fail('could not establish ' || p_subject);
    end if;
  end login;

  function rows_for(p_audit_id in number) return number is
    l_count number;
  begin
    select count(*) into l_count from road_decisions where decision_id = p_audit_id;
    return l_count;
  end rows_for;

  -- Rejected rows are committed autonomously, so the runner's savepoint cannot remove them.
  procedure purge_test_decisions is
  begin
    delete from road_decisions where action_id like 'test.road_decision.%';
    commit;
  end purge_test_decisions;

  procedure setup is
  begin
    execute immediate 'alter session disable parallel dml';

    insert into road_principals (issuer, subject, display_name, status)
    select c_issuer, 'ALICE', 'road_decision test fixture', 'ACTIVE' from dual
     where not exists (select 1 from road_principals where issuer = c_issuer and subject = 'ALICE');
    insert into road_principals (issuer, subject, display_name, status)
    select c_issuer, 'BOB', 'road_decision test fixture', 'ACTIVE' from dual
     where not exists (select 1 from road_principals where issuer = c_issuer and subject = 'BOB');
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

  ---------------------------------------------------------------------------
  -- Outcome shape (GSC definition section 6.4)
  ---------------------------------------------------------------------------

  procedure test_accept_outcome_and_record is
    l_out json;
    l_id  number;
    l_pid number;
  begin
    login('ALICE');
    l_out := road_decision_api.accept(c_action, c_version, json('{"item_id":42}'),
                                      json('[42]'), 'k-accept');
    assert_eq('decision', 'accepted', json_value(l_out, '$.decision'));
    assert_eq('contract_version', c_version, json_value(l_out, '$.contract_version'));
    assert_eq('result.item_id', '42', json_value(l_out, '$.result.item_id'));
    l_id := json_value(l_out, '$.audit_id' returning number);
    if l_id is null then fail('no audit_id'); end if;

    -- The principal comes from the session context, never from a parameter.
    select principal_id into l_pid from road_decisions where decision_id = l_id;
    assert_eq('principal', to_char(principal_of('ALICE')), to_char(l_pid));
  end test_accept_outcome_and_record;

  procedure test_reject_outcome_shape is
    l_out json;
  begin
    login('ALICE');
    -- One object, not an array: reject wraps it.
    l_out := road_decision_api.reject(
      c_action, c_version,
      road_decision_api.rejection('ITEM_ALREADY_CLAIMED', 'Claimed by another principal.', true,
                                  json('[42]')));
    assert_eq('decision', 'rejected', json_value(l_out, '$.decision'));
    assert_eq('rule_id', 'ITEM_ALREADY_CLAIMED', json_value(l_out, '$.rejections[0].rule_id'));
    assert_eq('retryable', 'true', json_value(l_out, '$.rejections[0].retryable'));
    assert_eq('ids', '42', json_value(l_out, '$.rejections[0].ids[0]'));
    if json_value(l_out, '$.audit_id' returning number) is null then fail('no audit_id'); end if;
    if json_exists(l_out, '$.result') then fail('a rejection carries no result'); end if;
  end test_reject_outcome_shape;

  ---------------------------------------------------------------------------
  -- Transactions (GSC definition sections 6.7.3 and 6.7.4)
  ---------------------------------------------------------------------------

  -- An accepted record is in the caller's transaction, so it goes when the change goes.
  procedure test_accept_rolls_back_with_caller is
    l_id number;
  begin
    login('ALICE');
    savepoint before_accept;
    l_id := json_value(road_decision_api.accept(c_action, c_version), '$.audit_id'
                       returning number);
    assert_eq('row before rollback', '1', to_char(rows_for(l_id)));
    rollback to savepoint before_accept;
    assert_eq('row after rollback', '0', to_char(rows_for(l_id)));
  end test_accept_rolls_back_with_caller;

  -- A rejected record is autonomous, so it survives the rollback of the rejected change.
  procedure test_reject_survives_rollback is
    l_id number;
  begin
    login('ALICE');
    savepoint before_reject;
    l_id := json_value(
      road_decision_api.reject(c_action, c_version,
        road_decision_api.rejection('STALE_TOKEN', 'The item has changed.', true)),
      '$.audit_id' returning number);
    rollback to savepoint before_reject;
    assert_eq('row after rollback', '1', to_char(rows_for(l_id)));
  end test_reject_survives_rollback;

  ---------------------------------------------------------------------------
  -- Idempotency (GSC definition section 6.5)
  ---------------------------------------------------------------------------

  procedure test_replay_is_per_principal is
    l_first  json;
    l_replay json;
  begin
    login('ALICE');
    l_first := road_decision_api.accept(c_action, c_version, json('{"n":1}'),
                                        p_idempotency_key => 'k-replay');
    l_replay := road_decision_api.prior_outcome(c_action, 'k-replay');
    assert_eq('replayed audit_id', json_value(l_first, '$.audit_id'),
              json_value(l_replay, '$.audit_id'));
    assert_eq('replayed result', '1', json_value(l_replay, '$.result.n'));

    -- Bob sending the same key must not see Alice's outcome.
    road_ctx_pkg.end_request;
    login('BOB');
    if road_decision_api.prior_outcome(c_action, 'k-replay') is not null then
      fail('another principal replayed Alice''s outcome');
    end if;
  end test_replay_is_per_principal;

  procedure test_rejection_keeps_key_by_default is
    l_rej json;
  begin
    login('ALICE');
    l_rej := road_decision_api.reject(c_action, c_version,
      road_decision_api.rejection('LOCK_HELD', 'Locked by another principal.', true),
      p_idempotency_key => 'k-retry');
    if road_decision_api.prior_outcome(c_action, 'k-retry') is not null then
      fail('a rejection consumed the key');
    end if;
    assert_eq('replay with rejections', json_value(l_rej, '$.audit_id'),
              json_value(road_decision_api.prior_outcome(c_action, 'k-retry', true),
                         '$.audit_id'));
    -- And the retry can then be accepted under the same key.
    if json_value(road_decision_api.accept(c_action, c_version,
                    p_idempotency_key => 'k-retry'), '$.decision') != 'accepted' then
      fail('retry under the same key was not accepted');
    end if;
  end test_rejection_keeps_key_by_default;

  procedure test_second_accept_same_key_refused is
    l_out    json;
    l_raised boolean := false;
  begin
    login('ALICE');
    l_out := road_decision_api.accept(c_action, c_version, p_idempotency_key => 'k-dup');
    begin
      l_out := road_decision_api.accept(c_action, c_version, p_idempotency_key => 'k-dup');
    exception
      when dup_val_on_index then
        l_raised := true;
    end;
    if not l_raised then fail('a second accepted decision under one key was allowed'); end if;
  end test_second_accept_same_key_refused;

  ---------------------------------------------------------------------------
  -- Non-disclosure (GSC definition section 6.4.4), public actions, misuse
  ---------------------------------------------------------------------------

  procedure test_undisclosed_records_truth is
    l_out       json;
    l_id        number;
    l_decision  varchar2(8);
    l_disclosed number;
  begin
    l_out := road_decision_api.reject_undisclosed(
      'test.road_decision.subscribe', c_version,
      road_decision_api.rejection('ADDRESS_SUPPRESSED', 'The address is suppressed.', false),
      json('{"status":"pending"}'));
    assert_eq('reported decision', 'accepted', json_value(l_out, '$.decision'));
    assert_eq('reported result', 'pending', json_value(l_out, '$.result.status'));
    if json_exists(l_out, '$.rejections') then fail('the rejection was disclosed'); end if;

    l_id := json_value(l_out, '$.audit_id' returning number);
    select decision, case when disclosed then 1 else 0 end
      into l_decision, l_disclosed
      from road_decisions where decision_id = l_id;
    assert_eq('recorded decision', 'rejected', l_decision);
    assert_eq('recorded disclosed', '0', to_char(l_disclosed));
  end test_undisclosed_records_truth;

  -- No begin_request: an action the contract declares public. The record has no principal.
  procedure test_public_action_has_no_principal is
    l_id  number;
    l_pid number;
  begin
    road_ctx_pkg.end_request;
    l_id := json_value(road_decision_api.accept('test.road_decision.public', c_version),
                       '$.audit_id' returning number);
    select principal_id into l_pid from road_decisions where decision_id = l_id;
    if l_pid is not null then fail('public decision recorded a principal'); end if;
  end test_public_action_has_no_principal;

  procedure test_reject_needs_a_rejection is
    l_out json;
  begin
    login('ALICE');
    begin
      l_out := road_decision_api.reject(c_action, c_version, json('[]'));
      fail('an empty rejection list was accepted');
    exception
      when others then
        if sqlcode != road_decision_api.c_misuse then raise; end if;
    end;
    begin
      l_out := road_decision_api.reject(c_action, c_version,
                 json('{"message":"no rule","retryable":false}'));
      fail('a rejection with no rule_id was accepted');
    exception
      when others then
        if sqlcode != road_decision_api.c_misuse then raise; end if;
    end;
  end test_reject_needs_a_rejection;

  procedure run_all is
    -- Tests that reject commit autonomously, which can leave the savepoint unusable
    -- (ORA-01086). Expected, not a failure -- the same handling as error_api_test.
    procedure rollback_if_possible is
    begin
      rollback to savepoint sp_decision;
    exception
      when others then
        if sqlcode != -1086 then
          raise;
        end if;
    end rollback_if_possible;

    procedure exec(p_name in varchar2) is
    begin
      savepoint sp_decision;
      case p_name
        when 'accept_outcome'        then test_accept_outcome_and_record;
        when 'reject_outcome'        then test_reject_outcome_shape;
        when 'accept_rolls_back'     then test_accept_rolls_back_with_caller;
        when 'reject_survives'       then test_reject_survives_rollback;
        when 'replay_per_principal'  then test_replay_is_per_principal;
        when 'rejection_keeps_key'   then test_rejection_keeps_key_by_default;
        when 'second_accept_refused' then test_second_accept_same_key_refused;
        when 'undisclosed_truth'     then test_undisclosed_records_truth;
        when 'public_no_principal'   then test_public_action_has_no_principal;
        when 'reject_needs_one'      then test_reject_needs_a_rejection;
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

    exec('accept_outcome');
    exec('reject_outcome');
    exec('accept_rolls_back');
    exec('reject_survives');
    exec('replay_per_principal');
    exec('rejection_keeps_key');
    exec('second_accept_refused');
    exec('undisclosed_truth');
    exec('public_no_principal');
    exec('reject_needs_one');

    teardown;
    dbms_output.put_line('road_decision_api_test: ' || l_pass || ' passed, ' || l_fail || ' failed');
  end run_all;

end road_decision_api_test;
/
