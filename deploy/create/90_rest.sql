whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback

prompt === deploy ords modules ===
@api/modules/health/module.create.sql
@api/modules/health/privileges.create.sql
