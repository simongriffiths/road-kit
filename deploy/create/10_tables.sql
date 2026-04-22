whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback

prompt === deploy tables ===
@db/tables/ui_assets.create.sql
@db/tables/jwt_scaffold_config.create.sql
