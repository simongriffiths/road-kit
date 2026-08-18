begin
  execute immediate 'drop trigger road_principals_updated_at_trg';
exception
  when others then
    if sqlcode != -4080 then
      raise;
    end if;
end;
/
