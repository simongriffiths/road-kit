create or replace package body jwt_scaffold_auth_api as
  -- NO CREDENTIAL CONSTANTS HERE, DELIBERATELY, AND NONE MAY BE ADDED.
  --
  -- Until spec-patch-09 phase 3 this package body carried three usernames, three salts and three
  -- SHA-256 digests as constants. That made changing a password a code change, so a credential
  -- lived in version control by construction -- and is why both repositories' histories had to be
  -- rewritten on 2026-08-18. Credentials are now rows in JWT_SCAFFOLD_CREDENTIALS, written by
  -- bin/set-principal-password.sh, which derives them outside the database.

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

  -- Resolves a username and password to a principal, or returns NULL.
  --
  -- Returns the PRINCIPAL_ID rather than a boolean because the caller needs the identity, not just
  -- the verdict: the token's sub must be the subject as ROAD_PRINCIPALS holds it, not as the caller
  -- typed it, and spec-patch-09 section 4 will derive the scope from this principal's permissions.
  --
  -- EVERY FAILURE RETURNS NULL, with no indication of which one it was. Whether the subject exists,
  -- whether it has a credential, whether the principal is suspended and whether the password is
  -- wrong are indistinguishable to the caller by design -- the login endpoint must not become an
  -- oracle for which usernames are real.
  function resolve_principal(
    p_username in varchar2,
    p_password in varchar2
  ) return number is
    l_username     varchar2(255 char) := upper(trim(p_username));
    l_issuer       varchar2(512 char);
    l_principal_id number;
    l_status       road_principals.status%type;
    l_salt         jwt_scaffold_credentials.salt%type;
    l_stored       jwt_scaffold_credentials.password_hash%type;
    l_iterations   jwt_scaffold_credentials.iterations%type;
    l_algorithm    jwt_scaffold_credentials.algorithm%type;
    l_derived      raw(32);
    l_profiles     number;
  begin
    if l_username is null or p_password is null then
      return null;
    end if;

    -- The issuer comes from the schema's registered JWT profile rather than from configuration,
    -- for the same reason 95_data.sql seeds the bootstrap administrator that way: it is by
    -- construction the issuer this token will carry, so the principal matched here is the principal
    -- road_ctx_pkg.begin_request will find when the token comes back.
    select count(*) into l_profiles from user_ords_jwt_profile;
    if l_profiles != 1 then
      return null;
    end if;
    select issuer into l_issuer from user_ords_jwt_profile;

    begin
      select principal_id, status
        into l_principal_id, l_status
        from road_principals
       where issuer = l_issuer
         and subject = l_username;
    exception
      when no_data_found then
        return null;
    end;

    -- ROAD_PRINCIPALS.STATUS has carried SUSPENDED and RETIRED since patch 06 and nothing had ever
    -- enforced them. A credential is not an entitlement to sign in.
    if l_status != 'ACTIVE' then
      return null;
    end if;

    begin
      select salt, password_hash, iterations, algorithm
        into l_salt, l_stored, l_iterations, l_algorithm
        from jwt_scaffold_credentials
       where principal_id = l_principal_id;
    exception
      when no_data_found then
        -- A principal with no password. Normal under external_oidc, and normal here for anyone
        -- created through the admin screens before a password was set for them.
        return null;
    end;

    -- Verified with the parameters the row was WRITTEN with, not with today's defaults, so raising
    -- the cost later does not invalidate existing rows.
    if l_algorithm != jwt_scaffold_crypto.c_algorithm then
      return null;
    end if;

    l_derived := jwt_scaffold_crypto.pbkdf2_sha256(
      p_password   => p_password,
      p_salt       => l_salt,
      p_iterations => l_iterations,
      p_dk_len     => utl_raw.length(l_stored)
    );

    -- Not a constant-time comparison. PL/SQL offers no primitive for one, and the scaffold is
    -- development-only per authentication-spec-v1.md section 11.5; the timing signal on a digest
    -- comparison is not the weakest thing about a profile that is its own identity provider.
    -- Recorded so it is a known limit rather than an oversight.
    if l_derived = l_stored then
      return l_principal_id;
    end if;

    return null;
  end resolve_principal;

  function issue_token(
    p_username    in varchar2,
    p_scope       in varchar2 default null,
    p_issuer      in varchar2 default null,
    p_audience    in varchar2 default null,
    p_ttl_minutes in number   default null
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
    -- A negative TTL yields an already-expired token, which is how the conformance suite builds the
    -- "expired token" case without touching the stored configuration.
    l_exp := l_iat + (nvl(p_ttl_minutes, l_config.ttl_minutes) * 60);
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
             'iss'   value nvl(p_issuer, l_config.issuer),
             'aud'   value nvl(p_audience, l_config.audience),
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
    l_payload      json_object_t;
    l_username     varchar2(255);
    l_password     varchar2(255);
    l_config       t_config;
    l_principal_id number;
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

    l_principal_id := resolve_principal(l_username, l_password);

    if l_principal_id is null then
      p_error := 'invalid_credentials';
      p_error_description := 'invalid username or password';
      p_http_status := 401;
      return;
    end if;

    l_config := get_config;

    -- Mint against the subject as ROAD_PRINCIPALS holds it, not as the caller typed it. They are
    -- the same today because resolve_principal matches on the uppercased form, but the token's sub
    -- must come from the identity record so that it stays true if that ever stops being so.
    select subject into l_username from road_principals where principal_id = l_principal_id;

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
