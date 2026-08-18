begin
  execute immediate 'drop table road_permissions cascade constraints purge';
exception
  when others then
    if sqlcode != -942 then
      raise;
    end if;
end;
/
