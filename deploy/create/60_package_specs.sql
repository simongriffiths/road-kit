whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback

prompt === deploy package specs ===
@db/package_specs/ui_assets_api.pks
@db/package_specs/health_api.pks
