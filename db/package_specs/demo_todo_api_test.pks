create or replace package demo_todo_api_test as

  -- Tests for the demo application (spec-patch-08 section 8). Same shape as road_admin_api_test:
  -- seeds its own principals and roles, runs each test independently, tears down in an exception
  -- handler so a failure still cleans up.
  --
  -- Covers what the demo exists to prove: ownership isolation, the read_token staleness path, the
  -- status transition rules, and purge's cross-owner reach. The framework-side assertions the demo
  -- ENABLES -- that attach_permission refuses todo.purge, and that grant_all_app_permissions skips
  -- it -- belong in road_admin_api_test, not here.
  procedure run_all;

end demo_todo_api_test;
/
