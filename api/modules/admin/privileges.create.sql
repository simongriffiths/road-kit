whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback

-- The privilege name is also the scope value the token must carry
-- (ords-security-configuration-v1.md section 6), so this string must stay in step with SCOPE_NAME in
-- JWT_SCAFFOLD_CONFIG, rendered from deploy/create/80_standalone.sql.tmpl.
--
-- Note what this gate can and cannot do today. The scaffold issues IDENTICAL scopes to every user,
-- so every signed-in caller carries road.admin.rw and ORDS admits them all. The real gate is
-- road_admin_api's require_permission on road.role.grant / road.role.define, which reads
-- database-held roles. That is spec-patch-06 section 8.4 exactly: the ORDS privilege is currently
-- decorative and the permission check is what holds. It becomes meaningful once road-kit is the
-- issuer and can mint per-principal scopes.

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
