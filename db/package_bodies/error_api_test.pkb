create or replace package body error_api_test as

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

  procedure test_handle_known_validation is
    l_status   number;
    l_response clob;
  begin
    begin
      raise_application_error(-20001, 'start must be before end');
    exception
      when others then
        error_api.handle_known(sqlcode, sqlerrm, l_status, l_response);
    end;
    assert_eq('status', '400', to_char(l_status));
    assert_eq('error', 'VALIDATION_ERROR', json_value(l_response, '$.error'));
    assert_eq('message', 'start must be before end', json_value(l_response, '$.message'));
    assert_eq('ora_code', 'ORA-20001', json_value(l_response, '$.ora_code'));
  end test_handle_known_validation;

  procedure test_handle_known_agenda_locked is
    l_status   number;
    l_response clob;
  begin
    begin
      raise_application_error(-20003, 'agenda is locked');
    exception
      when others then
        error_api.handle_known(sqlcode, sqlerrm, l_status, l_response);
    end;
    assert_eq('status', '422', to_char(l_status));
    assert_eq('error', 'AGENDA_LOCKED', json_value(l_response, '$.error'));
  end test_handle_known_agenda_locked;

  procedure test_handle_known_not_found is
    l_status   number;
    l_response clob;
  begin
    begin
      raise_application_error(-20004, 'instance 1001 not found');
    exception
      when others then
        error_api.handle_known(sqlcode, sqlerrm, l_status, l_response);
    end;
    assert_eq('status', '404', to_char(l_status));
    assert_eq('error', 'NOT_FOUND', json_value(l_response, '$.error'));
  end test_handle_known_not_found;

  -- spec-patch-06 section 6.4: an authenticated principal denied by require_permission must map to
  -- 403, not 401 and not 500. Raised through road_ctx_pkg.c_forbidden in real use.
  procedure test_handle_known_forbidden is
    l_status   number;
    l_response clob;
  begin
    begin
      raise_application_error(-20403, 'Permission required: events.purge');
    exception
      when others then
        error_api.handle_known(sqlcode, sqlerrm, l_status, l_response);
    end;
    assert_eq('status', '403', to_char(l_status));
    assert_eq('error', 'FORBIDDEN', json_value(l_response, '$.error'));
    assert_eq('message', 'Permission required: events.purge', json_value(l_response, '$.message'));
    assert_eq('ora_code', 'ORA-20403', json_value(l_response, '$.ora_code'));
  end test_handle_known_forbidden;

  procedure test_handle_known_conflict is
    l_status   number;
    l_response clob;
  begin
    begin
      raise_application_error(-20009, 'stale read_token');
    exception
      when others then
        error_api.handle_known(sqlcode, sqlerrm, l_status, l_response);
    end;
    assert_eq('status', '409', to_char(l_status));
    assert_eq('error', 'CONFLICT', json_value(l_response, '$.error'));
  end test_handle_known_conflict;

  procedure test_handle_known_unmapped_escalates is
    l_status     number;
    l_response   clob;
    l_log_count  number;
  begin
    begin
      raise_application_error(-20050, 'not a real mapped code');
    exception
      when others then
        error_api.handle_known(sqlcode, sqlerrm, l_status, l_response);
    end;
    assert_eq('status', '500', to_char(l_status));
    assert_eq('error', 'INTERNAL_ERROR', json_value(l_response, '$.error'));
    assert_eq('message', 'An unexpected error occurred', json_value(l_response, '$.message'));

    select count(*) into l_log_count
      from error_log
     where sqlcode = -20050;
    if l_log_count = 0 then
      raise_application_error(-20000, 'expected an error_log row for the unmapped code');
    end if;

    -- write_error_log commits autonomously; the outer SAVEPOINT/ROLLBACK in run_all cannot
    -- undo it, so clean up explicitly (per calendar-build-instructions.md's standing rule).
    delete from error_log where sqlcode = -20050;
    commit;
  end test_handle_known_unmapped_escalates;

  procedure test_handle_unknown is
    l_status    number;
    l_response  clob;
    l_log_count number;
  begin
    error_api.handle_unknown(
      p_sqlerrm     => 'ORA-00001: unique constraint violated',
      p_backtrace   => 'fake backtrace for test',
      p_context     => 'error_api_test.test_handle_unknown',
      p_status_code => l_status,
      p_response    => l_response
    );
    assert_eq('status', '500', to_char(l_status));
    assert_eq('error', 'INTERNAL_ERROR', json_value(l_response, '$.error'));
    assert_eq('message', 'An unexpected error occurred', json_value(l_response, '$.message'));

    select count(*) into l_log_count
      from error_log
     where context = 'error_api_test.test_handle_unknown';
    if l_log_count = 0 then
      raise_application_error(-20000, 'expected an error_log row from handle_unknown');
    end if;

    delete from error_log where context = 'error_api_test.test_handle_unknown';
    commit;
  end test_handle_unknown;

  procedure run_all is
    l_pass number := 0;
    l_fail number := 0;

    -- Tests that assert on error_log commit their own cleanup DELETE (autonomous rows can't be
    -- undone by ROLLBACK TO SAVEPOINT), which invalidates any savepoint taken before that
    -- commit — so ROLLBACK TO SAVEPOINT here may legitimately find nothing to roll back
    -- (ORA-01086). That's expected, not a failure; only re-raise other errors.
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
        when 'validation'         then test_handle_known_validation;
        when 'agenda_locked'      then test_handle_known_agenda_locked;
        when 'not_found'          then test_handle_known_not_found;
        when 'conflict'           then test_handle_known_conflict;
        when 'forbidden'          then test_handle_known_forbidden;
        when 'unmapped_escalates' then test_handle_known_unmapped_escalates;
        when 'handle_unknown'     then test_handle_unknown;
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
    run('test_handle_known_validation', 'validation');
    run('test_handle_known_agenda_locked', 'agenda_locked');
    run('test_handle_known_not_found', 'not_found');
    run('test_handle_known_conflict', 'conflict');
    run('test_handle_known_forbidden', 'forbidden');
    run('test_handle_known_unmapped_escalates', 'unmapped_escalates');
    run('test_handle_unknown', 'handle_unknown');

    dbms_output.put_line('error_api_test: ' || l_pass || ' passed, ' || l_fail || ' failed');
  end run_all;

end error_api_test;
/
