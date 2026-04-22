whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback

begin
  ords.delete_module(p_module_name => 'hello_api.auth');
exception
  when others then
    dbms_output.put_line('Note: Module may not exist - ' || sqlerrm);
end;
/

begin
  ords_security.delete_jwt_profile;
exception
  when others then
    dbms_output.put_line('Note: JWT profile may not exist - ' || sqlerrm);
end;
/

commit;
