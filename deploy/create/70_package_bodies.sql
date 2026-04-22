whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback

prompt === deploy package bodies ===
@db/package_bodies/ui_assets_api.pkb
@db/package_bodies/health_api.pkb
@db/package_bodies/jwt_scaffold_auth_api.pkb
@db/package_bodies/session_api.pkb
