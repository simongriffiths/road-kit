whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback

prompt === full deploy ===
@deploy/create/05_types.sql
@deploy/create/10_tables.sql
@deploy/create/20_indexes.sql
@deploy/create/30_synonyms.sql
@deploy/create/40_views.sql
@deploy/create/60_package_specs.sql
@deploy/create/70_package_bodies.sql
@deploy/create/75_type_bodies.sql
@deploy/create/80_standalone.sql
@deploy/create/90_rest.sql
@deploy/create/95_data.sql
@deploy/create/99_verify.sql
