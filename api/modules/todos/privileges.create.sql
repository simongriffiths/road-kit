whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback

-- The demo application's own ORDS privilege. The privilege name is also the scope value the token
-- must carry (ords-security-configuration-v1.md section 6), so deploy/create/97_demo.sql appends
-- todo.rw to jwt_scaffold_config.scope_name -- see the comment there for why that append lives in
-- the demo's deploy script and not in 80_standalone.sql.tmpl.
--
-- Same caveat as road.admin.rw: the scaffold issues an IDENTICAL scope list to every user, so
-- every signed-in caller reaches /todos/* at the ORDS layer and is then admitted -- or not -- by
-- demo_todo_api's require_permission against database-held roles. The permission check is the
-- control; this is routing.

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
