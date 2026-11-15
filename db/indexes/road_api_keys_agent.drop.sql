begin
  execute immediate 'drop index road_api_keys_agent_ix';
exception
  when others then
    if sqlcode != -1418 then
      raise;
    end if;
end;
/
