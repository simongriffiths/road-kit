whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback

-- INTENT:
-- Purpose: Confirm a completed deployment is healthy.
-- Approach: Read-only probes - health package status, UI asset count, JWT config presence.
-- Reason: A deploy that compiled without error can still be wrong (empty config, no
--   UI assets); this makes that visible in the run log.
-- Expected objects: None created. Read-only.
-- Risk: None. No DML, no DDL.
-- Prior history checked: Not applicable - read-only verification.
-- END INTENT

prompt === verify deployment ===
select health_api.get_status as status from dual;
select count(*) as ui_asset_count from ui_assets;
select audience, scope_name as auth_scope from jwt_scaffold_config;
