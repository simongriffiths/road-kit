whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback

prompt === drop triggers ===
@db/triggers/road_principals_updated_at.drop.sql
@db/triggers/road_config_updated_at.drop.sql
