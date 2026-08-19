-- The vocabulary application code checks. Handlers call road_ctx.require_permission('events.purge'),
-- never require_role -- because permissions are what make role composition a data change rather
-- than a release (spec-patch-06 section 6.1).
-- is_reserved marks a permission whose composition is framework- or application-owned rather than
-- an administrator's to change at runtime (spec-patch-07 rule 6). Read from this column, never
-- inferred from the permission_name -- events.purge is reserved and does not start with road.,
-- which is exactly the case a naming convention would get wrong (spec-patch-07 section 3.1).
create table road_permissions (
  permission_name varchar2(64 char) primary key,
  description     varchar2(4000 char),
  is_reserved     varchar2(1 char) default 'N' not null,
  constraint road_permissions_reserved_ck check (is_reserved in ('Y','N'))
);
