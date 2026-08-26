begin
  execute immediate 'drop table jwt_scaffold_credentials purge';
exception
  when others then
    if sqlcode != -942 then
      raise;
    end if;
end;
/
