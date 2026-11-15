create or replace package body road_agent_api as

  c_bad_request constant number := -20001;
  c_forbidden   constant number := -20403;

  function setting(p_key in varchar2, p_default in varchar2 default null) return varchar2 is
    l_value varchar2(4000);
  begin
    select max(config_value) into l_value from road_config where config_key = p_key;
    return nvl(l_value, p_default);
  end setting;

  function sha256(p_text in varchar2) return varchar2 is
  begin
    return lower(rawtohex(dbms_crypto.hash(utl_i18n.string_to_raw(p_text, 'AL32UTF8'), dbms_crypto.hash_sh256)));
  end sha256;

  function ids(p_a in number, p_b in number default null) return json is
  begin
    return json('[' || p_a || case when p_b is not null then ',' || p_b end || ']');
  end ids;

  function refuse(p_action in varchar2, p_rule in varchar2, p_message in varchar2, p_key in varchar2,
                  p_ids in json default null) return json is
  begin
    return road_decision_api.reject(p_action, c_contract_version,
      road_decision_api.rejection(p_rule, p_message, false, p_ids), p_idempotency_key => p_key);
  end refuse;

  procedure require_key(p_key in varchar2) is
  begin
    if trim(p_key) is null then
      raise_application_error(c_bad_request, 'The Idempotency-Key header is required');
    end if;
  end require_key;

  -- The caller may act on this agent: its owner, or a holder of road.api_key.manage. Null when the
  -- agent does not exist or is not the caller's to see, which callers answer AGENT_NOT_FOUND.
  function agent_row(p_agent_id in number) return road_agents%rowtype is
    l_row road_agents%rowtype;
  begin
    select * into l_row from road_agents where principal_id = p_agent_id;
    if road_ctx_pkg.has_permission('road.api_key.manage')
       or l_row.owner_principal_id = road_ctx_pkg.principal_id then
      return l_row;
    end if;
    return null;
  exception
    when no_data_found then
      return null;
  end agent_row;

  procedure require_agents_access is
  begin
    if not (road_ctx_pkg.has_permission('road.agent.self_serve') or road_ctx_pkg.has_permission('road.api_key.manage')) then
      raise_application_error(c_forbidden, 'You may not manage agents');
    end if;
  end require_agents_access;

  function create_agent(p_body in json, p_idempotency_key in varchar2) return json is
    l_key    varchar2(400) := trim(p_idempotency_key);
    l_name   varchar2(4000) := trim(json_value(p_body, '$.display_name'));
    l_shared boolean := json_value(p_body, '$.shared') = 'true';
    l_role   varchar2(64) := setting('agents.role');
    l_limit  number := to_number(setting('agents.limit_per_owner', '5'));
    l_owner  number := road_ctx_pkg.principal_id;
    l_prior  json;
    l_count  number;
    l_issuer varchar2(1024);
    l_id     number;
  begin
    if l_shared then
      road_ctx_pkg.require_permission('road.api_key.manage');
      l_owner := null;
    else
      road_ctx_pkg.require_permission('road.agent.self_serve');
    end if;
    require_key(l_key);
    if l_role is null then
      raise_application_error(c_forbidden, 'Agents are not enabled: road_config agents.role is not set');
    end if;
    if l_name is null or length(l_name) > 80 then
      raise_application_error(c_bad_request, 'display_name is required, up to 80 characters');
    end if;
    l_prior := road_decision_api.prior_outcome(c_create_agent, l_key);
    if l_prior is not null then
      return l_prior;
    end if;
    savepoint create_agent;
    if l_owner is not null then
      select count(*) into l_count
        from road_agents a join road_principals p on p.principal_id = a.principal_id
       where a.owner_principal_id = l_owner and p.status = 'ACTIVE';
      if l_count >= l_limit then
        rollback to savepoint create_agent;
        return refuse(c_create_agent, 'AGENT_LIMIT_REACHED',
          'You already have ' || l_count || ' agents, the most allowed. Retire one first.', l_key);
      end if;
    end if;
    -- Its own principal, in the issuer the scaffold signs tokens with, so a token for it maps back
    -- to it. The subject is AGENT_<id>, issued here; the person chooses only the display name.
    select max(issuer) into l_issuer from jwt_scaffold_config;
    insert into road_principals (issuer, subject, display_name)
    values (l_issuer, 'AGENT_PENDING_' || rawtohex(sys_guid()), l_name)
    returning principal_id into l_id;
    update road_principals set subject = 'AGENT_' || l_id where principal_id = l_id;
    insert into road_agents (principal_id, owner_principal_id, created_by)
    values (l_id, l_owner, road_ctx_pkg.principal_id);
    insert into road_principal_roles (principal_id, role_name, granted_by)
    values (l_id, l_role, road_ctx_pkg.principal_id);
    return road_decision_api.accept(c_create_agent, c_contract_version,
      json(json_object('agent_id' value l_id, 'subject' value 'AGENT_' || l_id, 'display_name' value l_name,
                       'shared' value case when l_owner is null then 'true' else 'false' end format json)),
      ids(l_id), l_key);
  exception
    when dup_val_on_index then
      rollback to savepoint create_agent;
      return road_decision_api.prior_outcome(c_create_agent, l_key);
  end create_agent;

  function retire_agent(p_agent_id in number, p_idempotency_key in varchar2) return json is
    l_key   varchar2(400) := trim(p_idempotency_key);
    l_prior json;
    l_row   road_agents%rowtype;
  begin
    require_agents_access;
    require_key(l_key);
    l_prior := road_decision_api.prior_outcome(c_retire_agent, l_key);
    if l_prior is not null then
      return l_prior;
    end if;
    savepoint retire_agent;
    l_row := agent_row(p_agent_id);
    if l_row.principal_id is null then
      rollback to savepoint retire_agent;
      return refuse(c_retire_agent, 'AGENT_NOT_FOUND', 'You have no agent with this id.', l_key);
    end if;
    update road_api_keys set revoked_at = systimestamp, revoked_by = road_ctx_pkg.principal_id
     where principal_id = p_agent_id and revoked_at is null;
    update road_principals set status = 'RETIRED', updated_at = systimestamp where principal_id = p_agent_id;
    return road_decision_api.accept(c_retire_agent, c_contract_version,
      json(json_object('agent_id' value p_agent_id)), ids(p_agent_id), l_key);
  exception
    when dup_val_on_index then
      rollback to savepoint retire_agent;
      return road_decision_api.prior_outcome(c_retire_agent, l_key);
  end retire_agent;

  function create_key(p_agent_id in number, p_body in json, p_idempotency_key in varchar2) return json is
    l_key     varchar2(400) := trim(p_idempotency_key);
    l_name    varchar2(4000) := trim(json_value(p_body, '$.name'));
    l_expires timestamp with time zone;
    l_prior   json;
    l_row     road_agents%rowtype;
    l_status  varchar2(20);
    l_secret  varchar2(100);
    l_hash    varchar2(64);
    l_id      number;
    l_out     json_object_t;
    l_result  json_object_t;
  begin
    require_agents_access;
    require_key(l_key);
    if l_name is null or length(l_name) > 80 then
      raise_application_error(c_bad_request, 'name is required, up to 80 characters: where the key will be used');
    end if;
    if json_value(p_body, '$.expires_at') is not null then
      begin
        l_expires := to_timestamp_tz(json_value(p_body, '$.expires_at'), 'YYYY-MM-DD"T"HH24:MI:SS.FFTZH:TZM');
      exception
        when others then
          raise_application_error(c_bad_request, 'expires_at must be an ISO 8601 time with its offset');
      end;
    end if;
    l_prior := road_decision_api.prior_outcome(c_create_key, l_key);
    if l_prior is not null then
      return l_prior;
    end if;
    savepoint create_key;
    l_row := agent_row(p_agent_id);
    if l_row.principal_id is null then
      rollback to savepoint create_key;
      return refuse(c_create_key, 'AGENT_NOT_FOUND', 'You have no agent with this id.', l_key);
    end if;
    select status into l_status from road_principals where principal_id = p_agent_id;
    if l_status != 'ACTIVE' then
      rollback to savepoint create_key;
      return refuse(c_create_key, 'AGENT_RETIRED', 'The agent is retired.', l_key, ids(p_agent_id));
    end if;
    -- 192 random bits as 48 hex characters, after the application's prefix.
    l_secret := setting('api_keys.prefix', 'rk') || '_' || lower(rawtohex(dbms_crypto.randombytes(24)));
    l_hash := sha256(l_secret);
    insert into road_api_keys (principal_id, name, key_prefix, key_hash, created_by, expires_at)
    values (p_agent_id, l_name, substr(l_secret, 1, 12), l_hash, road_ctx_pkg.principal_id, l_expires)
    returning key_id into l_id;
    l_out := json_object_t(json_serialize(road_decision_api.accept(c_create_key, c_contract_version,
      json(json_object('key_id' value l_id, 'agent_id' value p_agent_id, 'name' value l_name,
                       'key_prefix' value substr(l_secret, 1, 12))),
      ids(p_agent_id, l_id), l_key)));
    -- Added only to this answer, after accept has recorded the decision without it.
    l_result := l_out.get_object('result');
    l_result.put('api_key', l_secret);
    return json(l_out.to_clob);
  exception
    when dup_val_on_index then
      rollback to savepoint create_key;
      return road_decision_api.prior_outcome(c_create_key, l_key);
  end create_key;

  function revoke_key(p_agent_id in number, p_key_id in number, p_idempotency_key in varchar2) return json is
    l_key   varchar2(400) := trim(p_idempotency_key);
    l_prior json;
    l_row   road_agents%rowtype;
  begin
    require_agents_access;
    require_key(l_key);
    l_prior := road_decision_api.prior_outcome(c_delete_key, l_key);
    if l_prior is not null then
      return l_prior;
    end if;
    savepoint revoke_key;
    l_row := agent_row(p_agent_id);
    if l_row.principal_id is null then
      rollback to savepoint revoke_key;
      return refuse(c_delete_key, 'AGENT_NOT_FOUND', 'You have no agent with this id.', l_key);
    end if;
    update road_api_keys set revoked_at = systimestamp, revoked_by = road_ctx_pkg.principal_id
     where key_id = p_key_id and principal_id = p_agent_id and revoked_at is null;
    if sql%rowcount = 0 then
      rollback to savepoint revoke_key;
      return refuse(c_delete_key, 'API_KEY_NOT_FOUND', 'The agent has no current key with this id.', l_key, ids(p_agent_id));
    end if;
    return road_decision_api.accept(c_delete_key, c_contract_version,
      json(json_object('key_id' value p_key_id)), ids(p_agent_id, p_key_id), l_key);
  exception
    when dup_val_on_index then
      rollback to savepoint revoke_key;
      return road_decision_api.prior_outcome(c_delete_key, l_key);
  end revoke_key;

  function list_agents(p_all in varchar2 default null) return clob is
    -- A number, not a boolean, for use in SQL.
    l_all  number := case when lower(p_all) = 'true' then 1 else 0 end;
    l_list clob;
    l_obj  json_object_t := json_object_t();
  begin
    require_agents_access;
    if l_all = 1 then
      road_ctx_pkg.require_permission('road.api_key.manage');
    end if;
    select json_arrayagg(
             json_object(
               'agent_id' value a.principal_id, 'subject' value p.subject, 'display_name' value p.display_name,
               'status' value p.status, 'owner' value o.display_name, 'created_at' value to_char(sys_extract_utc(a.created_at), 'YYYY-MM-DD"T"HH24:MI:SS.FF3"Z"'),
               'keys' value (select json_arrayagg(
                                      json_object('key_id' value k.key_id, 'name' value k.name, 'key_prefix' value k.key_prefix,
                                                  'created_at' value to_char(sys_extract_utc(k.created_at), 'YYYY-MM-DD"T"HH24:MI:SS.FF3"Z"'), 'last_used_at' value to_char(sys_extract_utc(k.last_used_at), 'YYYY-MM-DD"T"HH24:MI:SS.FF3"Z"'),
                                                  'expires_at' value to_char(sys_extract_utc(k.expires_at), 'YYYY-MM-DD"T"HH24:MI:SS.FF3"Z"'), 'revoked_at' value to_char(sys_extract_utc(k.revoked_at), 'YYYY-MM-DD"T"HH24:MI:SS.FF3"Z"'))
                                      order by k.key_id desc returning clob)
                               from road_api_keys k where k.principal_id = a.principal_id) format json
               returning clob)
             order by p.status, p.display_name returning clob)
      into l_list
      from road_agents a
      join road_principals p on p.principal_id = a.principal_id
      left join road_principals o on o.principal_id = a.owner_principal_id
     where l_all = 1 or a.owner_principal_id = road_ctx_pkg.principal_id;
    l_obj.put('agents', json_array_t(nvl(l_list, '[]')));
    l_obj.put('self_serve', setting('agents.role') is not null);
    return l_obj.to_clob;
  end list_agents;

  procedure exchange(p_body in clob, p_status out number, p_response out clob) is
    l_secret  varchar2(4000);
    l_hash    varchar2(64);
    l_key_id  number;
    l_agent   number;
    l_subject varchar2(255);
    l_minutes number := to_number(setting('api_keys.token_minutes', '15'));
  begin
    begin
      l_secret := trim(json_value(p_body, '$.api_key'));
    exception
      when others then
        l_secret := null;
    end;
    if l_secret is null then
      p_status := 400;
      p_response := json_object('error' value 'invalid_request', 'message' value 'Send {"api_key": "..."}');
      return;
    end if;
    -- Hashed here: a package's private function cannot be called inside SQL (PLS-00231).
    l_hash := sha256(l_secret);
    begin
      select k.key_id, p.principal_id, p.subject into l_key_id, l_agent, l_subject
        from road_api_keys k
        join road_agents a on a.principal_id = k.principal_id
        join road_principals p on p.principal_id = a.principal_id
        left join road_principals o on o.principal_id = a.owner_principal_id
       where k.key_hash = l_hash
         and k.revoked_at is null
         and (k.expires_at is null or k.expires_at > systimestamp)
         and p.status = 'ACTIVE'
         and (a.owner_principal_id is null or o.status = 'ACTIVE');
    exception
      when no_data_found then
        p_status := 401;
        p_response := json_object('error' value 'invalid_key', 'message' value 'The key is unknown, revoked or expired, or its agent is not active.');
        return;
    end;
    update road_api_keys set last_used_at = systimestamp where key_id = l_key_id;
    p_status := 200;
    -- The token's scope is the agent's own permissions, as for a person's login.
    p_response := json_object('access_token' value jwt_scaffold_auth_api.issue_token(
                                p_username => l_subject, p_scope => road_ctx_pkg.effective_ords_scope(l_agent),
                                p_ttl_minutes => l_minutes),
                              'token_type' value 'Bearer', 'expires_in' value l_minutes * 60,
                              'subject' value l_subject);
  end exchange;

end road_agent_api;
/
