whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback

-- The demo application's own ORDS privilege. The privilege name is also the scope value the token
-- must carry (ords-security-configuration-v1.md section 6), so deploy/create/97_demo.sql appends
-- todo.rw to jwt_scaffold_config.scope_name -- see the comment there for why that append lives in
-- the demo's deploy script and not in 80_standalone.sql.tmpl.
--
-- Since spec-patch-09 phase 4, this gate discriminates: a login's scope is derived per principal
-- (jwt_scaffold_auth_api.effective_ords_scope), and reaching /todos/* at ORDS requires the
-- principal to hold the todo.rw ROAD_PERMISSIONS row seeded and attached below. demo_todo_api's own
-- require_permission on the finer todo.* permissions is still the control underneath, deciding what
-- is allowed once a request arrives -- this decides whether it arrives at all.

begin
  ords.delete_privilege(p_name => 'todo.rw');
exception
  when others then
    null;
end;
/

declare
  l_roles    owa.vc_arr;
  l_patterns owa.vc_arr;
begin
  l_patterns(1) := '/api/v1/todos/*';

  ords.define_privilege(
    p_privilege_name => 'todo.rw',
    p_roles          => l_roles,
    p_patterns       => l_patterns,
    p_label          => 'Demo Todos',
    p_description    => 'Protects the demo application endpoints'
  );

  commit;
end;
/
