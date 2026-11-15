whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback
begin
  ords.delete_module(p_module_name => 'hello_api.api_auth');
  commit;
exception
  when others then
    null;
end;
/
