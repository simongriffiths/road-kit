whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback

-- INTENT:
-- Purpose: Create the framework scaffold tables.
-- Approach: Invoke the per-table create scripts under db/tables/.
-- Reason: Table DDL is kept one-object-per-file so a single table can be redeployed.
-- Expected objects:
--   UI_ASSETS
--   JWT_SCAFFOLD_CONFIG
-- Risk: Low on an empty schema. HIGH if the tables already hold data - the create
--   scripts do not drop, so this fails rather than silently replacing.
-- Prior history checked: Search db-history for prior table deploys before rerunning.
-- END INTENT

prompt === deploy tables ===
@db/tables/ui_assets.create.sql
@db/tables/jwt_scaffold_config.create.sql

prompt === deploy identity tables (spec patch 06) ===
@db/tables/error_log.create.sql
-- Read-token and audit log (spec-patch-01-concurrency section 6). Framework-generic: nothing in
-- road_audit_api names an application concept. It lived only in road-cal until 2026-08-19 --
-- see spec-patch-08 section 7.2.
@db/tables/road_api_log.create.sql
@db/tables/road_config.create.sql
@db/tables/road_principals.create.sql
@db/tables/road_roles.create.sql
@db/tables/road_permissions.create.sql
@db/tables/road_role_permissions.create.sql
@db/tables/road_principal_roles.create.sql
