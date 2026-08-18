-- The vocabulary application code checks. Handlers call road_ctx.require_permission('events.purge'),
-- never require_role -- because permissions are what make role composition a data change rather
-- than a release (spec-patch-06 section 6.1).
create table road_permissions (
  permission_name varchar2(64 char) primary key,
  description     varchar2(4000 char)
);
