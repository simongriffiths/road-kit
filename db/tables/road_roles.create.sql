-- A flat set of roles. No hierarchy and no inheritance, by decision: effective permissions are the
-- union across a principal's roles, and senior_clerk is granted the same permissions as clerk
-- rather than inheriting them (spec-patch-06 rule 2). Inheritance is where RBAC models become
-- unauditable.
--
-- is_reserved marks the road.* roles that gate the framework's own administration surface. An
-- application may rename, redefine or delete an unreserved role; road-kit finds its provisioning
-- default through road_config.default_principal_role rather than by hardcoding the name.
--
-- display_name is data, not code (section 4.4) -- it is what lets an application render "clerk" as
-- Clerk or Clerc without either string appearing in a handler.
create table road_roles (
  role_name    varchar2(64 char) primary key,
  display_name varchar2(255 char),
  description  varchar2(4000 char),
  is_reserved  varchar2(1 char) default 'N' not null,
  constraint road_roles_reserved_ck check (is_reserved in ('Y','N'))
);
