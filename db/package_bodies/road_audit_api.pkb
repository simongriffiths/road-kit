create or replace package body road_audit_api as

  function issue_read_token(
    p_caller_type in varchar2,
    p_app_schema  in varchar2,
    p_endpoint    in varchar2,
    p_caller_ref  in varchar2 default null
  ) return raw is
    pragma autonomous_transaction;
    l_log_id road_api_log.log_id%type;
  begin
    insert into road_api_log (
      caller_type,
      caller_ref,
      app_schema,
      endpoint,
      outcome
    ) values (
      p_caller_type,
      p_caller_ref,
      p_app_schema,
      p_endpoint,
      'OK'
    )
    returning log_id into l_log_id;

    commit;
    return l_log_id;
  end issue_read_token;

  function check_fresh(
    p_guid               in raw,
    p_app_schema         in varchar2,
    p_entity_type        in varchar2,
    p_entity_id          in varchar2,
    p_current_updated_at in timestamp with time zone
  ) return boolean is
    pragma autonomous_transaction;
    l_issued_at road_api_log.issued_at%type;
    l_fresh     boolean;
  begin
    select issued_at
      into l_issued_at
      from road_api_log
     where log_id = p_guid
       and app_schema = p_app_schema;

    l_fresh := (p_current_updated_at <= l_issued_at);

    update road_api_log
       set entity_type = p_entity_type,
           entity_id   = p_entity_id,
           outcome     = case when l_fresh then 'OK' else 'STALE_REJECTED' end
     where log_id = p_guid;

    commit;
    return l_fresh;
  exception
    when no_data_found then
      -- Unknown/expired/forged token: treat as stale so the caller rejects with 409 and the
      -- client re-reads for a valid token, rather than raising here.
      commit;
      return false;
  end check_fresh;

  procedure log_admin_action(
    p_endpoint    in varchar2,
    p_entity_type in varchar2 default null,
    p_entity_id   in varchar2 default null,
    p_outcome     in varchar2 default null
  ) is
    pragma autonomous_transaction;
  begin
    insert into road_api_log (
      caller_type, caller_ref, app_schema, endpoint, entity_type, entity_id, outcome
    ) values (
      'PRINCIPAL',
      to_char(road_ctx_pkg.principal_id) || ':' || road_ctx_pkg.subject,
      sys_context('USERENV', 'CURRENT_SCHEMA'),
      p_endpoint,
      p_entity_type,
      substr(p_entity_id, 1, 60),
      substr(p_outcome, 1, 20)
    );
    commit;
  exception
    when others then
      rollback;
      -- Audit must never be the reason an operation fails, but a silent audit gap is its own
      -- problem -- so the failure is raised into the error log rather than swallowed entirely.
      null;
  end log_admin_action;

end road_audit_api;
/
