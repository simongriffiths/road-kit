create or replace package body road_agent_api_test as

  c_issuer constant varchar2(64) := 'urn:road:test:road_agent';
  g_pass number := 0;
  g_fail number := 0;
  g_seq  number := 0;

  procedure assert_eq(p_label in varchar2, p_expected in varchar2, p_actual in varchar2) is
  begin
    if nvl(p_actual, '<null>') != nvl(p_expected, '<null>') then
      raise_application_error(-20000, p_label || ': expected [' || p_expected || '] got [' || p_actual || ']');
    end if;
  end assert_eq;

  procedure assert_true(p_label in varchar2, p_cond in boolean) is
  begin
    if not nvl(p_cond, false) then
      raise_application_error(-20000, p_label || ': expected true');
    end if;
  end assert_true;

  function key return varchar2 is
  begin
    g_seq := g_seq + 1;
    return 'agent-test-' || to_char(systimestamp, 'FF6') || '-' || g_seq;
  end key;

  function decision(p_out in json) return varchar2 is begin return json_value(p_out, '$.decision'); end;
  function rule(p_out in json) return varchar2 is begin return json_value(p_out, '$.rejections[0].rule_id'); end;

  function raises(p_code in number, p_block in varchar2) return boolean is
  begin
    execute immediate 'declare x json; c clob; s number; begin ' || p_block || ' end;';
    return false;
  exception
    when others then
      return sqlcode = p_code;
  end raises;

  procedure be(p_subject in varchar2) is
  begin
    road_ctx_pkg.end_request;
    if not road_ctx_pkg.begin_request(p_subject, c_issuer) then
      raise_application_error(-20000, 'could not begin a request as ' || p_subject);
    end if;
  end be;

  function principal_of(p_subject in varchar2) return number is
    l_id number;
  begin
    select principal_id into l_id from road_principals where issuer = c_issuer and subject = p_subject;
    return l_id;
  end principal_of;

  procedure set_config(p_key in varchar2, p_value in varchar2) is
  begin
    update road_config set config_value = p_value where config_key = p_key;
    if sql%rowcount = 0 then
      insert into road_config (config_key, config_value, description) values (p_key, p_value, 'test');
    end if;
  end set_config;

  -- OWNER and OTHER may make their own agents; MANAGER holds road.api_key.manage; PLAIN neither.
  -- Agents hold test.agent_role. All inside the test's savepoint.
  procedure fixtures is
    l_owner   number;
    l_other   number;
    l_manager number;
  begin
    for s in (select column_value subject from table(sys.odcivarchar2list('OWNER', 'OTHER', 'MANAGER', 'PLAIN'))) loop
      insert into road_principals (issuer, subject, display_name, status) values (c_issuer, s.subject, 'Agent test ' || s.subject, 'ACTIVE');
    end loop;
    insert into road_roles (role_name, display_name, is_reserved) values ('test.agent_role', 'Agent test agents', 'N');
    insert into road_roles (role_name, display_name, is_reserved) values ('test.agent_user', 'Agent test people', 'N');
    insert into road_role_permissions (role_name, permission_name) values ('test.agent_user', 'road.agent.self_serve');
    insert into road_role_permissions (role_name, permission_name) values ('test.agent_user', 'road.agents.rw');
    insert into road_role_permissions (role_name, permission_name) values ('test.agent_role', 'session.me.read');
    -- In variables: a package's private function cannot be called inside SQL (PLS-00231).
    l_owner := principal_of('OWNER');
    l_other := principal_of('OTHER');
    l_manager := principal_of('MANAGER');
    insert into road_principal_roles (principal_id, role_name) values (l_owner, 'test.agent_user');
    insert into road_principal_roles (principal_id, role_name) values (l_other, 'test.agent_user');
    insert into road_principal_roles (principal_id, role_name) values (l_manager, 'road.system_admin');
    set_config('agents.role', 'test.agent_role');
    set_config('agents.limit_per_owner', '5');
    set_config('api_keys.prefix', 'tk');
  end fixtures;

  function make_agent(p_name in varchar2 default 'My Claude Code') return number is
    l_out json;
  begin
    l_out := road_agent_api.create_agent(json('{"display_name":"' || p_name || '"}'), key);
    if decision(l_out) != 'accepted' then
      raise_application_error(-20000, 'fixture agent not made: ' || json_serialize(l_out));
    end if;
    return json_value(l_out, '$.result.agent_id' returning number);
  end make_agent;

  function make_key(p_agent in number, p_k in varchar2 default null) return json is
  begin
    return road_agent_api.create_key(p_agent, json('{"name":"Test laptop"}'), nvl(p_k, key));
  end make_key;

  procedure exchange(p_secret in varchar2, p_status out number, p_body out clob) is
  begin
    road_ctx_pkg.end_request;
    road_agent_api.exchange('{"api_key":"' || p_secret || '"}', p_status, p_body);
  end exchange;

  -- ---------------------------------------------------------------------------------------------

  procedure test_self_serve_off is
  begin
    set_config('agents.role', null);
    be('OWNER');
    assert_true('no agent role, no agents', raises(-20403, 'x := road_agent_api.create_agent(json(''{"display_name":"x"}''), ''k'');'));
  end test_self_serve_off;

  procedure test_person_makes_an_agent is
    l_agent number;
    l_n     number;
    l_owner number;
  begin
    be('OWNER');
    l_agent := make_agent('Simon''s Claude Code');
    select count(*) into l_n from road_principals where principal_id = l_agent and subject = 'AGENT_' || l_agent and status = 'ACTIVE';
    assert_eq('a principal of its own, AGENT_<id>', '1', to_char(l_n));
    select owner_principal_id into l_owner from road_agents where principal_id = l_agent;
    assert_eq('owned by its maker', to_char(principal_of('OWNER')), to_char(l_owner));
    select count(*) into l_n from road_principal_roles where principal_id = l_agent;
    assert_eq('one role', '1', to_char(l_n));
    select count(*) into l_n from road_principal_roles where principal_id = l_agent and role_name = 'test.agent_role';
    assert_eq('the agent role, never its owner''s', '1', to_char(l_n));
    assert_true('in My agents', instr(road_agent_api.list_agents, 'Simon''s Claude Code') > 0);
  end test_person_makes_an_agent;

  procedure test_limit_per_owner is
    l_out json;
    l_a   number;
  begin
    set_config('agents.limit_per_owner', '2');
    be('OWNER');
    l_a := make_agent('One');
    l_a := make_agent('Two');
    l_out := road_agent_api.create_agent(json('{"display_name":"Three"}'), key);
    assert_eq('at the limit', 'AGENT_LIMIT_REACHED', rule(l_out));
    l_out := road_agent_api.retire_agent(l_a, key);
    assert_eq('retired', 'accepted', decision(l_out));
    l_a := make_agent('Three');
    assert_true('a retired agent does not count', l_a is not null);
  end test_limit_per_owner;

  procedure test_key_shown_once is
    l_agent  number;
    l_k      varchar2(100) := key;
    l_out    json;
    l_secret varchar2(100);
    l_n      number;
  begin
    be('OWNER');
    l_agent := make_agent;
    l_out := make_key(l_agent, l_k);
    assert_eq('made', 'accepted', decision(l_out));
    l_secret := json_value(l_out, '$.result.api_key');
    assert_true('the application''s prefix and 48 hex', regexp_like(l_secret, '^tk_[0-9a-f]{48}$'));
    select count(*) into l_n from road_decisions
     where idempotency_key = l_k and (json_serialize(result) like '%' || l_secret || '%' or json_serialize(result) like '%api_key%');
    assert_eq('the decision record does not hold it', '0', to_char(l_n));
    select count(*) into l_n from road_api_keys
     where principal_id = l_agent and key_prefix = substr(l_secret, 1, 12) and key_hash != l_secret and length(key_hash) = 64;
    assert_eq('only a hash is stored', '1', to_char(l_n));
    l_out := make_key(l_agent, l_k);
    assert_true('a replay does not show it again', json_value(l_out, '$.result.api_key') is null and decision(l_out) = 'accepted');
    assert_true('the list never shows a key', instr(road_agent_api.list_agents, l_secret) = 0);
  end test_key_shown_once;

  procedure test_others_cannot_touch_it is
    l_agent number;
    l_key   number;
    l_out   json;
  begin
    be('OWNER');
    l_agent := make_agent;
    l_key := json_value(make_key(l_agent), '$.result.key_id' returning number);
    be('OTHER');
    assert_eq('not in their list', '0', to_char(json_object_t.parse(road_agent_api.list_agents).get_array('agents').get_size));
    assert_eq('no key for it', 'AGENT_NOT_FOUND', rule(make_key(l_agent)));
    assert_eq('no revoking', 'AGENT_NOT_FOUND', rule(road_agent_api.revoke_key(l_agent, l_key, key)));
    assert_eq('no retiring', 'AGENT_NOT_FOUND', rule(road_agent_api.retire_agent(l_agent, key)));
    assert_true('not all agents', raises(-20403, 'c := road_agent_api.list_agents(''true'');'));
    be('PLAIN');
    assert_true('no self-serve, no agents page', raises(-20403, 'c := road_agent_api.list_agents;'));
    be('MANAGER');
    assert_true('the manager sees it', instr(road_agent_api.list_agents('true'), 'AGENT_' || l_agent) > 0);
    l_out := road_agent_api.revoke_key(l_agent, l_key, key);
    assert_eq('and revokes its key', 'accepted', decision(l_out));
    assert_eq('once', 'API_KEY_NOT_FOUND', rule(road_agent_api.revoke_key(l_agent, l_key, key)));
  end test_others_cannot_touch_it;

  procedure test_shared_agents is
    l_out   json;
    l_owner number;
  begin
    be('OWNER');
    assert_true('only a manager makes a shared agent',
      raises(-20403, 'x := road_agent_api.create_agent(json(''{"display_name":"CI","shared":true}''), ''k'');'));
    be('MANAGER');
    l_out := road_agent_api.create_agent(json('{"display_name":"CI bot","shared":true}'), key);
    assert_eq('shared', 'accepted', decision(l_out));
    select owner_principal_id into l_owner from road_agents where principal_id = json_value(l_out, '$.result.agent_id' returning number);
    assert_eq('with no owner', null, to_char(l_owner));
  end test_shared_agents;

  procedure test_exchange is
    l_agent  number;
    l_out    json;
    l_secret varchar2(100);
    l_status number;
    l_body   clob;
    l_n      number;
    l_owner  number := principal_of('OWNER');
  begin
    be('OWNER');
    l_agent := make_agent;
    l_out := make_key(l_agent);
    l_secret := json_value(l_out, '$.result.api_key');
    exchange(l_secret, l_status, l_body);
    assert_eq('the key buys a token', '200', to_char(l_status));
    assert_eq('for the agent', 'AGENT_' || l_agent, json_value(l_body, '$.subject'));
    assert_eq('for 15 minutes', '900', json_value(l_body, '$.expires_in'));
    assert_true('a token', length(json_value(l_body, '$.access_token')) > 100);
    select count(*) into l_n from road_api_keys where principal_id = l_agent and last_used_at is not null;
    assert_eq('last use recorded', '1', to_char(l_n));
    exchange('tk_' || rpad('0', 48, '0'), l_status, l_body);
    assert_eq('a wrong key', '401', to_char(l_status));
    road_agent_api.exchange('{}', l_status, l_body);
    assert_eq('no key', '400', to_char(l_status));

    update road_principals set status = 'SUSPENDED' where principal_id = l_owner;
    exchange(l_secret, l_status, l_body);
    assert_eq('a suspended owner stops the agent', '401', to_char(l_status));
    update road_principals set status = 'ACTIVE' where principal_id = l_owner;

    update road_api_keys set expires_at = systimestamp - interval '1' minute where principal_id = l_agent;
    exchange(l_secret, l_status, l_body);
    assert_eq('an expired key', '401', to_char(l_status));
    update road_api_keys set expires_at = null where principal_id = l_agent;

    be('OWNER');
    l_out := road_agent_api.retire_agent(l_agent, key);
    assert_eq('retired', 'accepted', decision(l_out));
    select count(*) into l_n from road_api_keys where principal_id = l_agent and revoked_at is null;
    assert_eq('its keys are revoked', '0', to_char(l_n));
    exchange(l_secret, l_status, l_body);
    assert_eq('a retired agent''s key', '401', to_char(l_status));
    be('OWNER');
    assert_eq('no new key for a retired agent', 'AGENT_RETIRED', rule(make_key(l_agent)));
  end test_exchange;

  procedure test_wrong_calls is
    l_agent number;
  begin
    be('OWNER');
    l_agent := make_agent;
    assert_true('no Idempotency-Key', raises(-20001, 'x := road_agent_api.create_key(' || l_agent || ', json(''{"name":"x"}''), null);'));
    assert_true('no name', raises(-20001, 'x := road_agent_api.create_key(' || l_agent || ', json(''{}''), ''k'');'));
    assert_true('a bad expiry', raises(-20001, 'x := road_agent_api.create_key(' || l_agent || ', json(''{"name":"x","expires_at":"soon"}''), ''k'');'));
    assert_true('no display name', raises(-20001, 'x := road_agent_api.create_agent(json(''{}''), ''k'');'));
  end test_wrong_calls;

  -- ---------------------------------------------------------------------------------------------

  procedure run(p_name in varchar2) is
  begin
    savepoint agent_test;
    fixtures;
    -- Called directly, as road-kit's other test packages do: the tests are not in the spec.
    case p_name
      when 'test_self_serve_off'         then test_self_serve_off;
      when 'test_person_makes_an_agent'  then test_person_makes_an_agent;
      when 'test_limit_per_owner'        then test_limit_per_owner;
      when 'test_key_shown_once'         then test_key_shown_once;
      when 'test_others_cannot_touch_it' then test_others_cannot_touch_it;
      when 'test_shared_agents'          then test_shared_agents;
      when 'test_exchange'               then test_exchange;
      when 'test_wrong_calls'            then test_wrong_calls;
    end case;
    rollback to savepoint agent_test;
    road_ctx_pkg.end_request;
    dbms_output.put_line('PASS ' || p_name);
    g_pass := g_pass + 1;
  exception
    when others then
      rollback to savepoint agent_test;
      road_ctx_pkg.end_request;
      dbms_output.put_line('FAIL ' || p_name || ': ' || sqlerrm);
      g_fail := g_fail + 1;
  end run;

  procedure run_all is
  begin
    execute immediate 'alter session disable parallel dml';
    g_pass := 0;
    g_fail := 0;
    for t in (select column_value name from table(sys.odcivarchar2list(
                'test_self_serve_off', 'test_person_makes_an_agent', 'test_limit_per_owner',
                'test_key_shown_once', 'test_others_cannot_touch_it', 'test_shared_agents',
                'test_exchange', 'test_wrong_calls'))) loop
      run(t.name);
    end loop;
    -- Rejections are recorded autonomously and outlive the rollback; their principals do not.
    delete from road_decisions
     where principal_id is not null
       and principal_id not in (select principal_id from road_principals);
    commit;
    dbms_output.put_line('road_agent_api_test: ' || g_pass || ' passed, ' || g_fail || ' failed');
    if g_fail > 0 then
      raise_application_error(-20000, g_fail || ' road_agent_api test(s) failed');
    end if;
  end run_all;

end road_agent_api_test;
/
