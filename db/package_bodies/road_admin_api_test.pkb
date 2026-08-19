create or replace package body road_admin_api_test as

  -- The two tests that carry this phase are test_user_admin_cannot_grant_reserved and
  -- test_granted_by_ignores_request_body. Everything else is ordinary coverage.

  c_issuer constant varchar2(64) := 'urn:road:test:road_admin';

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
    l_sys    number;
    l_usr    number;
    l_tgt    number;
    l_target number;
  begin
    execute immediate 'alter session disable parallel dml';

    insert into road_principals (issuer, subject, display_name, status)
    select c_issuer, 'SYSADM', 'road_admin test fixture', 'ACTIVE' from dual
     where not exists (select 1 from road_principals where issuer = c_issuer and subject = 'SYSADM');
    insert into road_principals (issuer, subject, display_name, status)
    select c_issuer, 'USRADM', 'road_admin test fixture', 'ACTIVE' from dual
     where not exists (select 1 from road_principals where issuer = c_issuer and subject = 'USRADM');
    insert into road_principals (issuer, subject, display_name, status)
    select c_issuer, 'TARGET', 'road_admin test fixture', 'ACTIVE' from dual
     where not exists (select 1 from road_principals where issuer = c_issuer and subject = 'TARGET');

    -- Distinctive name and address, so the get_principals search tests can assert an exact count
    -- against a database that also holds the real seeded principals.
    insert into road_principals (issuer, subject, display_name, email, status)
    select c_issuer, 'SEARCHME', 'Searchable Fixture', 'find.me@example.test', 'ACTIVE' from dual
     where not exists (select 1 from road_principals
                        where issuer = c_issuer and subject = 'SEARCHME');

    -- One role per grant test. Sharing a single role made two tests pass or fail depending on
    -- which ran first: whoever granted it first owned granted_by, and every later grant was a
    -- correct no-op that read as a failure.
    insert into road_roles (role_name, display_name, is_reserved)
    select 'test.ordinary', 'road_admin test fixture', 'N' from dual
     where not exists (select 1 from road_roles where role_name = 'test.ordinary');
    insert into road_roles (role_name, display_name, is_reserved)
    select 'test.grantedby', 'road_admin test fixture', 'N' from dual
     where not exists (select 1 from road_roles where role_name = 'test.grantedby');
    insert into road_roles (role_name, display_name, is_reserved)
    select 'test.idem', 'road_admin test fixture', 'N' from dual
     where not exists (select 1 from road_roles where role_name = 'test.idem');

    -- Two APPLICATION permission fixtures, one reserved and one not. Neither starts with road.,
    -- which is the whole point: spec-patch-07 section 3.1's rule is that reserved-ness is read
    -- from the column and never inferred from the name, and only an application permission can
    -- exercise it.
    --
    -- Seeded by this suite rather than borrowed from the adopting application's own data, so the
    -- file stays byte-identical across repos. It did borrow, until 2026-08-19: it named
    -- events.purge and session.read, which are road-cal's, and the two composition tests below
    -- therefore failed with ORA-20004 the first time this suite ran in road-kit. A framework test
    -- suite must not depend on any particular adopter existing.
    insert into road_permissions (permission_name, description, is_reserved)
    select 'test.appperm.reserved', 'road_admin test fixture, reserved', 'Y' from dual
     where not exists (select 1 from road_permissions
                        where permission_name = 'test.appperm.reserved');
    insert into road_permissions (permission_name, description, is_reserved)
    select 'test.appperm.plain', 'road_admin test fixture, unreserved', 'N' from dual
     where not exists (select 1 from road_permissions
                        where permission_name = 'test.appperm.plain');
    insert into road_roles (role_name, display_name, is_reserved)
    select 'test.searchable', 'road_admin test fixture', 'N' from dual
     where not exists (select 1 from road_roles where role_name = 'test.searchable');
    -- Dedicated to test_composition_takes_effect_on_next_request -- NOT test.ordinary, which
    -- test_grant_all_app_permissions_is_explicit blanket-attaches every application permission to
    -- (deploy-attached), and which test_user_admin_cannot_grant_reserved's own grant_role call
    -- assumes TARGET does not already hold.
    insert into road_roles (role_name, display_name, is_reserved)
    select 'test.composetarget', 'road_admin test fixture', 'N' from dual
     where not exists (select 1 from road_roles where role_name = 'test.composetarget');

    l_sys := principal_of('SYSADM');
    l_usr := principal_of('USRADM');
    l_tgt := principal_of('SEARCHME');

    insert into road_principal_roles (principal_id, role_name)
    select l_tgt, 'test.searchable' from dual
     where not exists (select 1 from road_principal_roles
                        where principal_id = l_tgt and role_name = 'test.searchable');

    insert into road_principal_roles (principal_id, role_name)
    select l_sys, 'road.system_admin' from dual
     where not exists (select 1 from road_principal_roles
                        where principal_id = l_sys and role_name = 'road.system_admin');
    insert into road_principal_roles (principal_id, role_name)
    select l_usr, 'road.user_admin' from dual
     where not exists (select 1 from road_principal_roles
                        where principal_id = l_usr and role_name = 'road.user_admin');

    -- TARGET holds test.composetarget directly (not via another test's side effect), so
    -- test_composition_takes_effect_on_next_request stays correct regardless of run order.
    l_target := principal_of('TARGET');
    insert into road_principal_roles (principal_id, role_name)
    select l_target, 'test.composetarget' from dual
     where not exists (select 1 from road_principal_roles
                        where principal_id = l_target and role_name = 'test.composetarget');
    commit;
  end setup;

  procedure teardown is
  begin
    -- road_role_permissions BEFORE road_principals: spec-patch-07 added ATTACHED_BY, a nullable FK
    -- to road_principals, and the composition tests below leave rows attached_by one of this
    -- fixture's own principals (SYSADM). Deleting road_principals first would raise ORA-02292
    -- (child record found) against those rows.
    delete from road_role_permissions
     where role_name in ('test.ordinary', 'test.definedrole', 'test.grantedby', 'test.idem',
                         'test.searchable', 'test.composetarget');
    delete from road_principal_roles
     where principal_id in (select principal_id from road_principals where issuer = c_issuer);
    delete from road_principals where issuer = c_issuer;
    delete from road_roles
     where role_name in ('test.ordinary', 'test.definedrole', 'test.grantedby', 'test.idem',
                         'test.searchable', 'test.composetarget');
    delete from road_permissions where permission_name like 'test.appperm%';
    commit;
    road_ctx_pkg.end_request;
  end teardown;

  -- THE test for this phase. Nothing in the table structure prevents it, so if this check is ever
  -- removed the model silently collapses to one tier: any user_admin could promote themselves.
  procedure test_user_admin_cannot_grant_reserved is
    l_res    json;
    l_raised boolean := false;
  begin
    if not road_ctx_pkg.begin_request('USRADM', c_issuer) then
      fail('USRADM should establish');
    end if;

    -- It CAN grant an ordinary role -- proving the denial below is about the role, not a blanket
    -- lack of permission.
    l_res := road_admin_api.grant_role(
               json('{"principal_id":' || principal_of('TARGET') || ',"role_name":"test.ordinary"}'));
    assert_eq('ordinary grant succeeded', 'true', json_value(l_res, '$.granted'));

    begin
      l_res := road_admin_api.grant_role(
                 json('{"principal_id":' || principal_of('TARGET')
                      || ',"role_name":"road.system_admin"}'));
    exception
      when others then
        l_raised := true;
        if sqlcode != road_ctx_pkg.c_forbidden then
          fail('expected forbidden, got ' || sqlcode || ': ' || sqlerrm);
        end if;
    end;

    if not l_raised then
      fail('a road.user_admin must NOT be able to grant road.system_admin');
    end if;

    -- And it must not have happened anyway.
    declare
      l_count  number;
      l_target number := principal_of('TARGET');  -- body-private, so not usable inside SQL
    begin
      select count(*) into l_count
        from road_principal_roles
       where principal_id = l_target and role_name = 'road.system_admin';
      assert_eq('no reserved grant written', '0', to_char(l_count));
    end;
  end test_user_admin_cannot_grant_reserved;

  procedure test_system_admin_can_grant_reserved is
    l_res json;
  begin
    if not road_ctx_pkg.begin_request('SYSADM', c_issuer) then
      fail('SYSADM should establish');
    end if;
    l_res := road_admin_api.grant_role(
               json('{"principal_id":' || principal_of('TARGET') || ',"role_name":"road.user_admin"}'));
    assert_eq('system_admin granted reserved role', 'true', json_value(l_res, '$.granted'));
  end test_system_admin_can_grant_reserved;

  -- granted_by must come from the session, not the caller. A caller who could nominate it could
  -- forge the record of who authorised an escalation.
  procedure test_granted_by_ignores_request_body is
    l_res    json;
    l_actual number;
    l_target number;
  begin
    if not road_ctx_pkg.begin_request('SYSADM', c_issuer) then
      fail('SYSADM should establish');
    end if;

    l_res := road_admin_api.grant_role(json(
      '{"principal_id":' || principal_of('TARGET')
      || ',"role_name":"test.grantedby","granted_by":999999}'));

    l_target := principal_of('TARGET');
    select granted_by into l_actual
      from road_principal_roles
     where principal_id = l_target and role_name = 'test.grantedby';

    if l_actual = 999999 then
      fail('granted_by was taken from the request body');
    end if;
    assert_eq('granted_by is the session principal', to_char(principal_of('SYSADM')), to_char(l_actual));
  end test_granted_by_ignores_request_body;

  procedure test_grant_is_idempotent is
    l_res json;
  begin
    if not road_ctx_pkg.begin_request('SYSADM', c_issuer) then fail('establish'); end if;
    l_res := road_admin_api.grant_role(
               json('{"principal_id":' || principal_of('TARGET') || ',"role_name":"test.idem"}'));
    assert_eq('first grant', 'true', json_value(l_res, '$.granted'));
    l_res := road_admin_api.grant_role(
               json('{"principal_id":' || principal_of('TARGET') || ',"role_name":"test.idem"}'));
    assert_eq('second grant is a no-op, not an error', 'false', json_value(l_res, '$.granted'));
  end test_grant_is_idempotent;

  procedure test_cannot_revoke_last_system_admin is
    l_raised boolean := false;
    l_res    json;
  begin
    if not road_ctx_pkg.begin_request('SYSADM', c_issuer) then fail('establish'); end if;

    -- The fixture SYSADM plus the seeded bootstrap admin means more than one holder exists, so
    -- revoke the fixture's own to get down to the last one, then prove the last is refused.
    l_res := road_admin_api.revoke_role(
               json('{"principal_id":' || principal_of('SYSADM')
                    || ',"role_name":"road.system_admin"}'));
    assert_eq('fixture admin revoked', 'true', json_value(l_res, '$.revoked'));

    -- Re-establish as the seeded bootstrap admin, now the only holder, and try to remove itself.
    road_ctx_pkg.end_request;
    declare
      l_subject road_config.config_value%type;
      l_boot    number;
    begin
      select config_value into l_subject
        from road_config where config_key = 'bootstrap_admin_subject';
      if not road_ctx_pkg.begin_request(l_subject) then fail('bootstrap admin should establish'); end if;
      select principal_id into l_boot
        from road_principals
       where subject = l_subject and issuer = road_ctx_pkg.issuer;

      begin
        l_res := road_admin_api.revoke_role(
                   json('{"principal_id":' || l_boot || ',"role_name":"road.system_admin"}'));
      exception
        when others then
          l_raised := true;
          if sqlcode != -20001 then
            fail('expected validation error, got ' || sqlcode || ': ' || sqlerrm);
          end if;
      end;
    end;

    if not l_raised then
      fail('revoking the last road.system_admin must be refused');
    end if;
  end test_cannot_revoke_last_system_admin;

  procedure test_define_role_rejects_road_namespace is
    l_raised boolean := false;
    l_res    json;
  begin
    if not road_ctx_pkg.begin_request('SYSADM', c_issuer) then fail('establish'); end if;

    l_res := road_admin_api.define_role(
               json('{"role_name":"test.definedrole","display_name":"Defined"}'));
    assert_eq('ordinary role defined', 'test.definedrole', json_value(l_res, '$.role_name'));

    begin
      l_res := road_admin_api.define_role(json('{"role_name":"road.sneaky"}'));
    exception
      when others then
        l_raised := true;
    end;
    if not l_raised then
      fail('the road. namespace must be refused');
    end if;
  end test_define_role_rejects_road_namespace;

  -- A user_admin holds road.role.grant but NOT road.role.define, so defining must 403.
  procedure test_user_admin_cannot_define_roles is
    l_raised boolean := false;
    l_res    json;
  begin
    if not road_ctx_pkg.begin_request('USRADM', c_issuer) then fail('establish'); end if;
    begin
      l_res := road_admin_api.define_role(json('{"role_name":"test.notallowed"}'));
    exception
      when others then
        l_raised := true;
        if sqlcode != road_ctx_pkg.c_forbidden then
          fail('expected forbidden, got ' || sqlcode);
        end if;
    end;
    if not l_raised then fail('user_admin must not define roles'); end if;
  end test_user_admin_cannot_define_roles;

  -- With no session at all, every operation must deny. This is the "handler forgot begin_request"
  -- case reaching the package directly.
  procedure test_unauthenticated_denied is
    l_raised boolean := false;
    l_res    json;
  begin
    road_ctx_pkg.end_request;
    begin
      l_res := road_admin_api.get_roles;
    exception
      when others then
        l_raised := true;
    end;
    if not l_raised then fail('get_roles must deny with no session'); end if;
  end test_unauthenticated_denied;

  procedure test_grant_all_app_permissions_is_explicit is
    l_before number;
    l_after  number;
  begin
    insert into road_permissions (permission_name, description)
    values ('test.appperm.one', 'road_admin test fixture');
    insert into road_permissions (permission_name, description)
    values ('test.appperm.two', 'road_admin test fixture');

    road_admin_api.grant_all_app_permissions('test.ordinary');

    -- three, not two: test.appperm.one and .two above, plus test.appperm.plain from setup.
    -- test.appperm.reserved is the one that must NOT appear -- see below.
    select count(*) into l_before
      from road_role_permissions
     where role_name = 'test.ordinary' and permission_name like 'test.appperm%';
    assert_eq('unreserved app permissions granted', '3', to_char(l_before));

    -- No road.* permission may be picked up by the blanket grant.
    select count(*) into l_after
      from road_role_permissions
     where role_name = 'test.ordinary' and permission_name like 'road.%';
    assert_eq('no framework permissions granted', '0', to_char(l_after));

    -- THE regression test for spec-patch-08 section 7.1. Until 2026-08-19 this procedure filtered
    -- on the road. prefix ALONE, so a RESERVED application permission -- events.purge in road-cal,
    -- todo.purge in the demo app, test.appperm.reserved here -- was handed to whatever role was
    -- named. That is the exact inference spec-patch-07 section 3.1 exists to forbid, in the package
    -- spec-patch-07 amended. road-cal hit the symptom, hand-listed its user grants in 95_data.sql
    -- to route around it, and left the cause shipping. This assertion is what stops it returning.
    select count(*) into l_after
      from road_role_permissions
     where role_name = 'test.ordinary' and permission_name = 'test.appperm.reserved';
    assert_eq('RESERVED app permission NOT granted', '0', to_char(l_after));

    -- A permission added AFTERWARDS must not be acquired -- that is rule 4, and the reason this is
    -- a deploy-time write rather than a runtime wildcard.
    insert into road_permissions (permission_name, description)
    values ('test.appperm.three', 'added after the blanket grant');
    select count(*) into l_after
      from road_role_permissions
     where role_name = 'test.ordinary' and permission_name = 'test.appperm.three';
    assert_eq('later permission NOT silently acquired', '0', to_char(l_after));
  end test_grant_all_app_permissions_is_explicit;

  ---------------------------------------------------------------------------
  -- Role composition (spec-patch-07 section 7.1)
  ---------------------------------------------------------------------------

  -- THE escalation test for this patch. If this check is removed the two-tier model collapses
  -- silently: any road.role.compose holder could attach the framework's own reserved permissions
  -- to any role.
  procedure test_attach_reserved_permission_refused is
    l_raised boolean := false;
    l_res    json;
    l_count  number;
  begin
    if not road_ctx_pkg.begin_request('SYSADM', c_issuer) then fail('establish'); end if;

    begin
      -- test.idem, not test.ordinary: test_grant_all_app_permissions_is_explicit blanket-attaches
      -- every unreserved non-road.* permission to test.ordinary (deploy-attached), so a row-count
      -- check against it would be muddied by rows this test did not write.
      -- test.appperm.reserved is reserved and does not start with road. -- proving the guard reads
      -- the flag, not the name (spec-patch-07 section 3.1).
      l_res := road_admin_api.attach_permission(
                 json('{"role_name":"test.idem","permission_name":"test.appperm.reserved"}'));
    exception
      when others then
        l_raised := true;
        if sqlcode != road_ctx_pkg.c_forbidden then
          fail('expected forbidden, got ' || sqlcode || ': ' || sqlerrm);
        end if;
    end;
    if not l_raised then fail('attaching a reserved permission must be refused'); end if;

    select count(*) into l_count
      from road_role_permissions
     where role_name = 'test.idem' and permission_name = 'test.appperm.reserved';
    assert_eq('no row written', '0', to_char(l_count));
  end test_attach_reserved_permission_refused;

  -- A reserved ROLE's composition is framework-owned, even for an ordinary permission.
  procedure test_attach_to_reserved_role_refused is
    l_raised boolean := false;
    l_res    json;
    l_count  number;
  begin
    if not road_ctx_pkg.begin_request('SYSADM', c_issuer) then fail('establish'); end if;

    begin
      l_res := road_admin_api.attach_permission(
                 json('{"role_name":"road.user_admin","permission_name":"test.appperm.plain"}'));
    exception
      when others then
        l_raised := true;
        if sqlcode != road_ctx_pkg.c_forbidden then
          fail('expected forbidden, got ' || sqlcode || ': ' || sqlerrm);
        end if;
    end;
    if not l_raised then fail('attaching to a reserved role must be refused'); end if;

    select count(*) into l_count
      from road_role_permissions
     where role_name = 'road.user_admin' and permission_name = 'test.appperm.plain';
    assert_eq('no row written', '0', to_char(l_count));
  end test_attach_to_reserved_role_refused;

  -- THE test that proves spec-patch-07 section 1's claim end to end: composition is a data change,
  -- not a release. Nothing tested this before now, because until this phase nothing COULD.
  procedure test_composition_takes_effect_on_next_request is
    l_res json;
  begin
    insert into road_permissions (permission_name, description)
    values ('test.appperm.compose', 'road_admin test fixture');

    if not road_ctx_pkg.begin_request('SYSADM', c_issuer) then fail('establish'); end if;
    l_res := road_admin_api.attach_permission(
               json('{"role_name":"test.composetarget","permission_name":"test.appperm.compose"}'));
    assert_eq('attached', 'true', json_value(l_res, '$.attached'));

    -- TARGET holds test.composetarget (setup). Re-establishing loads effective permissions fresh
    -- from road_role_permissions -- no deploy, no new machinery.
    road_ctx_pkg.end_request;
    if not road_ctx_pkg.begin_request('TARGET', c_issuer) then fail('TARGET should establish'); end if;
    if not road_ctx_pkg.has_permission('test.appperm.compose') then
      fail('composition did not take effect on the next request');
    end if;
  end test_composition_takes_effect_on_next_request;

  -- attached_by must come from the session, not the caller -- same forgery reason granted_by is
  -- not read from the body on grant_role.
  procedure test_attached_by_ignores_request_body is
    l_res    json;
    l_actual number;
  begin
    insert into road_permissions (permission_name, description)
    values ('test.appperm.attachedby', 'road_admin test fixture');

    if not road_ctx_pkg.begin_request('SYSADM', c_issuer) then fail('establish'); end if;
    l_res := road_admin_api.attach_permission(json(
      '{"role_name":"test.ordinary","permission_name":"test.appperm.attachedby",'
      || '"attached_by":999999}'));
    assert_eq('attached', 'true', json_value(l_res, '$.attached'));

    select attached_by into l_actual
      from road_role_permissions
     where role_name = 'test.ordinary' and permission_name = 'test.appperm.attachedby';

    if l_actual = 999999 then
      fail('attached_by was taken from the request body');
    end if;
    assert_eq('attached_by is the session principal',
              to_char(principal_of('SYSADM')), to_char(l_actual));
  end test_attached_by_ignores_request_body;

  procedure test_attach_detach_idempotent is
    l_res json;
  begin
    insert into road_permissions (permission_name, description)
    values ('test.appperm.idem', 'road_admin test fixture');

    if not road_ctx_pkg.begin_request('SYSADM', c_issuer) then fail('establish'); end if;

    l_res := road_admin_api.attach_permission(
               json('{"role_name":"test.ordinary","permission_name":"test.appperm.idem"}'));
    assert_eq('first attach', 'true', json_value(l_res, '$.attached'));
    l_res := road_admin_api.attach_permission(
               json('{"role_name":"test.ordinary","permission_name":"test.appperm.idem"}'));
    assert_eq('second attach is a no-op, not an error', 'false', json_value(l_res, '$.attached'));

    l_res := road_admin_api.detach_permission(
               json('{"role_name":"test.ordinary","permission_name":"test.appperm.idem"}'));
    assert_eq('first detach', 'true', json_value(l_res, '$.detached'));
    l_res := road_admin_api.detach_permission(
               json('{"role_name":"test.ordinary","permission_name":"test.appperm.idem"}'));
    assert_eq('second detach is a no-op, not an error', 'false', json_value(l_res, '$.detached'));
  end test_attach_detach_idempotent;

  -- A road.user_admin holds neither road.role.compose. Denial must hold for both mutators.
  procedure test_compose_denied_without_permission is
    l_raised boolean := false;
    l_res    json;
  begin
    if not road_ctx_pkg.begin_request('USRADM', c_issuer) then fail('establish'); end if;

    begin
      l_res := road_admin_api.attach_permission(
                 json('{"role_name":"test.ordinary","permission_name":"session.read"}'));
    exception
      when others then
        l_raised := true;
        if sqlcode != road_ctx_pkg.c_forbidden then
          fail('expected forbidden, got ' || sqlcode);
        end if;
    end;
    if not l_raised then fail('attach_permission must deny without road.role.compose'); end if;

    l_raised := false;
    begin
      l_res := road_admin_api.detach_permission(
                 json('{"role_name":"test.ordinary","permission_name":"session.read"}'));
    exception
      when others then
        l_raised := true;
        if sqlcode != road_ctx_pkg.c_forbidden then
          fail('expected forbidden, got ' || sqlcode);
        end if;
    end;
    if not l_raised then fail('detach_permission must deny without road.role.compose'); end if;
  end test_compose_denied_without_permission;

  ---------------------------------------------------------------------------
  -- The composition guard assertions (spec-patch-07 section 5.2), proven directly against the
  -- real tables, bypassing road_admin_api entirely -- the point of an assertion over a package
  -- check is that it holds when the package does not run. Every insert here targets a
  -- (role, permission) pair not already in road_role_permissions, and every branch rolls back, so
  -- these leave no state behind for teardown to clean up.
  ---------------------------------------------------------------------------

  procedure test_assertion_permits_ordinary_session_attach is
    l_sys number := principal_of('SYSADM');
  begin
    insert into road_permissions (permission_name, description)
    values ('test.appperm.assertok', 'road_admin test fixture');
    insert into road_role_permissions (role_name, permission_name, attached_by)
    values ('test.idem', 'test.appperm.assertok', l_sys);
    rollback;
  exception
    when others then
      rollback;
      fail('ordinary permission, session-attached, must be permitted: ' || sqlerrm);
  end test_assertion_permits_ordinary_session_attach;

  procedure test_assertion_refuses_reserved_session_attach is
    l_sys    number := principal_of('SYSADM');
    l_raised boolean := false;
  begin
    begin
      insert into road_role_permissions (role_name, permission_name, attached_by)
      values ('test.grantedby', 'road.role.compose', l_sys);
      rollback;
    exception
      when others then
        rollback;
        l_raised := true;
        if sqlcode != -8601 then
          fail('expected ORA-08601, got ' || sqlcode || ': ' || sqlerrm);
        end if;
    end;
    if not l_raised then
      fail('reserved permission, session-attached, must be refused by road_reserved_composition');
    end if;
  end test_assertion_refuses_reserved_session_attach;

  -- The row that earns the assertion over a BEFORE INSERT trigger: the PARENT table
  -- (road_permissions) is what changes, not the child row being inserted.
  procedure test_assertion_refuses_flip_under_session_attach is
    l_sys    number := principal_of('SYSADM');
    l_raised boolean := false;
  begin
    begin
      insert into road_permissions (permission_name, description)
      values ('test.appperm.flip', 'road_admin test fixture');
      insert into road_role_permissions (role_name, permission_name, attached_by)
      values ('test.idem', 'test.appperm.flip', l_sys);

      update road_permissions set is_reserved = 'Y' where permission_name = 'test.appperm.flip';
      rollback;
    exception
      when others then
        rollback;
        l_raised := true;
        if sqlcode != -8601 then
          fail('expected ORA-08601, got ' || sqlcode || ': ' || sqlerrm);
        end if;
    end;
    if not l_raised then
      fail('flipping is_reserved under a session-attached row must be refused (the back door)');
    end if;
  end test_assertion_refuses_flip_under_session_attach;

  -- Proves the guard does not break the seed path: 95_data.sql and grant_all_app_permissions must
  -- still be able to attach a reserved permission with attached_by null.
  procedure test_assertion_permits_reserved_deploy_attach is
  begin
    insert into road_role_permissions (role_name, permission_name, attached_by)
    values ('test.grantedby', 'road.role.compose', null);
    rollback;
  exception
    when others then
      rollback;
      fail('reserved permission, deploy-attached (attached_by null), must be permitted: '
           || sqlerrm);
  end test_assertion_permits_reserved_deploy_attach;

  ---------------------------------------------------------------------------
  -- get_principals (ui-authorisation-design-v1.md section 5.2)
  ---------------------------------------------------------------------------

  -- The gate is road.role.grant, so a principal who holds neither admin role must be denied even
  -- though they are perfectly well authenticated. Without this the endpoint would be a directory of
  -- everyone's email address readable by every signed-in user.
  procedure test_get_principals_requires_permission is
    l_res    json;
    l_raised boolean := false;
  begin
    -- SEARCHME, not TARGET: TARGET has been granted road.user_admin by an earlier test in this
    -- run, so it would pass the gate and the assertion would prove nothing. SEARCHME holds one
    -- ordinary role with no permissions attached.
    if not road_ctx_pkg.begin_request('SEARCHME', c_issuer) then
      fail('SEARCHME should establish');
    end if;

    begin
      l_res := road_admin_api.get_principals(json('{}'));
    exception
      when others then
        l_raised := true;
        if sqlcode != road_ctx_pkg.c_forbidden then
          fail('expected c_forbidden, got ' || sqlcode);
        end if;
    end;
    if not l_raised then fail('get_principals must deny a principal without road.role.grant'); end if;

    -- And with no session at all, for the "handler forgot begin_request" path.
    road_ctx_pkg.end_request;
    l_raised := false;
    begin
      l_res := road_admin_api.get_principals(json('{}'));
    exception
      when others then
        l_raised := true;
    end;
    if not l_raised then fail('get_principals must deny with no session'); end if;
  end test_get_principals_requires_permission;

  procedure test_get_principals_search is
    l_res json;
  begin
    if not road_ctx_pkg.begin_request('USRADM', c_issuer) then
      fail('USRADM should establish');
    end if;

    -- Case-insensitive, and matching on display_name.
    l_res := road_admin_api.get_principals(json('{"q":"sEaRcHaBlE"}'));
    assert_eq('display_name match count', '1', json_value(l_res, '$.count'));
    assert_eq('display_name match subject', 'SEARCHME', json_value(l_res, '$.items[0].subject'));

    -- Matching on email, which is the column the screen exists to make usable.
    l_res := road_admin_api.get_principals(json('{"q":"find.me@example.test"}'));
    assert_eq('email match count', '1', json_value(l_res, '$.count'));
    assert_eq('email is returned', 'find.me@example.test', json_value(l_res, '$.items[0].email'));

    -- Matching on subject, for the case where a principal has neither name nor address yet.
    l_res := road_admin_api.get_principals(json('{"q":"SEARCHME"}'));
    assert_eq('subject match count', '1', json_value(l_res, '$.count'));

    -- The row carries its roles, so the table renders without a request per principal. Objects,
    -- not bare names (spec-patch-07 section 8.1) -- role_name and is_reserved both travel.
    assert_eq('roles travel with the row', 'test.searchable',
              json_value(l_res, '$.items[0].roles[0].role_name'));
    assert_eq('reserved-ness travels with the row', 'N',
              json_value(l_res, '$.items[0].roles[0].is_reserved'));

    -- A LIKE wildcard typed into the search box must be a literal. Unescaped, this matches every
    -- principal and the user believes they have searched.
    l_res := road_admin_api.get_principals(json('{"q":"%"}'));
    assert_eq('percent is a literal, not a wildcard', '0', json_value(l_res, '$.count'));

    -- A valid status filter narrows rather than empties.
    l_res := road_admin_api.get_principals(json('{"q":"searchable","status":"ACTIVE"}'));
    assert_eq('active filter keeps the row', '1', json_value(l_res, '$.count'));

    l_res := road_admin_api.get_principals(json('{"q":"searchable","status":"RETIRED"}'));
    assert_eq('retired filter excludes it', '0', json_value(l_res, '$.count'));

    -- An unrecognised status is refused rather than ignored: silently returning the unfiltered
    -- list would let the caller believe it had filtered.
    declare
      l_raised boolean := false;
    begin
      begin
        l_res := road_admin_api.get_principals(json('{"status":"BANNED"}'));
      exception
        when others then
          l_raised := true;
      end;
      if not l_raised then fail('an unrecognised status must be refused, not ignored'); end if;
    end;
  end test_get_principals_search;

  procedure test_get_principals_paging is
    l_res   json;
    l_first varchar2(255 char);
  begin
    if not road_ctx_pkg.begin_request('SYSADM', c_issuer) then
      fail('SYSADM should establish');
    end if;

    -- At least four principals exist by now (three fixtures plus the searchable one), so a page of
    -- one must report more to come.
    l_res := road_admin_api.get_principals(json('{"limit":1,"offset":0}'));
    assert_eq('one row on the page', '1', json_value(l_res, '$.count'));
    assert_eq('hasMore is true',   'true', json_value(l_res, '$.hasMore'));
    l_first := json_value(l_res, '$.items[0].subject');

    -- The second page must not repeat the first. Stable ordering is what a prev/next pager rests
    -- on; without it paging silently duplicates and skips rows.
    l_res := road_admin_api.get_principals(json('{"limit":1,"offset":1}'));
    if json_value(l_res, '$.items[0].subject') = l_first then
      fail('offset did not advance the page');
    end if;

    -- Clamped, not rejected: an out-of-range page size is a client bug, and an unclamped limit is
    -- a denial-of-service parameter.
    l_res := road_admin_api.get_principals(json('{"limit":9999}'));
    assert_eq('limit clamped to the maximum', '100', json_value(l_res, '$.limit'));

    l_res := road_admin_api.get_principals(json('{"limit":0}'));
    assert_eq('limit clamped to the minimum', '1', json_value(l_res, '$.limit'));

    l_res := road_admin_api.get_principals(json('{"offset":-5}'));
    assert_eq('negative offset clamped', '0', json_value(l_res, '$.offset'));

    -- Past the end is an empty page, not an error.
    l_res := road_admin_api.get_principals(json('{"offset":100000}'));
    assert_eq('past the end returns nothing', '0', json_value(l_res, '$.count'));
    assert_eq('past the end has no more',  'false', json_value(l_res, '$.hasMore'));
  end test_get_principals_paging;

  procedure run(p_name in varchar2, p_which in varchar2) is
  begin
    case p_which
      when 'user_admin_reserved'   then test_user_admin_cannot_grant_reserved;
      when 'sysadmin_reserved'     then test_system_admin_can_grant_reserved;
      when 'granted_by'            then test_granted_by_ignores_request_body;
      when 'idempotent'            then test_grant_is_idempotent;
      when 'last_admin'            then test_cannot_revoke_last_system_admin;
      when 'define_namespace'      then test_define_role_rejects_road_namespace;
      when 'user_admin_define'     then test_user_admin_cannot_define_roles;
      when 'unauthenticated'       then test_unauthenticated_denied;
      when 'grant_all'             then test_grant_all_app_permissions_is_explicit;
      when 'principals_permission' then test_get_principals_requires_permission;
      when 'principals_search'     then test_get_principals_search;
      when 'principals_paging'     then test_get_principals_paging;
      when 'attach_reserved_perm'  then test_attach_reserved_permission_refused;
      when 'attach_reserved_role'  then test_attach_to_reserved_role_refused;
      when 'compose_effect'        then test_composition_takes_effect_on_next_request;
      when 'attached_by'           then test_attached_by_ignores_request_body;
      when 'compose_idempotent'    then test_attach_detach_idempotent;
      when 'compose_denied'        then test_compose_denied_without_permission;
      when 'assert_permit_ord'     then test_assertion_permits_ordinary_session_attach;
      when 'assert_refuse_res'     then test_assertion_refuses_reserved_session_attach;
      when 'assert_refuse_flip'    then test_assertion_refuses_flip_under_session_attach;
      when 'assert_permit_deploy'  then test_assertion_permits_reserved_deploy_attach;
    end case;
    dbms_output.put_line('PASS ' || p_name);
    l_pass := l_pass + 1;
  exception
    when others then
      dbms_output.put_line('FAIL ' || p_name || ': ' || sqlerrm);
      l_fail := l_fail + 1;
  end run;

  procedure run_all is
  begin
    l_pass := 0;
    l_fail := 0;
    setup;

    run('test_user_admin_cannot_grant_reserved', 'user_admin_reserved');
    run('test_system_admin_can_grant_reserved', 'sysadmin_reserved');
    run('test_granted_by_ignores_request_body', 'granted_by');
    run('test_grant_is_idempotent', 'idempotent');
    run('test_define_role_rejects_road_namespace', 'define_namespace');
    run('test_user_admin_cannot_define_roles', 'user_admin_define');
    run('test_unauthenticated_denied', 'unauthenticated');
    run('test_grant_all_app_permissions_is_explicit', 'grant_all');
    run('test_get_principals_requires_permission', 'principals_permission');
    run('test_get_principals_search', 'principals_search');
    run('test_get_principals_paging', 'principals_paging');

    run('test_attach_reserved_permission_refused', 'attach_reserved_perm');
    run('test_attach_to_reserved_role_refused', 'attach_reserved_role');
    run('test_composition_takes_effect_on_next_request', 'compose_effect');
    run('test_attached_by_ignores_request_body', 'attached_by');
    run('test_attach_detach_idempotent', 'compose_idempotent');
    run('test_compose_denied_without_permission', 'compose_denied');
    run('test_assertion_permits_ordinary_session_attach', 'assert_permit_ord');
    run('test_assertion_refuses_reserved_session_attach', 'assert_refuse_res');
    run('test_assertion_refuses_flip_under_session_attach', 'assert_refuse_flip');
    run('test_assertion_permits_reserved_deploy_attach', 'assert_permit_deploy');

    -- Last: it deliberately revokes admin grants, so it must not run before the others.
    run('test_cannot_revoke_last_system_admin', 'last_admin');

    teardown;
    dbms_output.put_line('road_admin_api_test: ' || l_pass || ' passed, ' || l_fail || ' failed');
    if l_fail > 0 then
      raise_application_error(-20000, l_fail || ' road_admin_api test(s) failed');
    end if;
  exception
    when others then
      teardown;
      raise;
  end run_all;

end road_admin_api_test;
/
