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
