whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback

prompt === verify deployment ===
select health_api.get_status as status from dual;
select count(*) as ui_asset_count from ui_assets;
select audience, scope_name as auth_scope from jwt_scaffold_config;
