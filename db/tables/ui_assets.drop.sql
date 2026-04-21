begin
  execute immediate 'drop table ui_assets cascade constraints purge';
exception
  when others then
    if sqlcode != -942 then
      raise;
    end if;
end;
/
