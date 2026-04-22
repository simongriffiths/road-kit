begin
  execute immediate 'drop table jwt_scaffold_config cascade constraints purge';
exception
  when others then
    if sqlcode != -942 then
      raise;
    end if;
end;
/
