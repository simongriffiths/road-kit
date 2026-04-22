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
  ords.delete_module(p_module_name => 'hello_api.ui');
exception
  when others then
    null;
end;
/

begin
  ords.define_module(
    p_module_name    => 'hello_api.ui',
    p_base_path      => '/ui/hello_world',
    p_items_per_page => 25,
    p_status         => 'PUBLISHED',
    p_comments       => 'ROAD public UI asset delivery module'
  );

  ords.define_template(
    p_module_name => 'hello_api.ui',
    p_pattern     => '/',
    p_priority    => 0,
    p_etag_type   => 'NONE',
    p_comments    => 'Root UI entry point'
  );

  ords.define_handler(
    p_module_name => 'hello_api.ui',
    p_pattern     => '/',
    p_method      => 'GET',
    p_source_type => ords.source_type_media,
    p_source      => q'[
      select a.content_type as "Content-Type",
             a.content as blob
        from ui_assets a
       where a.app_name = 'hello_world'
         and a.relative_path = 'index.html'
    ]',
    p_comments    => 'Returns the UI entry point'
  );

  ords.define_template(
    p_module_name => 'hello_api.ui',
    p_pattern     => '/:requested_path*',
    p_priority    => 1,
    p_etag_type   => 'NONE',
    p_comments    => 'Asset and SPA route delivery'
  );

  ords.define_handler(
    p_module_name => 'hello_api.ui',
    p_pattern     => '/:requested_path*',
    p_method      => 'GET',
    p_source_type => ords.source_type_media,
    p_source      => q'[
      with request_path as (
        select case
                 when :requested_path is null or :requested_path = '' then 'index.html'
                 when instr(:requested_path, '..') > 0 then '__invalid__'
                 when instr(:requested_path, '//') > 0 then '__invalid__'
                 when substr(:requested_path, 1, 1) = '/' then '__invalid__'
                 when regexp_like(:requested_path, '\.[[:alnum:]]+$') then :requested_path
                 else 'index.html'
               end as resolved_path
          from dual
      )
      select a.content_type as "Content-Type",
             a.content as blob
        from ui_assets a
        join request_path r
          on a.relative_path = r.resolved_path
       where a.app_name = 'hello_world'
         and r.resolved_path != '__invalid__'
    ]',
    p_comments    => 'Returns UI assets and SPA fallback'
  );

  commit;
end;
/
