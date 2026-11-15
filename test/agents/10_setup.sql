whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback
-- INTENT:
-- Purpose: Fixture for the spec-patch-15 HTTP and CLI tests (bin/run-agent-tests.sh): a second
--   person, ZZ_AGENT_OTHER, with the demo's default role, so a test can show one person cannot see
--   another's agents.
-- Approach: Insert the principal in the scaffold's issuer if missing, and grant role user (env dev).
-- Reason: ROAD_KIT_DEV has only ADMIN and USER1.
-- Expected objects: one ROAD_PRINCIPALS row and one role grant, removed by 90_cleanup.sql.
-- Risk: Low.
-- Prior history checked: scratch/probe-principals.sql.
-- END INTENT
insert into road_principals (issuer, subject, display_name)
select issuer, 'ZZ_AGENT_OTHER', 'Agent test other person' from jwt_scaffold_config
 where not exists (select 1 from road_principals where subject = 'ZZ_AGENT_OTHER');
insert into road_principal_roles (principal_id, role_name)
select principal_id, 'user' from road_principals p where subject = 'ZZ_AGENT_OTHER'
   and not exists (select 1 from road_principal_roles r where r.principal_id = p.principal_id and r.role_name = 'user');
commit;
