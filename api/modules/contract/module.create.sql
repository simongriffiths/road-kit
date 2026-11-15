whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback

-- GET /api/v1/contract/: the Governed Surface Contract this deployment serves (definition 5.5,
-- spec-patch-16 section 3.3). PUBLIC on purpose: a consumer reads the contract before it has a
-- token, and the contract holds no data. It is on bin/check-handler-coverage.sh's public list for
-- that reason and carries no privilege. The document is whatever scripts/contract-to-sql.mjs loaded
-- into road_contract.

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
  ords.delete_module(p_module_name => 'hello_api.contract');
exception
  when others then
    null;
end;
/

begin
  ords.define_module(
    p_module_name    => 'hello_api.contract',
    p_base_path      => '/api/v1/contract/',
    p_items_per_page => 0,
    p_status         => 'PUBLISHED',
    p_comments       => 'Governed Surface Contract discovery (spec-patch-16)'
  );

  ords.define_template(
    p_module_name => 'hello_api.contract',
    p_pattern     => '/',
    p_comments    => 'The contract document'
  );

  ords.define_handler(
    p_module_name => 'hello_api.contract',
    p_pattern     => '/',
    p_method      => 'GET',
    p_source_type => ords.source_type_plsql,
    p_source      => q'[
      declare
        l_doc clob;
      begin
        l_doc := road_surface_api.contract;
        road_surface_api.respond(200, l_doc);
      exception
        when others then
          road_surface_api.fail(sqlcode, sqlerrm, dbms_utility.format_error_backtrace, 'contract.get');
      end;
    ]',
    p_comments    => 'Returns the contract document'
  );

  commit;
end;
/
