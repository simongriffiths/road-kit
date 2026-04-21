whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback

prompt === drop tables ===
@db/tables/ui_assets.drop.sql
