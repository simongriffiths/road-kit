whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback
-- INTENT:
-- Purpose: Run every framework PL/SQL test suite, and report invalid objects and compile errors.
-- Approach: Each suite's run_all, committing between suites (each cleans up after itself).
-- Reason: road-kit had no committed runner; road-tracker wrote this one during its build and
--   spec-patch-15 adds road_agent_api_test.
-- Expected objects: None left behind.
-- Risk: Low. Suites roll back their fixtures.
-- Prior history checked: road-tracker test/plsql/run-framework-tests.sql.
-- END INTENT
set serveroutput on size unlimited
set feedback off

prompt === invalid objects (expect none) ===
select object_type, object_name from user_objects where status != 'VALID' order by 1, 2;

prompt === user_errors (expect none) ===
select name, type, line, text from user_errors order by name, type, sequence;

prompt === suites ===
begin error_api_test.run_all; end;
/
commit;
begin road_decision_api_test.run_all; end;
/
commit;
begin road_surface_api_test.run_all; end;
/
commit;
begin road_audit_api_test.run_all; end;
/
commit;
begin road_ctx_pkg_test.run_all; end;
/
commit;
begin road_admin_api_test.run_all; end;
/
commit;
begin road_agent_api_test.run_all; end;
/
commit;
begin jwt_scaffold_crypto_test.run_all; end;
/
commit;
begin jwt_scaffold_auth_api_test.run_all; end;
/
commit;
begin demo_todo_api_test.run_all; end;
/
commit;
