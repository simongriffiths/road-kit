whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback

-- INTENT:
-- Purpose: Deploy the full ROAD framework scaffold into an application schema.
-- Approach: Run the ordered create/ chain (types, tables, indexes, synonyms, views,
--   package specs/bodies, type bodies, standalone seed, ORDS modules, seed data) then verify.
-- Reason: Single entry point for a complete schema build; individual numbered scripts
--   exist for targeted redeploys during development.
-- Expected objects:
--   UI_ASSETS, JWT_SCAFFOLD_CONFIG
--   UI_ASSETS_API, HEALTH_API, JWT_SCAFFOLD_AUTH_API, SESSION_API
--   ORDS modules: health, auth, session, ui
-- Risk: Low on an empty schema; Medium on a populated one (object replacement).
-- Prior history checked: Search db-history for prior 00_full runs in this environment.
-- END INTENT

prompt === full deploy ===
@deploy/create/05_types.sql
@deploy/create/10_tables.sql
@deploy/create/15_triggers.sql
@deploy/create/20_indexes.sql
@deploy/create/30_synonyms.sql
@deploy/create/40_views.sql
@deploy/create/60_package_specs.sql
@deploy/create/65_contexts.sql
@deploy/create/70_package_bodies.sql
@deploy/create/75_type_bodies.sql
@deploy/create/80_standalone.generated.sql
@deploy/create/90_rest.sql
@deploy/create/95_data.sql
@deploy/create/99_verify.sql
