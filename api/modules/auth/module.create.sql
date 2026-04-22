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
  ords.delete_module(p_module_name => 'hello_api.auth');
exception
  when others then
    null;
end;
/

begin
  ords_security.delete_jwt_profile;
exception
  when others then
    null;
end;
/

begin
  ords.define_module(
    p_module_name    => 'hello_api.auth',
    p_base_path      => '/jwt-auth/',
    p_items_per_page => 0,
    p_status         => 'PUBLISHED',
    p_comments       => 'ROAD development-only JWT scaffold'
  );

  ords.define_template(
    p_module_name => 'hello_api.auth',
    p_pattern     => 'login',
    p_comments    => 'JWT scaffold login endpoint'
  );

  ords.define_handler(
    p_module_name   => 'hello_api.auth',
    p_pattern       => 'login',
    p_method        => 'POST',
    p_mimes_allowed => 'application/json',
    p_source_type   => ords.source_type_plsql,
    p_source        => q'[
      begin
        jwt_scaffold_auth_api.authenticate_json(
          p_body              => :body_text,
          p_access_token      => :access_token,
          p_token_type        => :token_type,
          p_expires_in        => :expires_in,
          p_kid               => :kid,
          p_error             => :error,
          p_error_description => :error_description,
          p_http_status       => :status
        );
      end;
    ]',
    p_comments      => 'Accepts username/password JSON and returns a JWT'
  );

  ords.define_parameter(
    p_module_name        => 'hello_api.auth',
    p_pattern            => 'login',
    p_method             => 'POST',
    p_name               => 'X-APEX-STATUS-CODE',
    p_bind_variable_name => 'status',
    p_source_type        => 'HEADER',
    p_param_type         => 'INT',
    p_access_method      => 'OUT',
    p_comments           => 'HTTP status code'
  );

  ords.define_parameter(
    p_module_name        => 'hello_api.auth',
    p_pattern            => 'login',
    p_method             => 'POST',
    p_name               => 'access_token',
    p_bind_variable_name => 'access_token',
    p_source_type        => 'RESPONSE',
    p_param_type         => 'STRING',
    p_access_method      => 'OUT'
  );

  ords.define_parameter(
    p_module_name        => 'hello_api.auth',
    p_pattern            => 'login',
    p_method             => 'POST',
    p_name               => 'token_type',
    p_bind_variable_name => 'token_type',
    p_source_type        => 'RESPONSE',
    p_param_type         => 'STRING',
    p_access_method      => 'OUT'
  );

  ords.define_parameter(
    p_module_name        => 'hello_api.auth',
    p_pattern            => 'login',
    p_method             => 'POST',
    p_name               => 'expires_in',
    p_bind_variable_name => 'expires_in',
    p_source_type        => 'RESPONSE',
    p_param_type         => 'INT',
    p_access_method      => 'OUT'
  );

  ords.define_parameter(
    p_module_name        => 'hello_api.auth',
    p_pattern            => 'login',
    p_method             => 'POST',
    p_name               => 'kid',
    p_bind_variable_name => 'kid',
    p_source_type        => 'RESPONSE',
    p_param_type         => 'STRING',
    p_access_method      => 'OUT'
  );

  ords.define_parameter(
    p_module_name        => 'hello_api.auth',
    p_pattern            => 'login',
    p_method             => 'POST',
    p_name               => 'error',
    p_bind_variable_name => 'error',
    p_source_type        => 'RESPONSE',
    p_param_type         => 'STRING',
    p_access_method      => 'OUT'
  );

  ords.define_parameter(
    p_module_name        => 'hello_api.auth',
    p_pattern            => 'login',
    p_method             => 'POST',
    p_name               => 'error_description',
    p_bind_variable_name => 'error_description',
    p_source_type        => 'RESPONSE',
    p_param_type         => 'STRING',
    p_access_method      => 'OUT'
  );

  ords.define_template(
    p_module_name => 'hello_api.auth',
    p_pattern     => '.well-known/jwks.json',
    p_comments    => 'JWT scaffold JWKS endpoint'
  );

  ords.define_handler(
    p_module_name => 'hello_api.auth',
    p_pattern     => '.well-known/jwks.json',
    p_method      => 'GET',
    p_source_type => ords.source_type_media,
    p_source      => q'[
      select 'application/json' as "Content-Type",
             jwt_scaffold_auth_api.jwks_document() as blob
        from dual
    ]',
    p_comments    => 'Returns the active RSA public key as JWKS'
  );

  commit;
end;
/

declare
  l_jwk_url jwt_scaffold_config.jwk_url%type;
  l_issuer  jwt_scaffold_config.issuer%type;
  l_aud     jwt_scaffold_config.audience%type;
  l_ttl     jwt_scaffold_config.ttl_minutes%type;
begin
  select jwk_url,
         issuer,
         audience,
         ttl_minutes
    into l_jwk_url,
         l_issuer,
         l_aud,
         l_ttl
    from jwt_scaffold_config
   where config_id = 1;

  ords_security.create_jwt_profile(
    p_issuer       => l_issuer,
    p_audience     => l_aud,
    p_jwk_url      => l_jwk_url,
    p_description  => 'ROAD development-only JWT scaffold profile',
    p_allowed_skew => 5,
    p_allowed_age  => l_ttl * 60
  );

  commit;
end;
/
