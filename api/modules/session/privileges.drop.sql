whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback

begin
  ords.delete_privilege(p_name => 'session.me.read');
exception
  when others then
    dbms_output.put_line('Note: Privilege may not exist - ' || sqlerrm);
end;
/

commit;
