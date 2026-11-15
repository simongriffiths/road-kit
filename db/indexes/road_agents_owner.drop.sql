begin
  execute immediate 'drop index road_agents_owner_ix';
exception
  when others then
    if sqlcode != -1418 then
      raise;
    end if;
end;
/
