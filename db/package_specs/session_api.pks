create or replace package session_api as
  procedure assert_authenticated(
    p_current_user in varchar2
  );
  function is_authenticated(
    p_current_user in varchar2
  ) return boolean;
  function get_principal(
    p_current_user in varchar2
  ) return varchar2;
  function get_issuer return varchar2;
  function get_audience return varchar2;
  function get_scope return varchar2;
end session_api;
/
