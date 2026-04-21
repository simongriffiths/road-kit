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
  ords.delete_module(p_module_name => 'hello_api.health');
exception
  when others then
    null;
end;
/

begin
  ords.define_module(
    p_module_name    => 'hello_api.health',
    p_base_path      => '/api/v1/',
    p_items_per_page => 25,
    p_status         => 'PUBLISHED',
    p_comments       => 'ROAD health probe module'
  );

  ords.define_template(
    p_module_name => 'hello_api.health',
    p_pattern     => 'health/',
    p_comments    => 'Health endpoint'
  );

  ords.define_handler(
    p_module_name => 'hello_api.health',
    p_pattern     => 'health/',
    p_method      => 'GET',
    p_source_type => ords.source_type_collection_item,
    p_source      => q'[
      select health_api.get_status as status
      from dual
    ]',
    p_comments    => 'Returns ROAD health status'
  );

  commit;
end;
/
