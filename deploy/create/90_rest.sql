whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback

prompt === deploy ords modules ===
@api/modules/health/module.create.sql
@api/modules/health/privileges.create.sql
@api/modules/auth/module.create.sql
@api/modules/auth/privileges.create.sql
@api/modules/session/module.create.sql
@api/modules/session/privileges.create.sql
@api/modules/ui/module.create.sql
@api/modules/ui/privileges.create.sql
