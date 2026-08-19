create or replace package body road_audit_api_test as

  c_app_schema constant varchar2(30) := 'ROAD_CAL_TEST';

  procedure assert_true(p_label in varchar2, p_condition in boolean) is
  begin
    if p_condition is null or not p_condition then
      raise_application_error(-20000, p_label || ': expected TRUE, got ' ||
        case p_condition when true then 'TRUE' when false then 'FALSE' else 'NULL' end);
    end if;
  end assert_true;

  procedure assert_eq(p_label in varchar2, p_expected in varchar2, p_actual in varchar2) is
  begin
    if p_actual is null or p_expected is null or p_actual != p_expected then
      raise_application_error(
        -20000,
        p_label || ': expected [' || p_expected || '] got [' || p_actual || ']'
      );
    end if;
  end assert_eq;

  -- issue_read_token / check_fresh both commit autonomously; SAVEPOINT/ROLLBACK in run_all
  -- cannot undo those rows, so every test cleans up its own road_api_log rows explicitly.
  procedure cleanup(p_log_id in raw) is
  begin
    delete from road_api_log where log_id = p_log_id;
    commit;
  end cleanup;

  procedure test_issue_read_token_creates_row is
    l_guid  raw(16);
    l_count number;
  begin
    l_guid := road_audit_api.issue_read_token(
      p_caller_type => 'BROWSER',
      p_app_schema  => c_app_schema,
      p_endpoint    => 'get_events_for_range',
      p_caller_ref  => 'test-session'
    );
    assert_true('guid not null', l_guid is not null);

    select count(*) into l_count
      from road_api_log
     where log_id = l_guid
       and caller_type = 'BROWSER'
       and caller_ref = 'test-session'
       and app_schema = c_app_schema
       and endpoint = 'get_events_for_range'
       and outcome = 'OK';
    assert_eq('row count', '1', to_char(l_count));

    cleanup(l_guid);
  end test_issue_read_token_creates_row;

  procedure test_check_fresh_true_when_unchanged is
    l_guid   raw(16);
    l_fresh  boolean;
  begin
    l_guid := road_audit_api.issue_read_token(
      p_caller_type => 'BROWSER',
      p_app_schema  => c_app_schema,
      p_endpoint    => 'get_event'
    );

    l_fresh := road_audit_api.check_fresh(
      p_guid               => l_guid,
      p_app_schema         => c_app_schema,
      p_entity_type        => 'EVENT_INSTANCES',
      p_entity_id          => '1001',
      p_current_updated_at => systimestamp - interval '1' second
    );
    assert_true('fresh when unchanged', l_fresh);

    cleanup(l_guid);
  end test_check_fresh_true_when_unchanged;

  procedure test_check_fresh_false_when_stale is
    l_guid   raw(16);
    l_fresh  boolean;
    l_outcome road_api_log.outcome%type;
  begin
    l_guid := road_audit_api.issue_read_token(
      p_caller_type => 'BROWSER',
      p_app_schema  => c_app_schema,
      p_endpoint    => 'get_event'
    );

    l_fresh := road_audit_api.check_fresh(
      p_guid               => l_guid,
      p_app_schema         => c_app_schema,
      p_entity_type        => 'EVENT_INSTANCES',
      p_entity_id          => '1001',
      p_current_updated_at => systimestamp + interval '1' second
    );
    assert_true('stale when row changed after token issued', not l_fresh);

    select outcome into l_outcome from road_api_log where log_id = l_guid;
    assert_eq('outcome', 'STALE_REJECTED', l_outcome);

    cleanup(l_guid);
  end test_check_fresh_false_when_stale;

  procedure test_check_fresh_false_for_unknown_guid is
    l_fresh boolean;
  begin
    l_fresh := road_audit_api.check_fresh(
      p_guid               => sys_guid(),
      p_app_schema         => c_app_schema,
      p_entity_type        => 'EVENT_INSTANCES',
      p_entity_id          => '1001',
      p_current_updated_at => systimestamp
    );
    assert_true('unknown guid treated as stale', not l_fresh);
  end test_check_fresh_false_for_unknown_guid;

  procedure run_all is
    l_pass number := 0;
    l_fail number := 0;

    -- cleanup() commits (autonomous rows can't be undone by ROLLBACK TO SAVEPOINT), which
    -- invalidates any savepoint taken before that commit, so ROLLBACK TO SAVEPOINT here may
    -- legitimately find nothing to roll back (ORA-01086). Expected, not a failure.
    procedure rollback_if_possible is
    begin
      rollback to savepoint before_test;
    exception
      when others then
        if sqlcode != -1086 then
          raise;
        end if;
    end rollback_if_possible;

    procedure run(p_name in varchar2, p_proc in varchar2) is
    begin
      savepoint before_test;
      case p_proc
        when 'issue_creates_row'    then test_issue_read_token_creates_row;
        when 'fresh_when_unchanged' then test_check_fresh_true_when_unchanged;
        when 'stale_when_changed'   then test_check_fresh_false_when_stale;
        when 'unknown_guid'         then test_check_fresh_false_for_unknown_guid;
      end case;
      rollback_if_possible;
      dbms_output.put_line('PASS ' || p_name);
      l_pass := l_pass + 1;
    exception
      when others then
        rollback_if_possible;
        dbms_output.put_line('FAIL ' || p_name || ': ' || sqlerrm);
        l_fail := l_fail + 1;
    end run;
  begin
    run('test_issue_read_token_creates_row', 'issue_creates_row');
    run('test_check_fresh_true_when_unchanged', 'fresh_when_unchanged');
    run('test_check_fresh_false_when_stale', 'stale_when_changed');
    run('test_check_fresh_false_for_unknown_guid', 'unknown_guid');

    dbms_output.put_line('road_audit_api_test: ' || l_pass || ' passed, ' || l_fail || ' failed');
  end run_all;

end road_audit_api_test;
/
