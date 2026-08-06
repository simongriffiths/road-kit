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
