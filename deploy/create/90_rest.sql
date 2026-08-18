whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback

-- INTENT:
-- Purpose: Define the ORDS modules, templates and handlers for the framework scaffold.
-- Approach: Invoke each module create script plus its privileges script under api/modules/.
-- Reason: ORDS metadata is versioned as code rather than configured by hand, so a
--   schema rebuild reproduces the API surface exactly.
-- Expected objects:
--   ORDS modules: health, auth, session, ui (plus privilege definitions)
-- Risk: Low. Module creates delete and recreate their module, so in-flight requests
--   against a live environment may briefly 404.
-- Prior history checked: Search db-history for prior 90_rest runs in this environment.
-- END INTENT

prompt === deploy ords modules ===
@api/modules/health/module.create.sql
@api/modules/health/privileges.create.sql
@api/modules/auth/module.create.sql
@api/modules/auth/privileges.create.sql
@api/modules/session/module.create.sql
@api/modules/session/privileges.create.sql
@api/modules/ui/module.create.sql
@api/modules/ui/privileges.create.sql
@api/modules/admin/module.create.sql
@api/modules/admin/privileges.create.sql
