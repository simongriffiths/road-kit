whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback

begin
  ords.delete_module(p_module_name => 'hello_api.session');
exception
  when others then
    dbms_output.put_line('Note: Module may not exist - ' || sqlerrm);
end;
/

commit;
