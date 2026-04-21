whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback

prompt === drop ords modules ===
@api/modules/health/privileges.drop.sql
@api/modules/health/module.drop.sql
