whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback

begin
  ords.enable_schema(
    p_enabled             => true,
    p_schema              => user,
    p_url_mapping_type    => 'BASE_PATH',
    p_url_mapping_pattern => 'hello_api',
    p_auto_rest_auth      => false
  );
exception
  when others then
    null;
end;
/

begin
  ords.delete_module(p_module_name => 'hello_api.session');
exception
  when others then
    null;
end;
/

begin
  ords.define_module(
    p_module_name    => 'hello_api.session',
    p_base_path      => '/api/v1/session/',
    p_items_per_page => 25,
    p_status         => 'PUBLISHED',
    p_comments       => 'ROAD protected session module'
  );

  ords.define_template(
    p_module_name => 'hello_api.session',
    p_pattern     => 'me/',
    p_comments    => 'Protected session endpoint'
  );

  ords.define_handler(
    p_module_name => 'hello_api.session',
    p_pattern     => 'me/',
    p_method      => 'GET',
    p_source_type => ords.source_type_collection_item,
    p_source      => q'[
      select session_api.get_principal(:current_user) as principal,
             session_api.get_issuer as issuer,
             session_api.get_audience as audience,
             session_api.get_scope as scope,
             case
               when session_api.is_authenticated(:current_user) then 'true'
               else 'false'
             end as authenticated,
             :current_user as current_user,
             sys_context('USERENV', 'CURRENT_USER') as db_user
        from dual
    ]',
    p_comments    => 'Returns the authenticated session identity'
  );

  commit;
end;
/
