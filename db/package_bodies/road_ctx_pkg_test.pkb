create or replace package body road_ctx_pkg_test as

  -- Fail-closed tests for road_ctx_pkg. Build plan 06 phase 2.3 -- "the ones the design rests on".
  --
  -- The pooled-session test is written first because it is the highest risk in the whole patch
  -- (risk 10.1): ORDS reuses connections, so a session genuinely does carry the previous caller's
  -- state. Confirmed on dev during phase 0.1 -- PROXY_USER is ORDS_PUBLIC_USER over a shared
  -- service. If context survived between requests, road_ctx_pkg.principal_id would return the wrong
  -- principal, and concurrency-only bugs reach production.

  c_issuer constant varchar2(64) := 'urn:road:test:road_ctx';

  procedure fail(p_message in varchar2) is
  begin
    raise_application_error(-20000, p_message);
  end fail;

  procedure assert_true(p_label in varchar2, p_actual in boolean) is
  begin
    if not nvl(p_actual, false) then
      fail(p_label || ': expected TRUE, got ' ||
           case when p_actual is null then 'NULL' else 'FALSE' end);
    end if;
  end assert_true;

  procedure assert_false(p_label in varchar2, p_actual in boolean) is
  begin
    -- Note "not false" is not the same as "null" here: rule 3 requires false, never null.
    if nvl(p_actual, true) then
      fail(p_label || ': expected FALSE, got ' ||
           case when p_actual is null then 'NULL' else 'TRUE' end);
    end if;
  end assert_false;

  procedure assert_null(p_label in varchar2, p_actual in varchar2) is
  begin
    if p_actual is not null then
      fail(p_label || ': expected NULL, got [' || p_actual || ']');
    end if;
  end assert_null;

  function principal_of(p_subject in varchar2) return number is
    l_id number;
  begin
    select principal_id into l_id
      from road_principals
     where issuer = c_issuer and subject = p_subject;
    return l_id;
  end principal_of;

  procedure setup is
    l_a    number;
    l_b    number;
    l_susp number;
  begin
    -- Autonomous Database enables parallel DML by default, and every insert below reads the table
    -- it writes (the NOT EXISTS guard). Once serial DML has happened in the transaction a parallel
    -- one raises ORA-12839, which then surfaces as a deadlock in teardown. Same reason
    -- deploy/create/95_data.sql disables it.
    execute immediate 'alter session disable parallel dml';

    -- Two roles sharing one permission, so the union case has something to collapse.
    insert into road_permissions (permission_name, description)
    select 'test.perm.a', 'road_ctx test fixture' from dual
     where not exists (select 1 from road_permissions where permission_name = 'test.perm.a');
    insert into road_permissions (permission_name, description)
    select 'test.perm.b', 'road_ctx test fixture' from dual
     where not exists (select 1 from road_permissions where permission_name = 'test.perm.b');
    insert into road_permissions (permission_name, description)
    select 'test.perm.shared', 'road_ctx test fixture' from dual
     where not exists (select 1 from road_permissions where permission_name = 'test.perm.shared');

    insert into road_roles (role_name, display_name, is_reserved)
    select 'test.role1', 'road_ctx test fixture', 'N' from dual
     where not exists (select 1 from road_roles where role_name = 'test.role1');
    insert into road_roles (role_name, display_name, is_reserved)
    select 'test.role2', 'road_ctx test fixture', 'N' from dual
     where not exists (select 1 from road_roles where role_name = 'test.role2');

    insert into road_role_permissions (role_name, permission_name)
    select 'test.role1', 'test.perm.a' from dual
     where not exists (select 1 from road_role_permissions
                        where role_name = 'test.role1' and permission_name = 'test.perm.a');
    insert into road_role_permissions (role_name, permission_name)
    select 'test.role1', 'test.perm.shared' from dual
     where not exists (select 1 from road_role_permissions
                        where role_name = 'test.role1' and permission_name = 'test.perm.shared');
    insert into road_role_permissions (role_name, permission_name)
    select 'test.role2', 'test.perm.b' from dual
     where not exists (select 1 from road_role_permissions
                        where role_name = 'test.role2' and permission_name = 'test.perm.b');
    insert into road_role_permissions (role_name, permission_name)
    select 'test.role2', 'test.perm.shared' from dual
     where not exists (select 1 from road_role_permissions
                        where role_name = 'test.role2' and permission_name = 'test.perm.shared');

    -- TESTA holds both roles, TESTB only the first, TESTSUSP is suspended.
    insert into road_principals (issuer, subject, display_name, status)
    select c_issuer, 'TESTA', 'road_ctx test fixture', 'ACTIVE' from dual
     where not exists (select 1 from road_principals where issuer = c_issuer and subject = 'TESTA');
    insert into road_principals (issuer, subject, display_name, status)
    select c_issuer, 'TESTB', 'road_ctx test fixture', 'ACTIVE' from dual
     where not exists (select 1 from road_principals where issuer = c_issuer and subject = 'TESTB');
    insert into road_principals (issuer, subject, display_name, status)
    select c_issuer, 'TESTSUSP', 'road_ctx test fixture', 'SUSPENDED' from dual
     where not exists (select 1 from road_principals where issuer = c_issuer and subject = 'TESTSUSP');

    -- Resolved into locals first: principal_of is body-private, and a private packaged function
    -- cannot be referenced from inside SQL (PLS-00231).
    l_a := principal_of('TESTA');
    l_b := principal_of('TESTB');
    l_susp := principal_of('TESTSUSP');

    insert into road_principal_roles (principal_id, role_name)
    select l_a, 'test.role1' from dual
     where not exists (select 1 from road_principal_roles
                        where principal_id = l_a and role_name = 'test.role1');
    insert into road_principal_roles (principal_id, role_name)
    select l_a, 'test.role2' from dual
     where not exists (select 1 from road_principal_roles
                        where principal_id = l_a and role_name = 'test.role2');
    insert into road_principal_roles (principal_id, role_name)
    select l_b, 'test.role1' from dual
     where not exists (select 1 from road_principal_roles
                        where principal_id = l_b and role_name = 'test.role1');
    insert into road_principal_roles (principal_id, role_name)
    select l_susp, 'test.role1' from dual
     where not exists (select 1 from road_principal_roles
                        where principal_id = l_susp and role_name = 'test.role1');

    commit;
  end setup;

  procedure teardown is
  begin
    delete from road_principal_roles
     where principal_id in (select principal_id from road_principals
                             where issuer like 'urn:road:test:%');
    -- Covers NEWCOMER, STRANGER and anything auto-provisioned under a second test issuer.
    delete from road_principals where issuer like 'urn:road:test:%';
    delete from road_role_permissions where role_name in ('test.role1', 'test.role2');
    delete from road_roles where role_name in ('test.role1', 'test.role2');
    delete from road_permissions
     where permission_name in ('test.perm.a', 'test.perm.b', 'test.perm.shared');
    commit;
    road_ctx_pkg.end_request;
  end teardown;

  -- THE test. B must never see A's permissions on a reused session.
  procedure test_pooled_session_does_not_bleed is
  begin
    assert_true('A establishes', road_ctx_pkg.begin_request('TESTA', c_issuer));
    assert_true('A has perm.b', road_ctx_pkg.has_permission('test.perm.b'));
    assert_true('A has role2', road_ctx_pkg.has_role('test.role2'));

    -- Same session, no end_request in between -- exactly what a pooled connection does.
    assert_true('B establishes', road_ctx_pkg.begin_request('TESTB', c_issuer));
    assert_false('B must NOT inherit A perm.b', road_ctx_pkg.has_permission('test.perm.b'));
    assert_false('B must NOT inherit A role2', road_ctx_pkg.has_role('test.role2'));
    assert_true('B keeps its own perm.a', road_ctx_pkg.has_permission('test.perm.a'));

    if road_ctx_pkg.principal_id != principal_of('TESTB') then
      fail('principal_id must be B, got ' || road_ctx_pkg.principal_id);
    end if;
  end test_pooled_session_does_not_bleed;

  -- A FAILED begin_request must also clear the previous caller, not leave them established.
  --
  -- The failure used to be an unknown subject. With auto-provisioning enabled that is no longer a
  -- failure -- it creates the principal -- so this uses a SUSPENDED one, which also exercises a
  -- later exit point: past the lookup, with identity partially resolved.
  procedure test_failed_begin_clears_previous is
  begin
    assert_true('A establishes', road_ctx_pkg.begin_request('TESTA', c_issuer));
    assert_false('suspended principal denied', road_ctx_pkg.begin_request('TESTSUSP', c_issuer));
    assert_false('previous identity gone', road_ctx_pkg.is_authenticated);
    assert_false('previous permission gone', road_ctx_pkg.has_permission('test.perm.a'));
    assert_null('principal_id cleared', to_char(road_ctx_pkg.principal_id));

    -- A null subject fails earliest of all, and must also leave nothing behind.
    assert_true('A re-establishes', road_ctx_pkg.begin_request('TESTA', c_issuer));
    assert_false('null subject denied', road_ctx_pkg.begin_request(null, c_issuer));
    assert_false('and cleared', road_ctx_pkg.is_authenticated);
  end test_failed_begin_clears_previous;

  procedure test_unestablished_denies_everything is
  begin
    road_ctx_pkg.end_request;
    assert_false('is_authenticated', road_ctx_pkg.is_authenticated);
    assert_false('has_permission', road_ctx_pkg.has_permission('test.perm.a'));
    assert_false('has_role', road_ctx_pkg.has_role('test.role1'));
    assert_null('principal_id', to_char(road_ctx_pkg.principal_id));
    assert_null('subject', road_ctx_pkg.subject);
    assert_null('issuer', road_ctx_pkg.issuer);
    -- Null arguments must deny too, not error.
    assert_false('null permission', road_ctx_pkg.has_permission(null));
    assert_false('null role', road_ctx_pkg.has_role(null));
  end test_unestablished_denies_everything;

  procedure test_suspended_principal_denied is
  begin
    assert_false('suspended denied', road_ctx_pkg.begin_request('TESTSUSP', c_issuer));
    assert_false('context not established', road_ctx_pkg.is_authenticated);
    assert_false('no permissions loaded', road_ctx_pkg.has_permission('test.perm.a'));
  end test_suspended_principal_denied;

  -- Same subject, different issuer: the whole reason section 4.1 keys on both.
  --
  -- With auto-provisioning on, the property under test is no longer "denied" -- a subject from
  -- another issuer is a legitimate new person, and gets their own principal. What must NEVER happen
  -- is that they resolve to the EXISTING principal and inherit its permissions. That is precisely
  -- the collision section 4.1 exists to prevent: two issuers may both legitimately mint 'TESTA'.
  procedure test_wrong_issuer_is_a_different_principal is
    l_other constant varchar2(64) := 'urn:road:test:somewhere-else';
    l_mine  number;
    l_other_id number;
  begin
    assert_true('A establishes under its own issuer', road_ctx_pkg.begin_request('TESTA', c_issuer));
    l_mine := road_ctx_pkg.principal_id;
    assert_true('and holds its permission', road_ctx_pkg.has_permission('test.perm.a'));

    -- Created explicitly rather than relying on auto-provisioning: this test is about issuer
    -- isolation, and must pass whether or not the deployment provisions on first sight. road-kit
    -- defaults auto_provision_principals to N, and the earlier version of this test failed there --
    -- caught by the phase 8 backport running the suite rather than reading it.
    insert into road_principals (issuer, subject, display_name, status)
    select l_other, 'TESTA', 'road_ctx test fixture (other issuer)', 'ACTIVE' from dual
     where not exists (select 1 from road_principals
                        where issuer = l_other and subject = 'TESTA');
    commit;

    assert_true('same subject under another issuer establishes separately',
                road_ctx_pkg.begin_request('TESTA', l_other));
    l_other_id := road_ctx_pkg.principal_id;

    if l_mine = l_other_id then
      fail('same subject from a different issuer resolved to the SAME principal');
    end if;
    assert_false('and must NOT inherit the other issuer''s permissions',
                 road_ctx_pkg.has_permission('test.perm.a'));
  end test_wrong_issuer_is_a_different_principal;

  procedure test_permission_union_no_duplicates is
    l_expected number;
    l_a        number;
  begin
    l_a := principal_of('TESTA');
    assert_true('A establishes', road_ctx_pkg.begin_request('TESTA', c_issuer));
    assert_true('perm.a from role1', road_ctx_pkg.has_permission('test.perm.a'));
    assert_true('perm.b from role2', road_ctx_pkg.has_permission('test.perm.b'));
    assert_true('perm.shared from both', road_ctx_pkg.has_permission('test.perm.shared'));

    -- The union really is three distinct permissions, not four rows collapsed by luck.
    select count(distinct rp.permission_name)
      into l_expected
      from road_principal_roles pr
      join road_role_permissions rp on rp.role_name = pr.role_name
     where pr.principal_id = l_a;
    if l_expected != 3 then
      fail('fixture wrong: expected 3 distinct permissions, got ' || l_expected);
    end if;

    assert_false('unheld permission still denied', road_ctx_pkg.has_permission('road.role.define'));
  end test_permission_union_no_duplicates;

  procedure test_require_permission_raises_403 is
    l_raised boolean := false;
  begin
    assert_true('B establishes', road_ctx_pkg.begin_request('TESTB', c_issuer));

    -- Held: must not raise.
    road_ctx_pkg.require_permission('test.perm.a');

    -- Not held: must raise the dedicated forbidden code, which error_api maps to 403.
    begin
      road_ctx_pkg.require_permission('test.perm.b');
    exception
      when others then
        l_raised := true;
        if sqlcode != road_ctx_pkg.c_forbidden then
          fail('expected ' || road_ctx_pkg.c_forbidden || ', got ' || sqlcode);
        end if;
    end;
    assert_true('require_permission raised', l_raised);

    l_raised := false;
    begin
      road_ctx_pkg.require_role('test.role2');
    exception
      when others then
        l_raised := true;
        if sqlcode != road_ctx_pkg.c_forbidden then
          fail('expected ' || road_ctx_pkg.c_forbidden || ', got ' || sqlcode);
        end if;
    end;
    assert_true('require_role raised', l_raised);
  end test_require_permission_raises_403;

  -- require_* on an UNESTABLISHED session must deny, not pass. The dangerous failure would be a
  -- handler that forgot begin_request sailing through its permission check.
  procedure test_require_denies_when_unestablished is
    l_raised boolean := false;
  begin
    road_ctx_pkg.end_request;
    begin
      road_ctx_pkg.require_permission('test.perm.a');
    exception
      when others then
        l_raised := true;
    end;
    assert_true('require_permission denied with no session', l_raised);
  end test_require_denies_when_unestablished;

  -- p_issuer defaulted: resolved from the schema's ORDS JWT profile. Uses the seeded bootstrap
  -- principal, which is the only one that exists under the real issuer.
  procedure test_default_issuer_resolution is
    l_subject road_config.config_value%type;
  begin
    select config_value into l_subject
      from road_config where config_key = 'bootstrap_admin_subject';

    assert_true('bootstrap principal establishes with defaulted issuer',
                road_ctx_pkg.begin_request(l_subject));
    assert_true('and holds road.role.define', road_ctx_pkg.has_permission('road.role.define'));

    -- The resolved issuer must equal the JWT profile's, not a guess.
    for r in (select issuer from user_ords_jwt_profile) loop
      if road_ctx_pkg.issuer != r.issuer then
        fail('issuer mismatch: context [' || road_ctx_pkg.issuer || '] profile [' || r.issuer || ']');
      end if;
    end loop;
  end test_default_issuer_resolution;

  -- The USING clause is the security control. Prove it: this package is not road_ctx_pkg, so it
  -- must not be able to write the namespace. Without this, "secured context" is an unverified
  -- claim and any handler could grant itself permissions.
  procedure test_context_is_not_writable_by_others is
    l_raised boolean := false;
  begin
    -- Start from a genuinely cleared session, otherwise the second assertion would just be
    -- observing the previous test's establishment rather than this one's failure to establish.
    road_ctx_pkg.end_request;
    begin
      dbms_session.set_context(road_ctx_pkg.namespace, 'ESTABLISHED', 'Y');
    exception
      when others then
        l_raised := true;
    end;
    assert_true('non-trusted package must not write the namespace', l_raised);
    assert_false('and identity must not be established', road_ctx_pkg.is_authenticated);
  end test_context_is_not_writable_by_others;

  -- Auto-provisioning: a subject the issuer authenticated but this application has never seen.
  procedure test_auto_provision_creates_principal is
    l_before number;
    l_after  number;
    l_role   road_config.config_value%type;
    l_saved  road_config.config_value%type;
  begin
    select config_value into l_role from road_config where config_key = 'default_principal_role';

    -- Enabled for the duration and restored afterwards. road-cal ships this on and road-kit ships
    -- it off, so a test that assumed either would fail in the other repo.
    select config_value into l_saved
      from road_config where config_key = 'auto_provision_principals';
    update road_config set config_value = 'Y' where config_key = 'auto_provision_principals';
    commit;

    delete from road_principal_roles
     where principal_id in (select principal_id from road_principals
                             where issuer = c_issuer and subject = 'NEWCOMER');
    delete from road_principals where issuer = c_issuer and subject = 'NEWCOMER';
    commit;

    select count(*) into l_before
      from road_principals where issuer = c_issuer and subject = 'NEWCOMER';
    assert_true('fixture starts absent', l_before = 0);

    assert_true('unknown subject is provisioned and establishes',
                road_ctx_pkg.begin_request('NEWCOMER', c_issuer));

    select count(*) into l_after
      from road_principals where issuer = c_issuer and subject = 'NEWCOMER';
    assert_true('principal row created', l_after = 1);
    assert_true('holds the default role', road_ctx_pkg.has_role(l_role));

    -- Second visit must reuse the row, not create another.
    assert_true('second request establishes', road_ctx_pkg.begin_request('NEWCOMER', c_issuer));
    select count(*) into l_after
      from road_principals where issuer = c_issuer and subject = 'NEWCOMER';
    assert_true('still exactly one principal', l_after = 1);

    update road_config set config_value = l_saved where config_key = 'auto_provision_principals';
    commit;
  exception
    when others then
      update road_config set config_value = l_saved where config_key = 'auto_provision_principals';
      commit;
      raise;
  end test_auto_provision_creates_principal;

  -- With provisioning off, an unknown subject must be denied -- rule 3's default.
  procedure test_auto_provision_off_denies is
    l_saved road_config.config_value%type;
  begin
    select config_value into l_saved
      from road_config where config_key = 'auto_provision_principals';

    update road_config set config_value = 'N' where config_key = 'auto_provision_principals';
    commit;

    begin
      assert_false('unknown subject denied when provisioning is off',
                   road_ctx_pkg.begin_request('STRANGER', c_issuer));
      assert_false('context not established', road_ctx_pkg.is_authenticated);

      declare
        l_count number;
      begin
        select count(*) into l_count
          from road_principals where issuer = c_issuer and subject = 'STRANGER';
        assert_true('no principal created', l_count = 0);
      end;
    exception
      when others then
        update road_config set config_value = l_saved
         where config_key = 'auto_provision_principals';
        commit;
        raise;
    end;

    update road_config set config_value = l_saved where config_key = 'auto_provision_principals';
    commit;
  end test_auto_provision_off_denies;

  -- A SUSPENDED principal must stay denied even with provisioning on: it is a known subject, so
  -- provisioning never runs, and the status check is what holds. Getting this wrong would let a
  -- suspended user be silently re-provisioned as active.
  procedure test_suspended_is_not_reprovisioned is
    l_count number;
  begin
    assert_false('suspended still denied', road_ctx_pkg.begin_request('TESTSUSP', c_issuer));
    select count(*) into l_count
      from road_principals where issuer = c_issuer and subject = 'TESTSUSP';
    assert_true('still exactly one TESTSUSP row', l_count = 1);
    assert_false('context not established', road_ctx_pkg.is_authenticated);
  end test_suspended_is_not_reprovisioned;

  procedure run_all is
  begin
    setup;

    test_pooled_session_does_not_bleed;
    test_failed_begin_clears_previous;
    test_unestablished_denies_everything;
    test_suspended_principal_denied;
    test_wrong_issuer_is_a_different_principal;
    test_permission_union_no_duplicates;
    test_require_permission_raises_403;
    test_require_denies_when_unestablished;
    test_default_issuer_resolution;
    test_context_is_not_writable_by_others;
    test_auto_provision_creates_principal;
    test_suspended_is_not_reprovisioned;
    test_auto_provision_off_denies;

    teardown;
    dbms_output.put_line('[PASS] road_ctx_pkg_test: 13 tests');
  exception
    when others then
      teardown;
      raise;
  end run_all;

end road_ctx_pkg_test;
/
