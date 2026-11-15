-- ORA-955-tolerant, matching this index's own drop.sql (-1418 there) -- see road-atlas F-10.
-- An agent's keys.
begin
  execute immediate 'create index road_api_keys_agent_ix on road_api_keys (principal_id)';
exception
  when others then
    if sqlcode != -955 then
      raise;
    end if;
end;
/
