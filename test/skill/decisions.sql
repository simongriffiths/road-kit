whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback
-- INTENT:
-- Purpose: Count what the skill-acceptance agent did, as road-kit's decision record shows it, for
--   bin/run-skill-acceptance.sh.
-- Approach: Read-only selects on ROAD_DECISIONS joined to ROAD_PRINCIPALS, for the fixture agent
--   (display name 'agent-test skill acceptance').
-- Reason: The refusal must be in the decision record, as TITLE_TAKEN from the agent (spec-patch-16 4.3).
-- Expected objects: None.
-- Risk: None. Reads only.
-- Prior history checked: road-tracker's test/skill/decisions.sql.
-- END INTENT
set pagesize 0 feedback off heading off linesize 200
select 'AGENT_CREATES=' || count(*)
  from road_decisions d join road_principals p on p.principal_id = d.principal_id
 where p.display_name = 'agent-test skill acceptance' and d.action_id = 'todos.create' and d.decision = 'accepted';
select 'AGENT_COMPLETIONS=' || count(*)
  from road_decisions d join road_principals p on p.principal_id = d.principal_id
 where p.display_name = 'agent-test skill acceptance' and d.action_id = 'todos.complete' and d.decision = 'accepted';
select 'AGENT_TITLE_TAKEN=' || count(*)
  from road_decisions d join road_principals p on p.principal_id = d.principal_id
 where p.display_name = 'agent-test skill acceptance' and d.action_id = 'todos.create' and d.decision = 'rejected'
   and json_exists(d.rejections, '$[*]?(@.rule_id == "TITLE_TAKEN")');
