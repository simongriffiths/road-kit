whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback

-- INTENT:
-- Purpose: Remove the ORDS modules for the framework scaffold.
-- Approach: Invoke each module drop script under api/modules/.
-- Reason: Part of the full teardown; also used to rebuild the API surface cleanly.
-- Expected objects: REMOVED - ORDS modules health, auth, session, ui
-- Risk: Medium. No data loss, but every endpoint 404s until 90_rest.sql reruns.
-- Prior history checked: Not usually needed - safe to rerun.
-- END INTENT

prompt === drop ords modules ===
@api/modules/ui/privileges.drop.sql
@api/modules/ui/module.drop.sql
@api/modules/session/privileges.drop.sql
@api/modules/session/module.drop.sql
@api/modules/auth/privileges.drop.sql
@api/modules/auth/module.drop.sql
@api/modules/health/privileges.drop.sql
@api/modules/health/module.drop.sql
