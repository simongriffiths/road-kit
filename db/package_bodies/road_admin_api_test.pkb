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
    l_sys number;
    l_usr number;
    l_tgt number;
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

    l_sys := principal_of('SYSADM');
    l_usr := principal_of('USRADM');

    insert into road_principal_roles (principal_id, role_name)
    select l_sys, 'road.system_admin' from dual
     where not exists (select 1 from road_principal_roles
                        where principal_id = l_sys and role_name = 'road.system_admin');
    insert into road_principal_roles (principal_id, role_name)
    select l_usr, 'road.user_admin' from dual
     where not exists (select 1 from road_principal_roles
                        where principal_id = l_usr and role_name = 'road.user_admin');
    commit;
  end setup;

  procedure teardown is
  begin
    delete from road_principal_roles
     where principal_id in (select principal_id from road_principals where issuer = c_issuer);
    delete from road_principals where issuer = c_issuer;
    delete from road_role_permissions
     where role_name in ('test.ordinary', 'test.definedrole', 'test.grantedby', 'test.idem');
    delete from road_roles
     where role_name in ('test.ordinary', 'test.definedrole', 'test.grantedby', 'test.idem');
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

    select count(*) into l_before
      from road_role_permissions
     where role_name = 'test.ordinary' and permission_name like 'test.appperm%';
    assert_eq('both app permissions granted', '2', to_char(l_before));

    -- No road.* permission may be picked up by the blanket grant.
    select count(*) into l_after
      from road_role_permissions
     where role_name = 'test.ordinary' and permission_name like 'road.%';
    assert_eq('no framework permissions granted', '0', to_char(l_after));

    -- A permission added AFTERWARDS must not be acquired -- that is rule 4, and the reason this is
    -- a deploy-time write rather than a runtime wildcard.
    insert into road_permissions (permission_name, description)
    values ('test.appperm.three', 'added after the blanket grant');
    select count(*) into l_after
      from road_role_permissions
     where role_name = 'test.ordinary' and permission_name = 'test.appperm.three';
    assert_eq('later permission NOT silently acquired', '0', to_char(l_after));
  end test_grant_all_app_permissions_is_explicit;

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
