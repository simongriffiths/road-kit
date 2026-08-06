whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback

-- INTENT:
-- Purpose: Tear down the entire ROAD framework scaffold from an application schema.
-- Approach: Run the drop/ chain in reverse dependency order (ORDS modules first,
--   tables last).
-- Reason: Clean-slate rebuild during development.
-- Expected objects: ALL scaffold objects REMOVED -
--   ORDS modules: health, auth, session, ui
--   UI_ASSETS_API, HEALTH_API, JWT_SCAFFOLD_AUTH_API, SESSION_API
--   UI_ASSETS, JWT_SCAFFOLD_CONFIG (and all data in them)
-- Risk: HIGH - DESTRUCTIVE AND IRREVERSIBLE. Drops tables and every row they contain,
--   including uploaded UI assets and JWT signing key material. There is no backup step
--   in this script. Never run against test or prod without an explicit, separately
--   confirmed decision; prod additionally requires ALLOW_PROD_SQL=yes.
-- Prior history checked: Confirm the target environment in db-history before running,
--   and confirm the connection is the one you think it is.
-- END INTENT

prompt === full teardown ===
@deploy/drop/90_rest.sql
@deploy/drop/80_standalone.sql
@deploy/drop/75_type_bodies.sql
@deploy/drop/70_package_bodies.sql
@deploy/drop/60_package_specs.sql
@deploy/drop/40_views.sql
@deploy/drop/30_synonyms.sql
@deploy/drop/20_indexes.sql
@deploy/drop/10_tables.sql
@deploy/drop/05_types.sql
