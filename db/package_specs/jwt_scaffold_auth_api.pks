create or replace package jwt_scaffold_auth_api as
  -- Mints a signed JWT. The optional overrides exist so the conformance suite can produce the
  -- NEGATIVE cases authentication-spec-v1.md section 12 requires -- expired, wrong issuer, wrong
  -- audience -- which cannot be built by tampering, because any edit breaks the signature and would
  -- test signature validation instead of the claim under test.
  --
  -- This widens nothing. issue_token already mints for any username with no password check, so
  -- anyone able to call it already holds schema access and could sign anything they liked. Scaffold
  -- only: authentication-spec-v1.md section 10 marks this profile development-use and not
  -- production ready, and these parameters retire with it.
  --
  -- Each override defaults to null, meaning "use JWT_SCAFFOLD_CONFIG".
  function issue_token(
    p_username    in varchar2,
    p_scope       in varchar2 default null,
    p_issuer      in varchar2 default null,
    p_audience    in varchar2 default null,
    p_ttl_minutes in number   default null
  ) return clob;

  function jwks_document return clob;

  procedure authenticate_json(
    p_body              in  clob,
    p_access_token      out varchar2,
    p_token_type        out varchar2,
    p_expires_in        out number,
    p_kid               out varchar2,
    p_error             out varchar2,
    p_error_description out varchar2,
    p_http_status       out number
  );
end jwt_scaffold_auth_api;
/
