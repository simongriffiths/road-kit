whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback

prompt === composition guard assertions (spec patch 07) ===

-- Runs AFTER 95_data.sql, deliberately: both assertions below need the seed already in place.
-- road_admin_reachable is `exists`, which is false against an empty table, so it cannot be
-- created before the seed grants road.role.grant to road.system_admin. Creating both here also
-- makes them validate the seed -- a 95_data.sql that produced a violation fails the deploy at
-- this step (spec-patch-07 section 5.3).
--
-- Needs CREATE ASSERTION, granted schema-scoped (not CREATE ANY ASSERTION) by
-- admin/grant-schema-privileges.sql. See planning/spike-07-1-assertion-support.md.

-- The invariant is PROVENANCE, not state: road.system_admin legitimately holds road.role.grant,
-- and calendar_admin legitimately holds events.purge -- both are reserved permissions attached to
-- roles. What is forbidden is a reserved permission attached BY A SESSION. attached_by is null for
-- a deploy (no session context to read a principal from) and always non-null for
-- road_admin_api.attach_permission, which takes it from road_ctx_pkg.principal_id -- so the audit
-- column carries the rule (spec-patch-07 section 5.1).
--
-- COMMA JOIN, NOT ANSI: `JOIN ... ON` is rejected with ORA-08735 inside an ORA-08689 wrapper on
-- 26ai (spike-07-1 section 3.3). This is not a style choice -- an ANSI rewrite looks like tidying
-- and fails at deploy time, not review time. Do not "simplify" this to a JOIN.
--
-- This is an ASSERTION rather than a BEFORE INSERT trigger on road_role_permissions because the
-- escalation this guards against is the PARENT table (road_permissions) being updated -- flipping
-- an existing row's is_reserved to 'Y' out from under an already session-attached grant. A trigger
-- on the child table would never fire for that case (spike-07-1 section 3.4, row 3).
create assertion road_reserved_composition check (
  not exists (
    select 1
      from road_role_permissions rp, road_permissions p
     where p.permission_name = rp.permission_name
       and p.is_reserved = 'Y'
       and rp.attached_by is not null
  )
);

-- Reachability, the other direction. This assertion does NOT cover DELETE -- a `not exists`
-- predicate cannot be violated by removing a row, so road_reserved_composition does not stop
-- detaching road.role.grant from road.system_admin, and that would be a lock-out (the role keeps
-- its holders, so revoke_role's last-administrator guard never fires). Named on the PERMISSION,
-- not the role, because the invariant is "somebody can still grant roles", not "this particular
-- role still exists" (spec-patch-07 section 5.3). Together with revoke_role's refusal to remove
-- the last road.system_admin holder, administration stays reachable from both directions.
create assertion road_admin_reachable check (
  exists (select 1 from road_role_permissions where permission_name = 'road.role.grant')
);
