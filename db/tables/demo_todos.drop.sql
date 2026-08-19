begin
  execute immediate 'drop table demo_todos cascade constraints purge';
exception
  when others then
    if sqlcode != -942 then
      raise;
    end if;
end;
/
