create or replace package jwt_scaffold_auth_api as
  function issue_token(
    p_username in varchar2,
    p_scope    in varchar2 default null
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
