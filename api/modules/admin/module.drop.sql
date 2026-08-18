whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback

begin
  ords.delete_module(p_module_name => 'road_cal_api.admin');
exception
  when others then
    null;
end;
/

commit;
