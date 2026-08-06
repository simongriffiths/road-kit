whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback

-- INTENT:
-- Purpose: Deploy test-only utility objects into a non-production schema.
-- Approach: Scaffold placeholder - no objects defined yet.
-- Reason: Reserved entry point so test fixtures have a home separate from the
--   application deploy chain.
-- Expected objects: None yet.
-- Risk: None while empty. Never run against prod - test utilities are not application objects.
-- Prior history checked: Not applicable.
-- END INTENT

prompt === deploy test utilities ===
