create or replace package body demo_todo_api_test as

  -- The tests that carry this package are test_other_owners_todo_is_not_found (the ownership seam)
  -- and test_stale_token_leaves_no_change (the concurrency seam). The rest cover each rule of
  -- contract/hello_world.gsc.json, replays, the view envelope and the reserved purge.

  c_issuer constant varchar2(64) := 'urn:road:test:demo_todo';

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

  procedure setup is
    l_owner number;
    l_other number;
    l_admin number;
  begin
    execute immediate 'alter session disable parallel dml';

    -- OWNER holds the ordinary todo permissions; OTHER holds the same but owns different rows;
    -- ADMIN holds todo_admin only. Three principals is the minimum that can show ownership
    -- isolation AND that an administrator crosses it.
    insert into road_principals (issuer, subject, display_name, status)
    select c_issuer, 'OWNER', 'demo_todo test fixture', 'ACTIVE' from dual
     where not exists (select 1 from road_principals where issuer = c_issuer and subject = 'OWNER');
    insert into road_principals (issuer, subject, display_name, status)
    select c_issuer, 'OTHER', 'demo_todo test fixture', 'ACTIVE' from dual
     where not exists (select 1 from road_principals where issuer = c_issuer and subject = 'OTHER');
    insert into road_principals (issuer, subject, display_name, status)
    select c_issuer, 'ADMIN', 'demo_todo test fixture', 'ACTIVE' from dual
     where not exists (select 1 from road_principals where issuer = c_issuer and subject = 'ADMIN');

    -- Resolved into locals first: a private packaged function may not be used inside a SQL
    -- statement (PLS-00231).
    l_owner := principal_of('OWNER');
    l_other := principal_of('OTHER');
    l_admin := principal_of('ADMIN');

    insert into road_principal_roles (principal_id, role_name)
    select l_owner, 'user' from dual
     where not exists (select 1 from road_principal_roles
                        where principal_id = l_owner and role_name = 'user');
    insert into road_principal_roles (principal_id, role_name)
    select l_other, 'user' from dual
     where not exists (select 1 from road_principal_roles
                        where principal_id = l_other and role_name = 'user');
    insert into road_principal_roles (principal_id, role_name)
    select l_admin, 'todo_admin' from dual
     where not exists (select 1 from road_principal_roles
                        where principal_id = l_admin and role_name = 'todo_admin');

    commit;
  end setup;

  procedure teardown is
  begin
    delete from demo_todos
     where owner_principal_id in (select principal_id from road_principals where issuer = c_issuer);
    -- Refusals are recorded autonomously, so the runner's rollback leaves them behind.
    delete from road_decisions
     where principal_id in (select principal_id from road_principals where issuer = c_issuer);
    delete from road_principal_roles
     where principal_id in (select principal_id from road_principals where issuer = c_issuer);
    delete from road_principals where issuer = c_issuer;
    commit;
    road_ctx_pkg.end_request;
  end teardown;

  -- Creates a todo directly, bypassing the API, so a test can arrange state without depending on
  -- create_todo being correct.
  function seed_todo(p_subject in varchar2, p_title in varchar2,
                     p_status in varchar2 default 'OPEN') return number is
    l_id    number;
    l_owner number;
  begin
    l_owner := principal_of(p_subject);
    insert into demo_todos (owner_principal_id, title, status)
    values (l_owner, p_title, p_status)
    returning todo_id into l_id;
    return l_id;
  end seed_todo;

  procedure be(p_subject in varchar2) is
  begin
    if not road_ctx_pkg.begin_request(p_subject, c_issuer) then fail('could not establish ' || p_subject); end if;
  end be;

  -- One read of the caller's todos: its token covers every todo it returned.
  function read_token return varchar2 is
  begin
    return json_value(demo_todo_api.list_todos, '$.read_token');
  end read_token;

  function body_with(p_token in varchar2, p_extra in varchar2 default null) return json is
  begin
    return json('{"read_token":"' || p_token || '"' || case when p_extra is not null then ',' || p_extra end || '}');
  end body_with;

  function status_of(p_id in number) return varchar2 is
    l_status varchar2(10);
  begin
    select status into l_status from demo_todos where todo_id = p_id;
    return l_status;
  end status_of;

  function owner_of(p_id in number) return number is
    l_owner number;
  begin
    select owner_principal_id into l_owner from demo_todos where todo_id = p_id;
    return l_owner;
  end owner_of;

  function title_of(p_id in number) return varchar2 is
    l_title varchar2(200);
  begin
    select title into l_title from demo_todos where todo_id = p_id;
    return l_title;
  end title_of;

  function count_of(p_a in number, p_b in number) return number is
    l_count number;
  begin
    select count(*) into l_count from demo_todos where todo_id in (p_a, p_b);
    return l_count;
  end count_of;

  function decision(p_out in json) return varchar2 is begin return json_value(p_out, '$.decision'); end;
  function rule(p_out in json) return varchar2 is begin return json_value(p_out, '$.rejections[0].rule_id'); end;

  function raises(p_code in number, p_block in varchar2) return boolean is
  begin
    execute immediate 'declare x json; c clob; begin ' || p_block || ' end;';
    return false;
  exception
    when others then
      return sqlcode = p_code;
  end raises;

  ---------------------------------------------------------------------------
  -- Creating
  ---------------------------------------------------------------------------

  procedure test_create_takes_owner_from_session is
    l_out json;
    l_id  number;
  begin
    be('OWNER');
    l_out := demo_todo_api.create_todo(json('{"title":"buy milk","notes":"semi"}'), 'k-create-1');
    assert_eq('decision', 'accepted', decision(l_out));
    assert_eq('contract_version', road_surface_api.contract_version, json_value(l_out, '$.contract_version'));
    l_id := json_value(l_out, '$.result.todo_id' returning number);
    assert_eq('owner', to_char(principal_of('OWNER')), to_char(owner_of(l_id)));
    assert_eq('status', 'OPEN', json_value(l_out, '$.result.status'));
    if json_value(l_out, '$.result.read_token') is null then fail('an accepted create returns a read token'); end if;
  end test_create_takes_owner_from_session;

  procedure test_create_refuses_a_named_owner is
  begin
    be('OWNER');
    if not raises(-20001, 'x := demo_todo_api.create_todo(json(''{"title":"t","owner_principal_id":1}''), ''k-owner'');') then
      fail('a body that names an owner is a wrong call');
    end if;
  end test_create_refuses_a_named_owner;

  procedure test_create_wrong_calls is
  begin
    be('OWNER');
    if not raises(-20001, 'x := demo_todo_api.create_todo(json(''{"notes":"no title"}''), ''k-w1'');') then fail('title required'); end if;
    if not raises(-20001, 'x := demo_todo_api.create_todo(json(''{"title":"t"}''), null);') then fail('key required'); end if;
    if not raises(-20001, 'x := demo_todo_api.create_todo(json(''{"title":"t","due_at":"tomorrow"}''), ''k-w3'');') then fail('due_at must parse'); end if;
  end test_create_wrong_calls;

  procedure test_create_title_taken is
    l_first  json;
    l_second json;
    l_count  number;
    l_owner  number;
  begin
    be('OWNER');
    l_first := demo_todo_api.create_todo(json('{"title":"Same"}'), 'k-t1');
    l_second := demo_todo_api.create_todo(json('{"title":"same"}'), 'k-t2');
    assert_eq('first', 'accepted', decision(l_first));
    assert_eq('second', 'rejected', decision(l_second));
    assert_eq('rule', 'TITLE_TAKEN', rule(l_second));
    assert_eq('ids', json_value(l_first, '$.result.todo_id'), json_value(l_second, '$.rejections[0].ids[0]'));
    l_owner := principal_of('OWNER');
    select count(*) into l_count from demo_todos
     where owner_principal_id = l_owner and lower(title) = 'same';
    assert_eq('one row', '1', to_char(l_count));
  end test_create_title_taken;

  procedure test_create_replays_by_key is
    l_first  json;
    l_second json;
    l_count  number;
    l_owner  number;
  begin
    be('OWNER');
    l_first := demo_todo_api.create_todo(json('{"title":"once"}'), 'k-replay');
    l_second := demo_todo_api.create_todo(json('{"title":"once"}'), 'k-replay');
    assert_eq('same decision', json_value(l_first, '$.audit_id'), json_value(l_second, '$.audit_id'));
    l_owner := principal_of('OWNER');
    select count(*) into l_count from demo_todos where title = 'once' and owner_principal_id = l_owner;
    assert_eq('one row', '1', to_char(l_count));
  end test_create_replays_by_key;

  ---------------------------------------------------------------------------
  -- Reading
  ---------------------------------------------------------------------------

  procedure test_list_envelope is
    l_ignore number;
    l_view   clob;
  begin
    l_ignore := seed_todo('OWNER', 'listed');
    be('OWNER');
    l_view := demo_todo_api.list_todos;
    assert_eq('contract_version', road_surface_api.contract_version, json_value(l_view, '$.contract_version'));
    if json_value(l_view, '$.as_at') is null then fail('as_at'); end if;
    assert_eq('scope', demo_todo_api.c_scope, json_value(l_view, '$.scope'));
    if json_value(l_view, '$.read_token') is null then fail('read_token'); end if;
    assert_eq('items', 'listed', json_value(l_view, '$.items[0].title'));
  end test_list_envelope;

  -- THE ownership test. A todo belonging to someone else is NOT FOUND, not FORBIDDEN: a 403 would
  -- confirm the row exists, which the caller has not earned.
  procedure test_other_owners_todo_is_not_found is
    l_id number := seed_todo('OTHER', 'not yours');
  begin
    be('OWNER');
    if not raises(road_surface_api.c_not_found, 'c := demo_todo_api.get_todo(' || l_id || ');') then
      fail('another owner''s todo must not be readable');
    end if;
    -- An action refuses it in the same words as a todo that never existed.
    declare
      l_hidden  json := demo_todo_api.revise_todo(l_id, body_with(rawtohex(sys_guid()), '"title":"mine now"'));
      l_missing json := demo_todo_api.revise_todo(-1, body_with(rawtohex(sys_guid()), '"title":"mine now"'));
    begin
      assert_eq('hidden rule', 'TODO_NOT_FOUND', rule(l_hidden));
      assert_eq('missing rule', 'TODO_NOT_FOUND', rule(l_missing));
      assert_eq('same message', json_value(l_hidden, '$.rejections[0].message'), json_value(l_missing, '$.rejections[0].message'));
      if json_exists(l_hidden, '$.rejections[0].ids') then fail('no ids for a hidden todo'); end if;
    end;
    assert_eq('unchanged', 'not yours', title_of(l_id));
  end test_other_owners_todo_is_not_found;

  -- todo_admin holds todo.list_all but NOT todo.list, so it cannot list at all: administering todos
  -- is not using them, and list_all does not imply list.
  procedure test_list_all_does_not_imply_list is
  begin
    be('ADMIN');
    if not raises(-20403, 'c := demo_todo_api.list_todos;') then fail('todo_admin must not be able to list'); end if;
  end test_list_all_does_not_imply_list;

  procedure test_own_owner_param_is_not_escalation is
    l_view clob;
  begin
    be('OWNER');
    l_view := demo_todo_api.list_todos(p_owner => principal_of('OWNER'));
    if json_value(l_view, '$.read_token') is null then fail('listing yourself by id is not an escalation'); end if;
  end test_own_owner_param_is_not_escalation;

  procedure test_listing_another_owner_requires_list_all is
  begin
    be('OWNER');
    if not raises(-20403, 'c := demo_todo_api.list_todos(p_owner => ' || principal_of('OTHER') || ');') then
      fail('another owner''s todos need todo.list_all');
    end if;
  end test_listing_another_owner_requires_list_all;

  ---------------------------------------------------------------------------
  -- Changing (the four rules that carry the read token)
  ---------------------------------------------------------------------------

  -- A stale token is refused, and nothing changes. The token is retryable only after a re-read.
  procedure test_stale_token_leaves_no_change is
    l_id    number := seed_todo('OWNER', 'before');
    l_token varchar2(40);
    l_out   json;
  begin
    be('OWNER');
    l_token := read_token;
    -- Someone else changes it after the read.
    update demo_todos set notes = 'changed elsewhere' where todo_id = l_id;
    l_out := demo_todo_api.revise_todo(l_id, body_with(l_token, '"title":"after"'));
    assert_eq('decision', 'rejected', decision(l_out));
    assert_eq('rule', 'STALE_TOKEN', rule(l_out));
    assert_eq('retryable', 'true', json_value(l_out, '$.rejections[0].retryable'));
    assert_eq('title unchanged', 'before', title_of(l_id));
    -- After a re-read the same change is accepted.
    l_out := demo_todo_api.revise_todo(l_id, body_with(read_token, '"title":"after"'));
    assert_eq('after re-read', 'accepted', decision(l_out));
    assert_eq('title changed', 'after', title_of(l_id));
  end test_stale_token_leaves_no_change;

  procedure test_complete_revise_reopen_cycle is
    l_id  number := seed_todo('OWNER', 'cycle');
    l_out json;
    l_tok varchar2(40);
  begin
    be('OWNER');
    l_out := demo_todo_api.complete_todo(l_id, body_with(read_token));
    assert_eq('complete', 'accepted', decision(l_out));
    assert_eq('done', 'DONE', status_of(l_id));
    l_tok := json_value(l_out, '$.result.read_token');
    -- The token an action returns is good for the next one.
    l_out := demo_todo_api.revise_todo(l_id, body_with(l_tok, '"title":"x"'));
    assert_eq('revise a done todo', 'TODO_DONE', rule(l_out));
    l_out := demo_todo_api.complete_todo(l_id, body_with(l_tok));
    assert_eq('complete twice', 'TODO_DONE', rule(l_out));
    l_out := demo_todo_api.reopen_todo(l_id, body_with(l_tok));
    assert_eq('reopen', 'accepted', decision(l_out));
    assert_eq('open', 'OPEN', status_of(l_id));
    l_tok := json_value(l_out, '$.result.read_token');
    l_out := demo_todo_api.reopen_todo(l_id, body_with(l_tok));
    assert_eq('reopen an open todo', 'TODO_NOT_DONE', rule(l_out));
    assert_eq('still open', 'OPEN', status_of(l_id));
  end test_complete_revise_reopen_cycle;

  -- One read returns many todos with one token, so the key must include the id.
  procedure test_one_token_many_todos is
    l_a   number := seed_todo('OWNER', 'many a');
    l_b   number := seed_todo('OWNER', 'many b');
    l_tok varchar2(40);
  begin
    be('OWNER');
    l_tok := read_token;
    assert_eq('a', 'accepted', decision(demo_todo_api.complete_todo(l_a, body_with(l_tok))));
    assert_eq('b', 'accepted', decision(demo_todo_api.complete_todo(l_b, body_with(l_tok))));
    assert_eq('a done', 'DONE', status_of(l_a));
    assert_eq('b done', 'DONE', status_of(l_b));
  end test_one_token_many_todos;

  procedure test_same_token_same_todo_replays is
    l_id    number := seed_todo('OWNER', 'replay me');
    l_tok   varchar2(40);
    l_first json;
    l_again json;
  begin
    be('OWNER');
    l_tok := read_token;
    l_first := demo_todo_api.complete_todo(l_id, body_with(l_tok));
    l_again := demo_todo_api.complete_todo(l_id, body_with(l_tok));
    assert_eq('accepted', 'accepted', decision(l_again));
    assert_eq('the same decision', json_value(l_first, '$.audit_id'), json_value(l_again, '$.audit_id'));
  end test_same_token_same_todo_replays;

  procedure test_revise_wrong_calls is
    l_id number := seed_todo('OWNER', 'wrong');
  begin
    be('OWNER');
    if not raises(-20001, 'x := demo_todo_api.revise_todo(' || l_id || ', json(''{"title":"t"}''));') then fail('read_token is required'); end if;
    if not raises(-20001, 'x := demo_todo_api.revise_todo(' || l_id || ', json(''{"read_token":"not hex","title":"t"}''));') then fail('read_token must be a token'); end if;
    if not raises(-20001, 'x := demo_todo_api.revise_todo(' || l_id || ', json(''{"read_token":"' || rawtohex(sys_guid()) || '"}''));') then fail('a revision must change something'); end if;
  end test_revise_wrong_calls;

  procedure test_delete_is_soft is
    l_id  number := seed_todo('OWNER', 'doomed');
    l_tok varchar2(40);
    l_out json;
    l_view clob;
  begin
    be('OWNER');
    l_tok := read_token;
    l_out := demo_todo_api.delete_todo(l_id, body_with(l_tok));
    assert_eq('accepted', 'accepted', decision(l_out));
    assert_eq('row kept', 'DELETED', status_of(l_id));
    if not raises(road_surface_api.c_not_found, 'c := demo_todo_api.get_todo(' || l_id || ');') then fail('a deleted todo is not found'); end if;
    l_view := demo_todo_api.list_todos;
    if json_exists(l_view, '$.items[*]?(@.title == "doomed")') then fail('deleted todos are left out of the list'); end if;
    l_view := demo_todo_api.list_todos(p_status => 'DELETED');
    assert_eq('asked for by name', 'doomed', json_value(l_view, '$.items[0].title'));
    l_out := demo_todo_api.delete_todo(l_id, body_with(read_token));
    assert_eq('delete again', 'TODO_NOT_FOUND', rule(l_out));
  end test_delete_is_soft;

  ---------------------------------------------------------------------------
  -- The reserved purge
  ---------------------------------------------------------------------------

  procedure test_purge_denied_without_permission is
  begin
    be('OWNER');
    if not raises(-20403, 'x := demo_todo_api.purge_todos(json(''{"before":"2999-01-01T00:00:00+00:00"}''), ''k-p0'');') then
      fail('an ordinary user must not purge');
    end if;
  end test_purge_denied_without_permission;

  procedure test_purge_crosses_owners_and_spares_open is
    l_done  number := seed_todo('OWNER', 'finished', 'DONE');
    l_gone  number := seed_todo('OTHER', 'removed', 'DELETED');
    l_open  number := seed_todo('OTHER', 'still open');
    l_out   json;
  begin
    be('ADMIN');
    -- updated_at is trigger-maintained, so the rows cannot be backdated: let a second pass and
    -- purge everything last changed before now.
    dbms_session.sleep(1);
    l_out := demo_todo_api.purge_todos(
      json('{"before":"' || to_char(sys_extract_utc(systimestamp), 'YYYY-MM-DD"T"HH24:MI:SS.FF3"Z"') || '"}'), 'k-p1');
    assert_eq('accepted', 'accepted', decision(l_out));
    if json_value(l_out, '$.result.purged' returning number) < 2 then fail('purge removes done and deleted todos of every owner'); end if;
    assert_eq('open spared', 'OPEN', status_of(l_open));
    assert_eq('done gone', '0', to_char(count_of(l_done, l_gone)));
  end test_purge_crosses_owners_and_spares_open;

  procedure test_purge_refuses_a_future_cutoff is
    l_out json;
  begin
    be('ADMIN');
    l_out := demo_todo_api.purge_todos(json('{"before":"2999-01-01T00:00:00+00:00"}'), 'k-p2');
    assert_eq('decision', 'rejected', decision(l_out));
    assert_eq('rule', 'PURGE_CUTOFF_IN_FUTURE', rule(l_out));
  end test_purge_refuses_a_future_cutoff;

  procedure run_all is
    procedure rollback_if_possible is
    begin
      rollback to savepoint sp_demo;
    exception
      when others then
        if sqlcode != -1086 then
          raise;
        end if;
    end rollback_if_possible;

    procedure exec(p_name in varchar2) is
    begin
      savepoint sp_demo;
      case p_name
        when 'create_owner'        then test_create_takes_owner_from_session;
        when 'create_named_owner'  then test_create_refuses_a_named_owner;
        when 'create_wrong'        then test_create_wrong_calls;
        when 'create_title_taken'  then test_create_title_taken;
        when 'create_replay'       then test_create_replays_by_key;
        when 'list_envelope'       then test_list_envelope;
        when 'other_not_found'     then test_other_owners_todo_is_not_found;
        when 'list_all_not_list'   then test_list_all_does_not_imply_list;
        when 'own_owner_param'     then test_own_owner_param_is_not_escalation;
        when 'other_owner_list'    then test_listing_another_owner_requires_list_all;
        when 'stale_token'         then test_stale_token_leaves_no_change;
        when 'cycle'               then test_complete_revise_reopen_cycle;
        when 'one_token_many'      then test_one_token_many_todos;
        when 'same_token_replays'  then test_same_token_same_todo_replays;
        when 'revise_wrong'        then test_revise_wrong_calls;
        when 'delete_soft'         then test_delete_is_soft;
        when 'purge_denied'        then test_purge_denied_without_permission;
        when 'purge_crosses'       then test_purge_crosses_owners_and_spares_open;
        when 'purge_future'        then test_purge_refuses_a_future_cutoff;
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
    exec('create_owner');
    exec('create_named_owner');
    exec('create_wrong');
    exec('create_title_taken');
    exec('create_replay');
    exec('list_envelope');
    exec('other_not_found');
    exec('list_all_not_list');
    exec('own_owner_param');
    exec('other_owner_list');
    exec('stale_token');
    exec('cycle');
    exec('one_token_many');
    exec('same_token_replays');
    exec('revise_wrong');
    exec('delete_soft');
    exec('purge_denied');
    exec('purge_crosses');
    exec('purge_future');
    teardown;
    dbms_output.put_line('demo_todo_api_test: ' || l_pass || ' passed, ' || l_fail || ' failed');
    if l_fail > 0 then
      raise_application_error(-20000, l_fail || ' demo_todo_api test(s) failed');
    end if;
  end run_all;

end demo_todo_api_test;
/
