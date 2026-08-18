-- Which roles a principal holds. No scope_key: an earlier draft carried one so roles could be
-- per-tenant, dropped on the decision that one primary email is one principal and no login spans
-- tenants (spec-patch-06 sections 4.3 and 9.3). An application needing per-tenant membership
-- carries its own dimension.
--
-- granted_by is always taken from road_ctx.principal_id, never from a request body.
create table road_principal_roles (
  principal_id number not null references road_principals,
  role_name    varchar2(64 char) not null references road_roles,
  granted_at   timestamp with time zone default systimestamp not null,
  granted_by   number references road_principals,
  constraint road_principal_roles_pk primary key (principal_id, role_name)
);
