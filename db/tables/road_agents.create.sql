-- road_agents: which principals are agents, and who owns each (spec-patch-15 section 4.1).
--
-- An agent is a principal of its own, never its owner: it holds the application's agent role
-- (road_config agents.role), is attributed to itself in road_decisions, and stops when its owner
-- is not ACTIVE. owner_principal_id is null for a shared agent an administrator made. A principal
-- is an agent if and only if it has a row here; road_principals itself is unchanged.
-- ORA-955-tolerant, matching its drop script (road-atlas F-10).
begin
  execute immediate q'[
    create table road_agents (
      principal_id        number not null constraint road_agents_pk primary key
                          constraint road_agents_principal_fk references road_principals,
      owner_principal_id  number constraint road_agents_owner_fk references road_principals,
      created_by          number not null constraint road_agents_by_fk references road_principals,
      created_at          timestamp with time zone default systimestamp not null
    )
  ]';
exception
  when others then
    if sqlcode != -955 then
      raise;
    end if;
end;
/

comment on table road_agents is 'Which principals are agents, and who owns each (null owner: a shared agent). spec-patch-15.';
