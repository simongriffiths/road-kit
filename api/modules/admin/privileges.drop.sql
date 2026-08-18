whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback

begin
  ords.delete_privilege(p_name => 'road.admin.rw');
exception
  when others then
    null;
end;
/

commit;
