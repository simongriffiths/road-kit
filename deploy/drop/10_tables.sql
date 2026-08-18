whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback

-- INTENT:
-- Purpose: Drop the framework scaffold tables.
-- Approach: Invoke the per-table drop scripts under db/tables/.
-- Reason: Part of the full teardown; also allows a single table to be rebuilt.
-- Expected objects: REMOVED - UI_ASSETS, JWT_SCAFFOLD_CONFIG
-- Risk: HIGH - DESTRUCTIVE AND IRREVERSIBLE. All rows are lost, including uploaded UI
--   assets and JWT signing key material. No backup is taken.
-- Prior history checked: Confirm target environment before running.
-- END INTENT

prompt === drop tables ===
@db/tables/road_principal_roles.drop.sql
@db/tables/road_role_permissions.drop.sql
@db/tables/road_permissions.drop.sql
@db/tables/road_roles.drop.sql
@db/tables/road_principals.drop.sql
@db/tables/road_config.drop.sql
@db/tables/error_log.drop.sql
@db/tables/jwt_scaffold_config.drop.sql
@db/tables/ui_assets.drop.sql
