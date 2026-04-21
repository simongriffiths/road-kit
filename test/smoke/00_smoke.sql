whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback

select health_api.get_status as status from dual;
