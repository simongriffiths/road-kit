-- Which permissions a role composes. Every row is an explicit grant: a permission added later must
-- never be silently acquired by an existing role (spec-patch-06 rule 4). That is why
-- road_admin.grant_all_app_permissions writes real rows at deploy time instead of being a runtime
-- wildcard.
--
-- attached_by is NULLABLE, and the nullability is load-bearing (spec-patch-07 section 4): a deploy
-- has no session context to read a principal from, so 95_data.sql and grant_all_app_permissions
-- write null, meaning "seeded at deploy time". attach_permission always writes a real principal_id.
-- The road_reserved_composition assertion reads this column to distinguish the two -- do not
-- "simplify" it away as mere audit.
create table road_role_permissions (
  role_name       varchar2(64 char) not null references road_roles,
  permission_name varchar2(64 char) not null references road_permissions,
  attached_at     timestamp with time zone default systimestamp not null,
  attached_by     number references road_principals,
  constraint road_role_permissions_pk primary key (role_name, permission_name)
);
