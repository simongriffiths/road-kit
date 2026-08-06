whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback

-- INTENT:
-- Purpose: Compile the framework package specifications.
-- Approach: Invoke each .pks under db/package_specs/ in dependency order.
-- Reason: Specs compile before bodies so dependent bodies resolve on first pass.
-- Expected objects:
--   UI_ASSETS_API, HEALTH_API, JWT_SCAFFOLD_AUTH_API, SESSION_API (specs)
-- Risk: Low. Recompiling a spec invalidates dependent bodies until 70_package_bodies runs.
-- Prior history checked: Check db-history for recent USER_ERRORS on these packages.
-- END INTENT

prompt === deploy package specs ===
@db/package_specs/ui_assets_api.pks
@db/package_specs/health_api.pks
@db/package_specs/jwt_scaffold_auth_api.pks
@db/package_specs/session_api.pks
