whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback

prompt === deploy triggers ===
@db/triggers/road_principals_updated_at.create.sql
@db/triggers/road_config_updated_at.create.sql
