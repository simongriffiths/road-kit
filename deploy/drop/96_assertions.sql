whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback

prompt === drop composition guard assertions (spec patch 07) ===

-- Must drop BEFORE the tables they depend on -- deploy/drop/00_full.sql runs this file first, for
-- exactly that reason (spec-patch-07 section 5.4). A teardown that leaves an assertion behind
-- blocks the rebuild, the same failure mode DROP ANY CONTEXT was added for in patch 06.
--
-- ORA-13650 ("the specified object does not exist for this execution") is what 26ai raises for
-- DROP ASSERTION on a name that isn't there -- confirmed empirically, not assumed, since assertion
-- error codes are undocumented territory for this project. Tolerated so teardown completes on a
-- schema where these were never created.
begin
  execute immediate 'drop assertion road_reserved_composition';
exception
  when others then
    if sqlcode != -13650 then
      raise;
    end if;
end;
/

begin
  execute immediate 'drop assertion road_admin_reachable';
exception
  when others then
    if sqlcode != -13650 then
      raise;
    end if;
end;
/
