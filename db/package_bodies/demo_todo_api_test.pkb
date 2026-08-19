create or replace package body demo_todo_api_test as

  -- The tests that carry this package are test_other_owners_todo_is_not_found (the ownership seam)
  -- and test_stale_read_token_conflicts (the concurrency seam). Everything else is ordinary
  -- coverage of the handler contract.

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

  ---------------------------------------------------------------------------
  -- Ownership (spec-patch-08 section 6.1)
  ---------------------------------------------------------------------------

  -- THE ownership test. A todo belonging to someone else is NOT FOUND, not FORBIDDEN -- a 403
  -- would confirm the row exists, which the caller has not earned.
  procedure test_other_owners_todo_is_not_found is
    l_id     number;
    l_raised boolean := false;
    l_res    json;
  begin
    l_id := seed_todo('OTHER', 'not yours');
    if not road_ctx_pkg.begin_request('OWNER', c_issuer) then fail('establish'); end if;

    begin
      l_res := demo_todo_api.get_todo(json('{"todo_id":' || l_id || '}'));
    exception
      when others then
        l_raised := true;
        if sqlcode != demo_todo_api.c_not_found then
          fail('expected NOT_FOUND (' || demo_todo_api.c_not_found || '), got '
               || sqlcode || ': ' || sqlerrm);
        end if;
    end;
    if not l_raised then fail('another owner''s todo must not be readable'); end if;
  end test_other_owners_todo_is_not_found;

  -- todo_admin holds todo.list_all but NOT todo.list, so it cannot list at all. That is the
  -- separation rule 2 of spec patch 06 applies to road.system_admin, carried into the application:
  -- administering todos is not using them. It also proves list_all does not imply list -- an
  -- easy and invisible mistake to make when wiring the two.
  --
  -- Naming this honestly matters. An earlier draft called it test_admin_can_list_another_owner,
  -- which is the opposite of what it asserts.
  procedure test_list_all_does_not_imply_list is
    l_ignore number;
    l_res    json;
    l_raised boolean := false;
  begin
    l_ignore := seed_todo('OWNER', 'admin cannot see me either');
    if not road_ctx_pkg.begin_request('ADMIN', c_issuer) then fail('establish'); end if;

    begin
      l_res := demo_todo_api.get_todos(json('{"owner":' || principal_of('OWNER') || '}'));
    exception
      when others then
        l_raised := true;
        if sqlcode != road_ctx_pkg.c_forbidden then
          fail('expected forbidden, got ' || sqlcode || ': ' || sqlerrm);
        end if;
    end;
    if not l_raised then fail('todo_admin holds no todo.list and must not be able to list'); end if;
  end test_list_all_does_not_imply_list;

  -- Naming your own principal_id explicitly is not an escalation and must not be treated as one.
  procedure test_own_owner_param_is_not_escalation is
    l_res json;
  begin
    if not road_ctx_pkg.begin_request('OWNER', c_issuer) then fail('establish'); end if;
    l_res := demo_todo_api.get_todos(json('{"owner":' || principal_of('OWNER') || '}'));
    assert_eq('own rows listed', '0', json_value(l_res, '$.offset'));
  end test_own_owner_param_is_not_escalation;

  procedure test_listing_another_owner_requires_list_all is
    l_raised boolean := false;
    l_res    json;
  begin
    if not road_ctx_pkg.begin_request('OWNER', c_issuer) then fail('establish'); end if;
    begin
      l_res := demo_todo_api.get_todos(json('{"owner":' || principal_of('OTHER') || '}'));
    exception
      when others then
        l_raised := true;
        if sqlcode != road_ctx_pkg.c_forbidden then
          fail('expected forbidden, got ' || sqlcode || ': ' || sqlerrm);
        end if;
    end;
    if not l_raised then fail('listing another owner must require todo.list_all'); end if;
  end test_listing_another_owner_requires_list_all;

  ---------------------------------------------------------------------------
  -- Ownership is taken from the session, never the body
  ---------------------------------------------------------------------------

  procedure test_owner_ignores_request_body is
    l_raised boolean := false;
    l_res    json;
  begin
    if not road_ctx_pkg.begin_request('OWNER', c_issuer) then fail('establish'); end if;
    begin
      l_res := demo_todo_api.create_todo(
                 json('{"title":"forged","owner_principal_id":' || principal_of('OTHER') || '}'));
    exception
      when others then
        l_raised := true;
        if sqlcode != demo_todo_api.c_validation then
          fail('expected validation, got ' || sqlcode || ': ' || sqlerrm);
        end if;
    end;
    if not l_raised then
      fail('supplying owner_principal_id must be refused, not silently ignored');
    end if;
  end test_owner_ignores_request_body;

  procedure test_create_takes_owner_from_session is
    l_res json;
  begin
    if not road_ctx_pkg.begin_request('OWNER', c_issuer) then fail('establish'); end if;
    l_res := demo_todo_api.create_todo(json('{"title":"mine"}'));
    assert_eq('owner is the caller', to_char(principal_of('OWNER')),
              json_value(l_res, '$.owner_principal_id'));
    assert_eq('starts OPEN', 'OPEN', json_value(l_res, '$.status'));
  end test_create_takes_owner_from_session;

  ---------------------------------------------------------------------------
  -- Concurrency (spec-patch-08 section 6.2)
  ---------------------------------------------------------------------------

  -- THE concurrency test. A second writer moved the row after this caller read it; the update
  -- must be refused, not silently applied over the top.
  procedure test_stale_read_token_conflicts is
    l_id     number;
    l_token  varchar2(100);
    l_read   json;
    l_raised boolean := false;
    l_res    json;
  begin
    l_id := seed_todo('OWNER', 'contended');
    if not road_ctx_pkg.begin_request('OWNER', c_issuer) then fail('establish'); end if;

    l_read  := demo_todo_api.get_todo(json('{"todo_id":' || l_id || '}'));
    l_token := json_value(l_read, '$.read_token');

    -- Somebody else moves it. The trigger advances updated_at past the token's issued_at.
    update demo_todos set title = 'moved by someone else' where todo_id = l_id;

    begin
      l_res := demo_todo_api.update_todo(
                 json('{"todo_id":' || l_id || ',"read_token":"' || l_token || '","title":"mine"}'));
    exception
      when others then
        l_raised := true;
        if sqlcode != demo_todo_api.c_conflict then
          fail('expected CONFLICT, got ' || sqlcode || ': ' || sqlerrm);
        end if;
    end;
    if not l_raised then fail('a stale read_token must be refused'); end if;

    declare
      l_title varchar2(200 char);
    begin
      select title into l_title from demo_todos where todo_id = l_id;
      assert_eq('the losing write did not land', 'moved by someone else', l_title);
    end;
  end test_stale_read_token_conflicts;

  procedure test_fresh_read_token_updates is
    l_id    number;
    l_token varchar2(100);
    l_read  json;
    l_res   json;
  begin
    l_id := seed_todo('OWNER', 'before');
    if not road_ctx_pkg.begin_request('OWNER', c_issuer) then fail('establish'); end if;

    l_read  := demo_todo_api.get_todo(json('{"todo_id":' || l_id || '}'));
    l_token := json_value(l_read, '$.read_token');

    l_res := demo_todo_api.update_todo(
               json('{"todo_id":' || l_id || ',"read_token":"' || l_token || '","title":"after"}'));
    assert_eq('title updated', 'after', json_value(l_res, '$.title'));
  end test_fresh_read_token_updates;

  procedure test_update_requires_read_token is
    l_id     number;
    l_raised boolean := false;
    l_res    json;
  begin
    l_id := seed_todo('OWNER', 'no token');
    if not road_ctx_pkg.begin_request('OWNER', c_issuer) then fail('establish'); end if;
    begin
      l_res := demo_todo_api.update_todo(json('{"todo_id":' || l_id || ',"title":"x"}'));
    exception
      when others then
        l_raised := true;
        if sqlcode != demo_todo_api.c_validation then
          fail('expected validation, got ' || sqlcode || ': ' || sqlerrm);
        end if;
    end;
    if not l_raised then fail('update without a read_token must be refused'); end if;
  end test_update_requires_read_token;

  ---------------------------------------------------------------------------
  -- Status transitions
  ---------------------------------------------------------------------------

  -- DELETED is not reachable through update. "I finished it" and "I want it gone" are different
  -- intentions and the audit trail should keep them apart.
  procedure test_update_cannot_set_deleted is
    l_id     number;
    l_token  varchar2(100);
    l_raised boolean := false;
    l_res    json;
  begin
    l_id := seed_todo('OWNER', 'not via update');
    if not road_ctx_pkg.begin_request('OWNER', c_issuer) then fail('establish'); end if;
    l_token := json_value(demo_todo_api.get_todo(json('{"todo_id":' || l_id || '}')), '$.read_token');

    begin
      l_res := demo_todo_api.update_todo(
                 json('{"todo_id":' || l_id || ',"read_token":"' || l_token
                      || '","status":"DELETED"}'));
    exception
      when others then
        l_raised := true;
        if sqlcode != demo_todo_api.c_validation then
          fail('expected validation, got ' || sqlcode || ': ' || sqlerrm);
        end if;
    end;
    if not l_raised then fail('update must not set DELETED'); end if;
  end test_update_cannot_set_deleted;

  procedure test_delete_is_soft_and_idempotent is
    l_id    number;
    l_token varchar2(100);
    l_res   json;
    l_count number;
  begin
    l_id := seed_todo('OWNER', 'soft delete me');
    if not road_ctx_pkg.begin_request('OWNER', c_issuer) then fail('establish'); end if;

    l_token := json_value(demo_todo_api.get_todo(json('{"todo_id":' || l_id || '}')), '$.read_token');
    l_res := demo_todo_api.delete_todo(
               json('{"todo_id":' || l_id || ',"read_token":"' || l_token || '"}'));
    assert_eq('first delete reports true', 'true', json_value(l_res, '$.deleted'));

    select count(*) into l_count from demo_todos where todo_id = l_id and status = 'DELETED';
    assert_eq('row survives as DELETED', '1', to_char(l_count));

    l_token := json_value(demo_todo_api.get_todo(json('{"todo_id":' || l_id || '}')), '$.read_token');
    l_res := demo_todo_api.delete_todo(
               json('{"todo_id":' || l_id || ',"read_token":"' || l_token || '"}'));
    assert_eq('second delete reports false, not an error', 'false', json_value(l_res, '$.deleted'));
  end test_delete_is_soft_and_idempotent;

  procedure test_deleted_excluded_from_default_list is
    l_res   json;
    l_id    number;
    l_count number;
  begin
    l_id := seed_todo('OWNER', 'hidden', 'DELETED');
    if not road_ctx_pkg.begin_request('OWNER', c_issuer) then fail('establish'); end if;

    l_res := demo_todo_api.get_todos(null);
    select count(*) into l_count
      from json_table(json_query(l_res, '$.items' returning json), '$[*]'
                      columns (id number path '$.todo_id'))
     where id = l_id;
    assert_eq('DELETED hidden by default', '0', to_char(l_count));

    l_res := demo_todo_api.get_todos(json('{"status":"DELETED"}'));
    select count(*) into l_count
      from json_table(json_query(l_res, '$.items' returning json), '$[*]'
                      columns (id number path '$.todo_id'))
     where id = l_id;
    assert_eq('DELETED visible when asked for', '1', to_char(l_count));
  end test_deleted_excluded_from_default_list;

  ---------------------------------------------------------------------------
  -- Purge -- the reserved permission's subject
  ---------------------------------------------------------------------------

  procedure test_purge_denied_without_permission is
    l_raised boolean := false;
    l_res    json;
  begin
    if not road_ctx_pkg.begin_request('OWNER', c_issuer) then fail('establish'); end if;
    begin
      l_res := demo_todo_api.purge(json('{"before":"2999-01-01T00:00:00.000+00:00"}'));
    exception
      when others then
        l_raised := true;
        if sqlcode != road_ctx_pkg.c_forbidden then
          fail('expected forbidden, got ' || sqlcode || ': ' || sqlerrm);
        end if;
    end;
    if not l_raised then fail('purge must require todo.purge'); end if;
  end test_purge_denied_without_permission;

  -- Purge reaches ACROSS OWNERS and only takes finished rows. Both halves matter: the cross-owner
  -- reach is what makes it dangerous enough to reserve, and sparing OPEN rows is what stops it
  -- being a table truncate with extra steps.
  procedure test_purge_crosses_owners_and_spares_open is
    l_open   number;
    l_done_a number;
    l_done_b number;
    l_res    json;
    l_count  number;
  begin
    l_open   := seed_todo('OWNER', 'still open', 'OPEN');
    l_done_a := seed_todo('OWNER', 'finished a', 'DONE');
    l_done_b := seed_todo('OTHER', 'finished b', 'DONE');

    if not road_ctx_pkg.begin_request('ADMIN', c_issuer) then fail('establish'); end if;
    l_res := demo_todo_api.purge(json('{"before":"2999-01-01T00:00:00.000+00:00"}'));

    select count(*) into l_count from demo_todos where todo_id in (l_done_a, l_done_b);
    assert_eq('both owners'' finished todos purged', '0', to_char(l_count));

    select count(*) into l_count from demo_todos where todo_id = l_open;
    assert_eq('an OPEN todo is untouched', '1', to_char(l_count));
  end test_purge_crosses_owners_and_spares_open;

  ---------------------------------------------------------------------------

  procedure run_all is
    procedure exec(p_name in varchar2) is
    begin
      savepoint sp_demo;
      case p_name
        when 'other_owner_not_found'   then test_other_owners_todo_is_not_found;
        when 'list_all_not_list'       then test_list_all_does_not_imply_list;
        when 'own_owner_ok'            then test_own_owner_param_is_not_escalation;
        when 'other_owner_needs_all'   then test_listing_another_owner_requires_list_all;
        when 'owner_from_session'      then test_create_takes_owner_from_session;
        when 'owner_body_refused'      then test_owner_ignores_request_body;
        when 'stale_token_conflicts'   then test_stale_read_token_conflicts;
        when 'fresh_token_updates'     then test_fresh_read_token_updates;
        when 'update_needs_token'      then test_update_requires_read_token;
        when 'update_not_deleted'      then test_update_cannot_set_deleted;
        when 'delete_soft_idempotent'  then test_delete_is_soft_and_idempotent;
        when 'deleted_hidden'          then test_deleted_excluded_from_default_list;
        when 'purge_needs_permission'  then test_purge_denied_without_permission;
        when 'purge_cross_owner'       then test_purge_crosses_owners_and_spares_open;
        else fail('unknown test ' || p_name);
      end case;
      dbms_output.put_line('PASS ' || p_name);
      l_pass := l_pass + 1;
      rollback to sp_demo;
      road_ctx_pkg.end_request;
    exception
      when others then
        dbms_output.put_line('FAIL ' || p_name || ': ' || sqlerrm);
        l_fail := l_fail + 1;
        rollback to sp_demo;
        road_ctx_pkg.end_request;
    end exec;
  begin
    l_pass := 0;
    l_fail := 0;
    setup;

    exec('other_owner_not_found');
    exec('list_all_not_list');
    exec('own_owner_ok');
    exec('other_owner_needs_all');
    exec('owner_from_session');
    exec('owner_body_refused');
    exec('stale_token_conflicts');
    exec('fresh_token_updates');
    exec('update_needs_token');
    exec('update_not_deleted');
    exec('delete_soft_idempotent');
    exec('deleted_hidden');
    exec('purge_needs_permission');
    exec('purge_cross_owner');

    teardown;
    dbms_output.put_line('demo_todo_api_test: ' || l_pass || ' passed, ' || l_fail || ' failed');
    if l_fail > 0 then
      raise_application_error(-20000, l_fail || ' demo_todo_api test(s) failed');
    end if;
  exception
    when others then
      teardown;
      raise;
  end run_all;

end demo_todo_api_test;
/
