whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback

prompt === deploy indexes ===
@db/indexes/road_principals_email.create.sql
@db/indexes/road_principal_roles_role.create.sql
