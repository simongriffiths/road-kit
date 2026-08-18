-- Which permissions a role composes. Every row is an explicit grant: a permission added later must
-- never be silently acquired by an existing role (spec-patch-06 rule 4). That is why
-- road_admin.grant_all_app_permissions writes real rows at deploy time instead of being a runtime
-- wildcard.
create table road_role_permissions (
  role_name       varchar2(64 char) not null references road_roles,
  permission_name varchar2(64 char) not null references road_permissions,
  constraint road_role_permissions_pk primary key (role_name, permission_name)
);
