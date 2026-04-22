create or replace package body session_api as
  type t_config is record (
    issuer     jwt_scaffold_config.issuer%type,
    audience   jwt_scaffold_config.audience%type,
    scope_name jwt_scaffold_config.scope_name%type
  );

  function get_config return t_config is
    l_config t_config;
  begin
    select issuer,
           audience,
           scope_name
      into l_config
      from jwt_scaffold_config
     where config_id = 1;

    return l_config;
  end get_config;

  function normalize_principal(
    p_current_user in varchar2
  ) return varchar2 is
  begin
    return upper(trim(p_current_user));
  end normalize_principal;

  procedure assert_authenticated(
    p_current_user in varchar2
  ) is
  begin
    if not is_authenticated(p_current_user) then
      raise_application_error(-20001, 'Authenticated session context is required');
    end if;
  end assert_authenticated;

  function is_authenticated(
    p_current_user in varchar2
  ) return boolean is
  begin
    return get_principal(p_current_user) is not null;
  end is_authenticated;

  function get_principal(
    p_current_user in varchar2
  ) return varchar2 is
  begin
    return normalize_principal(p_current_user);
  end get_principal;

  function get_issuer return varchar2 is
    l_config t_config;
  begin
    l_config := get_config;
    return l_config.issuer;
  end get_issuer;

  function get_audience return varchar2 is
    l_config t_config;
  begin
    l_config := get_config;
    return l_config.audience;
  end get_audience;

  function get_scope return varchar2 is
    l_config t_config;
  begin
    l_config := get_config;
    return l_config.scope_name;
  end get_scope;
end session_api;
/
