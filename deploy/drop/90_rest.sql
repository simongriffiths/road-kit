whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback

prompt === drop ords modules ===
@api/modules/ui/privileges.drop.sql
@api/modules/ui/module.drop.sql
@api/modules/session/privileges.drop.sql
@api/modules/session/module.drop.sql
@api/modules/auth/privileges.drop.sql
@api/modules/auth/module.drop.sql
@api/modules/health/privileges.drop.sql
@api/modules/health/module.drop.sql
