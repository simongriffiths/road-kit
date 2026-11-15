whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback
-- INTENT:
-- Purpose: Remove what bin/run-agent-tests.sh made: agents whose display name starts "agent-test",
--   their keys, roles and decisions, the todos they made, and the fixture person ZZ_AGENT_OTHER.
-- Approach: Delete by those names only (env dev).
-- Reason: Leave ROAD_KIT_DEV as it was.
-- Expected objects: none left.
-- Risk: Low. Names only test rows.
-- Prior history checked: test/agents/10_setup.sql.
-- END INTENT
alter session disable parallel dml;
declare
  l_ids sys.odcinumberlist;
  l_all sys.odcinumberlist;
begin
  select a.principal_id bulk collect into l_ids
    from road_agents a join road_principals p on p.principal_id = a.principal_id
   where p.display_name like 'agent-test%';
  select principal_id bulk collect into l_all from (
    select column_value principal_id from table(l_ids)
    union all
    select principal_id from road_principals where subject = 'ZZ_AGENT_OTHER');
  l_ids := l_all;
  delete from road_api_keys where principal_id in (select column_value from table(l_ids)) or created_by in (select column_value from table(l_ids));
  delete from road_agents where principal_id in (select column_value from table(l_ids)) or owner_principal_id in (select column_value from table(l_ids));
  delete from road_decisions where principal_id in (select column_value from table(l_ids));
  delete from demo_todos where owner_principal_id in (select column_value from table(l_ids));
  delete from road_principal_roles where principal_id in (select column_value from table(l_ids));
  delete from road_principals where principal_id in (select column_value from table(l_ids));
  dbms_output.put_line('[INFO] removed ' || l_ids.count || ' test principals');
  commit;
end;
/
