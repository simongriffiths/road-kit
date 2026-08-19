whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback

-- INTENT:
-- Purpose: Compile the framework package bodies.
-- Approach: Invoke each .pkb under db/package_bodies/.
-- Reason: Bodies are deployed separately from specs so implementation can be
--   redeployed without touching the public contract.
-- Expected objects:
--   UI_ASSETS_API, HEALTH_API, JWT_SCAFFOLD_AUTH_API, SESSION_API (bodies)
-- Risk: Low. Review USER_ERRORS after running - a body can fail to compile without
--   failing the script.
-- Prior history checked: Search db-history failures for these package names.
-- END INTENT

prompt === deploy package bodies ===
@db/package_bodies/ui_assets_api.pkb
@db/package_bodies/health_api.pkb
@db/package_bodies/jwt_scaffold_auth_api.pkb
@db/package_bodies/session_api.pkb
@db/package_bodies/error_api.pkb
@db/package_bodies/error_api_test.pkb
@db/package_bodies/road_ctx_pkg.pkb
@db/package_bodies/road_ctx_pkg_test.pkb
@db/package_bodies/road_admin_api.pkb
@db/package_bodies/road_admin_api_test.pkb
@db/package_bodies/road_audit_api.pkb
@db/package_bodies/road_audit_api_test.pkb
