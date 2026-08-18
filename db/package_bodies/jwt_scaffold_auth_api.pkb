create or replace package body jwt_scaffold_auth_api as
  c_admin_username constant varchar2(30) := 'ADMIN';
  c_admin_salt     constant raw(16)      := hextoraw('81DAE563DC239D38FEBF76FAD3885104');
  c_admin_hash     constant raw(32)      := hextoraw('5C104866B778B69DBC36E06B3230FF5BCBBBC76E5E3FAE85CF1C503499960B69');

  c_user1_username constant varchar2(30) := 'USER1';
  c_user1_salt     constant raw(16)      := hextoraw('A244EF5B579898203EC68A3F1B40E3B6');
  c_user1_hash     constant raw(32)      := hextoraw('9C1DB83A7656BE02AEAE6F1ED10759AC15266CDB8ABE85099A5EE1C31154BCF8');

  c_user2_username constant varchar2(30) := 'USER2';
  c_user2_salt     constant raw(16)      := hextoraw('C7FFDC97A465A438E3BB68C0E597CFC5');
  c_user2_hash     constant raw(32)      := hextoraw('B96BF0DBAC303473AEB14507EA73F6795DDE1ADD502760E9FD4A83488F35C3DB');

  type t_config is record (
    issuer           jwt_scaffold_config.issuer%type,
    audience         jwt_scaffold_config.audience%type,
    scope_name       jwt_scaffold_config.scope_name%type,
    ttl_minutes      jwt_scaffold_config.ttl_minutes%type,
    jwk_url          jwt_scaffold_config.jwk_url%type,
    kid              jwt_scaffold_config.kid%type,
    private_key_b64  jwt_scaffold_config.private_key_b64%type,
    public_n         jwt_scaffold_config.public_n%type,
    public_e         jwt_scaffold_config.public_e%type
  );

  function get_config return t_config is
    l_config t_config;
  begin
    select issuer,
           audience,
           scope_name,
           ttl_minutes,
           jwk_url,
           kid,
           private_key_b64,
           public_n,
           public_e
      into l_config
      from jwt_scaffold_config
     where config_id = 1;

    return l_config;
  end get_config;

  function password_digest(
    p_password in varchar2,
    p_salt     in raw
  ) return raw is
  begin
    return dbms_crypto.hash(
      src => utl_i18n.string_to_raw(nvl(p_password, ''), 'AL32UTF8') || p_salt,
      typ => dbms_crypto.hash_sh256
    );
  end password_digest;

  function base64url_from_raw(p_raw in raw) return varchar2 is
    l_b64 varchar2(32767);
  begin
    l_b64 := utl_raw.cast_to_varchar2(utl_encode.base64_encode(p_raw));
    l_b64 := replace(l_b64, chr(10), '');
    l_b64 := replace(l_b64, chr(13), '');
    l_b64 := replace(l_b64, '+', '-');
    l_b64 := replace(l_b64, '/', '_');
    l_b64 := rtrim(l_b64, '=');
    return l_b64;
  end base64url_from_raw;

  function base64url_from_text(p_text in clob) return varchar2 is
  begin
    return base64url_from_raw(
      utl_i18n.string_to_raw(dbms_lob.substr(p_text, 32767, 1), 'AL32UTF8')
    );
  end base64url_from_text;

  function epoch_seconds_now return number is
  begin
    return floor(
      (cast(systimestamp at time zone 'UTC' as date) - date '1970-01-01') * 86400
    );
  end epoch_seconds_now;

  function check_credentials(
    p_username in varchar2,
    p_password in varchar2
  ) return boolean is
    l_username varchar2(30) := upper(trim(p_username));
    l_digest   raw(32);
  begin
    if l_username = c_admin_username then
      l_digest := password_digest(p_password, c_admin_salt);
      return l_digest = c_admin_hash;
    elsif l_username = c_user1_username then
      l_digest := password_digest(p_password, c_user1_salt);
      return l_digest = c_user1_hash;
    elsif l_username = c_user2_username then
      l_digest := password_digest(p_password, c_user2_salt);
      return l_digest = c_user2_hash;
    end if;

    return false;
  end check_credentials;

  function issue_token(
    p_username in varchar2,
    p_scope    in varchar2 default null
  ) return clob is
    l_config        t_config;
    l_iat           number;
    l_exp           number;
    l_scope         varchar2(4000);
    l_header_json   clob;
    l_payload_json  clob;
    l_header_b64    varchar2(32767);
    l_payload_b64   varchar2(32767);
    l_signing_input varchar2(32767);
    l_signature_raw raw(32767);
  begin
    l_config := get_config;
    l_iat := epoch_seconds_now;
    l_exp := l_iat + (l_config.ttl_minutes * 60);
    l_scope := nvl(p_scope, l_config.scope_name);

    select json_object(
             'alg' value 'RS256',
             'typ' value 'JWT',
             'kid' value l_config.kid
             returning clob
           )
      into l_header_json
      from dual;

    select json_object(
             'sub'   value upper(trim(p_username)),
             'iss'   value l_config.issuer,
             'aud'   value l_config.audience,
             'exp'   value l_exp,
             'iat'   value l_iat,
             'scope' value l_scope,
             'env'   value 'dev-scaffold'
             returning clob
           )
      into l_payload_json
      from dual;

    l_header_b64 := base64url_from_text(l_header_json);
    l_payload_b64 := base64url_from_text(l_payload_json);
    l_signing_input := l_header_b64 || '.' || l_payload_b64;

    l_signature_raw := dbms_crypto.sign(
      src        => utl_i18n.string_to_raw(l_signing_input, 'AL32UTF8'),
      prv_key    => utl_i18n.string_to_raw(l_config.private_key_b64, 'AL32UTF8'),
      pubkey_alg => dbms_crypto.key_type_rsa,
      sign_alg   => dbms_crypto.sign_sha256_rsa
    );

    return l_signing_input || '.' || base64url_from_raw(l_signature_raw);
  end issue_token;

  function jwks_document return clob is
    l_config t_config;
    l_jwks   clob;
  begin
    l_config := get_config;

    select json_object(
             'keys' value json_array(
               json_object(
                 'kty' value 'RSA',
                 'use' value 'sig',
                 'kid' value l_config.kid,
                 'alg' value 'RS256',
                 'n'   value l_config.public_n,
                 'e'   value l_config.public_e
                 returning clob
               )
               returning clob
             )
             returning clob
           )
      into l_jwks
      from dual;

    return l_jwks;
  end jwks_document;

  procedure authenticate_json(
    p_body              in  clob,
    p_access_token      out varchar2,
    p_token_type        out varchar2,
    p_expires_in        out number,
    p_kid               out varchar2,
    p_error             out varchar2,
    p_error_description out varchar2,
    p_http_status       out number
  ) is
    l_payload  json_object_t;
    l_username varchar2(255);
    l_password varchar2(255);
    l_config   t_config;
  begin
    p_access_token := null;
    p_token_type := null;
    p_expires_in := null;
    p_kid := null;
    p_error := null;
    p_error_description := null;
    p_http_status := 200;

    l_payload := json_object_t.parse(p_body);
    l_username := upper(trim(l_payload.get_string('username')));
    l_password := l_payload.get_string('password');

    if l_username is null or l_password is null then
      p_error := 'invalid_request';
      p_error_description := 'username and password are required';
      p_http_status := 400;
      return;
    end if;

    if not check_credentials(l_username, l_password) then
      p_error := 'invalid_credentials';
      p_error_description := 'invalid username or password';
      p_http_status := 401;
      return;
    end if;

    l_config := get_config;

    p_access_token := issue_token(l_username, l_config.scope_name);
    p_token_type := 'Bearer';
    p_expires_in := l_config.ttl_minutes * 60;
    p_kid := l_config.kid;
    p_http_status := 200;
  exception
    when others then
      if sqlcode in (-40441, -40587) then
        p_error := 'invalid_request';
        p_error_description := 'request body must be valid JSON';
        p_http_status := 400;
      else
        p_error := 'server_error';
        p_error_description := substr(sqlerrm, 1, 250);
        p_http_status := 500;
      end if;
  end authenticate_json;
end jwt_scaffold_auth_api;
/
