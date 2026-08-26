whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback

-- The privilege name is also the scope value the token must carry
-- (ords-security-configuration-v1.md section 6), so this string must stay in step with SCOPE_NAME in
-- JWT_SCAFFOLD_CONFIG, rendered from deploy/create/80_standalone.sql.tmpl.
--
-- Closes spec-patch-06 section 8.4, as of spec-patch-09 phase 4: the scaffold now derives each
-- token's scope from the principal's own ROAD_ROLE_PERMISSIONS (jwt_scaffold_auth_api.
-- effective_ords_scope), so this gate actually discriminates. A principal must hold the matching
-- ROAD_PERMISSIONS row -- named road.admin.rw, seeded in 95_data.sql, attached to road.system_admin
-- and road.user_admin -- to reach anything under /api/v1/admin/* at all. road_admin_api's own
-- require_permission on road.role.grant / road.role.define is still the finer-grained control
-- underneath; this is what decides whether a request reaches PL/SQL in the first place.

begin
  ords.delete_privilege(p_name => 'road.admin.rw');
exception
  when others then
    null;
end;
/

declare
  l_roles    owa.vc_arr;
  l_patterns owa.vc_arr;
begin
  l_patterns(1) := '/api/v1/admin/*';

  ords.define_privilege(
    p_privilege_name => 'road.admin.rw',
    p_roles          => l_roles,
    p_patterns       => l_patterns,
    p_label          => 'ROAD Administration',
    p_description    => 'Protects the ROAD role administration endpoints'
  );

  commit;
end;
/
