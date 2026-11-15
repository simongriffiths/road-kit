whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback
-- INTENT:
-- Purpose: List the deployed ORDS handlers and the contract versions the database holds, for
--   test/contract/check-contract-coverage.mjs.
-- Approach: Read-only selects on USER_ORDS_MODULES, USER_ORDS_TEMPLATES, USER_ORDS_HANDLERS and
--   ROAD_CONTRACT, one prefixed line each.
-- Reason: Definition 9.5 (every handler has a contract entry and every entry a handler); spec-patch-16
--   section 3.5.
-- Expected objects: None.
-- Risk: None. Reads only.
-- Prior history checked: deploy/create/90_rest.sql; road-tracker's test/contract/read-deployed-surface.sql.
-- END INTENT
set pagesize 0 feedback off heading off linesize 400 serveroutput on
select 'HANDLER|' || h.method || '|' || m.uri_prefix || '|' || t.uri_template
  from user_ords_modules m
  join user_ords_templates t on t.module_id = m.id
  join user_ords_handlers h on h.template_id = t.id
 order by 1;
select 'STORED|' || contract_version from road_contract;
select 'SERVED|' || json_value(document, '$.envelope.contract_version') from road_contract;
