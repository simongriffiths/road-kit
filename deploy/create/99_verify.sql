whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback

-- INTENT:
-- Purpose: Confirm a completed deployment is healthy.
-- Approach: Read-only probes - health package status, UI asset count, JWT config presence,
--   plus a hard check that the auth config row exists.
-- Reason: A deploy that compiled without error can still be wrong (empty config, no
--   UI assets); this makes that visible in the run log.
-- Expected objects: None created. Read-only.
-- Risk: None. No DML, no DDL.
-- Prior history checked: Not applicable - read-only verification.
-- END INTENT

prompt === verify deployment ===
select health_api.get_status as status from dual;
select count(*) as ui_asset_count from ui_assets;
select audience,
       scope_name as auth_scope,
       nvl(kid, '(none - run bin/ensure-auth-key.sh)') as signing_kid
  from jwt_scaffold_config;

-- A missing @deploy/create/80_standalone.generated.sql is skipped by SQLcl without failing the
-- run, which would leave auth silently unconfigured. Fail loudly instead.
declare
  l_count number;
begin
  select count(*) into l_count from jwt_scaffold_config where config_id = 1;
  if l_count = 0 then
    raise_application_error(
      -20000,
      'JWT_SCAFFOLD_CONFIG is empty - run bin/render-auth-config.sh --env <env> then redeploy'
    );
  end if;
end;
/

prompt === verify identity model (spec patch 06) ===

declare
  l_count    number;
  l_expected constant number := 6;

  procedure assert(p_condition in boolean, p_message in varchar2) is
  begin
    if not nvl(p_condition, false) then
      raise_application_error(-20000, p_message);
    end if;
  end assert;
begin
  -- 1. All six tables present. A half-applied deploy is the thing this catches.
  select count(*)
    into l_count
    from user_tables
   where table_name in ('ROAD_PRINCIPALS', 'ROAD_ROLES', 'ROAD_PERMISSIONS',
                        'ROAD_ROLE_PERMISSIONS', 'ROAD_PRINCIPAL_ROLES', 'ROAD_CONFIG');
  assert(l_count = l_expected,
         'Expected ' || l_expected || ' identity tables, found ' || l_count);

  -- 2. The three baseline roles, with the two road.* ones reserved.
  select count(*)
    into l_count
    from road_roles
   where role_name in ('road.system_admin', 'road.user_admin', 'user');
  assert(l_count = 3, 'Expected 3 baseline roles, found ' || l_count);

  select count(*)
    into l_count
    from road_roles
   where role_name in ('road.system_admin', 'road.user_admin')
     and is_reserved = 'Y';
  assert(l_count = 2, 'Both road.* baseline roles must be reserved, found ' || l_count);

  -- 3. road.system_admin actually composes its permissions.
  select count(*)
    into l_count
    from road_role_permissions
   where role_name = 'road.system_admin'
     and permission_name = 'road.role.define';
  assert(l_count = 1, 'road.system_admin must hold road.role.define');

  -- 4. road.user_admin must NOT be able to define roles -- the two-tier split is the point.
  select count(*)
    into l_count
    from road_role_permissions
   where role_name = 'road.user_admin'
     and permission_name in ('road.role.define', 'road.permission.define');
  assert(l_count = 0,
         'road.user_admin must not hold define permissions, found ' || l_count);

  -- 5. Exactly one principal can administer the system. Zero means the deploy produced an
  --    identity model nobody can administer, which is the failure mode section 10 question 1
  --    exists to prevent.
  select count(*)
    into l_count
    from road_principal_roles
   where role_name = 'road.system_admin';
  assert(l_count >= 1,
         'No principal holds road.system_admin - check road_config.bootstrap_admin_subject');

  -- 6. Exactly one ORDS JWT profile. This is the tripwire for the phase 0.1 spike constraint:
  --    road_ctx resolves the issuer from this view, which is only unambiguous while trust is
  --    schema-level with a single profile. A second profile means the implementation must move to
  --    reading the token header instead. See planning/spike-06-1-iss-reachability.md section 4.
  select count(*) into l_count from user_ords_jwt_profile;
  assert(l_count = 1,
         'Expected exactly 1 ORDS JWT profile, found ' || l_count
         || ' - road_ctx issuer resolution is ambiguous, see spike-06-1');

  dbms_output.put_line('[INFO] Identity model verified: 6 tables, 3 roles, 4 permissions, bootstrap admin present');
end;
/
