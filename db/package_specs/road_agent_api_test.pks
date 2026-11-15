create or replace package road_agent_api_test as
  -- Tests for road_agent_api (spec-patch-15). Each test runs in a savepoint that is rolled back;
  -- run_all then removes the decision rows its fixture principals left, which are autonomous for
  -- rejections and survive the rollback by design.
  procedure run_all;
end road_agent_api_test;
/
