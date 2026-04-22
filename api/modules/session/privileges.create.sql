whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback

begin
  ords.delete_privilege(p_name => 'session.me.read');
exception
  when others then
    null;
end;
/

declare
  l_roles    owa.vc_arr;
  l_patterns owa.vc_arr;
begin
  l_patterns(1) := '/api/v1/session/me/*';

  ords.define_privilege(
    p_privilege_name => 'session.me.read',
    p_roles          => l_roles,
    p_patterns       => l_patterns,
    p_label          => 'ROAD Session Me Read',
    p_description    => 'Protects the ROAD session/me endpoint'
  );

  commit;
end;
/
