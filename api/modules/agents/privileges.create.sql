whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback

-- The ORDS gate to /api/v1/agents/, named as the permission road.agents.rw so a token's scope,
-- derived from the principal's permissions, includes it (spec-patch-09 section 4.2).

begin
  ords.delete_privilege(p_name => 'road.agents.rw');
exception
  when others then
    null;
end;
/

declare
  l_roles    owa.vc_arr;
  l_patterns owa.vc_arr;
begin
  l_patterns(1) := '/api/v1/agents/*';
  ords.define_privilege(
    p_privilege_name => 'road.agents.rw',
    p_roles          => l_roles,
    p_patterns       => l_patterns,
    p_label          => 'ROAD agents',
    p_description    => 'Protects the agents and API key endpoints (spec-patch-15)'
  );
  commit;
end;
/
