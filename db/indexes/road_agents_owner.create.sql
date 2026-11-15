-- ORA-955-tolerant, matching this index's own drop.sql (-1418 there) -- see road-atlas F-10.
-- A person's own agents, for My agents and the per-owner limit.
begin
  execute immediate 'create index road_agents_owner_ix on road_agents (owner_principal_id)';
exception
  when others then
    if sqlcode != -955 then
      raise;
    end if;
end;
/
