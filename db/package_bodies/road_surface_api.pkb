create or replace package body road_surface_api as

  function contract_version return varchar2 is
    l_version varchar2(20);
  begin
    select max(contract_version) into l_version from road_contract;
    return nvl(l_version, c_framework_version);
  end contract_version;

  function major_version return varchar2 is
  begin
    return regexp_substr(contract_version, '^[0-9]+');
  end major_version;

  function contract return clob is
    l_doc clob;
  begin
    select document into l_doc from road_contract;
    return l_doc;
  exception
    when no_data_found then
      raise_application_error(c_not_found, 'No contract has been loaded');
  end contract;

  procedure bad_request(p_message in varchar2) is
  begin
    raise_application_error(c_bad_request, p_message);
  end bad_request;

  function natural_key(p_record_id in number, p_read_token in varchar2) return varchar2 is
  begin
    if trim(p_read_token) is null then
      return null;
    end if;
    return to_char(p_record_id) || ':' || upper(trim(p_read_token));
  end natural_key;

  function token_raw(p_read_token in varchar2) return raw is
  begin
    if trim(p_read_token) is null then
      bad_request('read_token is required');
    end if;
    return hextoraw(trim(p_read_token));
  exception
    when value_error or invalid_number then
      bad_request('read_token is not a valid token');
  end token_raw;

  function is_fresh(p_token in raw, p_entity in varchar2, p_id in number,
                    p_updated_at in timestamp with time zone) return boolean is
  begin
    return road_audit_api.check_fresh(
      p_guid               => p_token,
      p_app_schema         => sys_context('USERENV', 'CURRENT_SCHEMA'),
      p_entity_type        => p_entity,
      p_entity_id          => to_char(p_id),
      p_current_updated_at => p_updated_at);
  exception
    when no_data_found then
      return false;
  end is_fresh;

  function is_agent return boolean is
    l_count number;
  begin
    select count(*) into l_count from road_agents where principal_id = road_ctx_pkg.principal_id;
    return l_count > 0;
  end is_agent;

  function new_token(p_endpoint in varchar2) return varchar2 is
  begin
    return rawtohex(road_audit_api.issue_read_token(
      p_caller_type => case when is_agent then 'AGENT' else 'BROWSER' end,
      p_app_schema  => sys_context('USERENV', 'CURRENT_SCHEMA'),
      p_endpoint    => p_endpoint,
      p_caller_ref  => road_ctx_pkg.subject));
  end new_token;

  function iso(p_ts in timestamp with time zone) return varchar2 is
  begin
    return to_char(sys_extract_utc(p_ts), 'YYYY-MM-DD"T"HH24:MI:SS.FF3"Z"');
  end iso;

  function accept(
    p_action_id       in varchar2,
    p_result          in json     default null,
    p_record_ids      in json     default null,
    p_idempotency_key in varchar2 default null
  ) return json is
  begin
    return road_decision_api.accept(p_action_id, contract_version, p_result, p_record_ids,
                                    p_idempotency_key);
  end accept;

  function accept(
    p_action_id       in varchar2,
    p_result_text     in varchar2,
    p_record_ids      in json     default null,
    p_idempotency_key in varchar2 default null
  ) return json is
  begin
    return accept(p_action_id, json(p_result_text), p_record_ids, p_idempotency_key);
  end accept;

  function reject(
    p_action_id       in varchar2,
    p_rejections      in json,
    p_record_ids      in json     default null,
    p_idempotency_key in varchar2 default null
  ) return json is
  begin
    return road_decision_api.reject(p_action_id, contract_version, p_rejections, p_record_ids,
                                    p_idempotency_key);
  end reject;

  function record_not_found(
    p_action_id       in varchar2,
    p_rule_id         in varchar2,
    p_message         in varchar2 default 'No such record.',
    p_idempotency_key in varchar2 default null
  ) return json is
  begin
    return reject(
      p_action_id       => p_action_id,
      p_rejections      => road_decision_api.rejection(p_rule_id, p_message, false),
      p_idempotency_key => p_idempotency_key);
  end record_not_found;

  function envelope(
    p_body          in json,
    p_scope         in varchar2 default c_default_scope,
    p_change_number in number   default null
  ) return clob is
    l_obj json_object_t := json_object_t.parse(json_serialize(p_body returning clob));
  begin
    l_obj.put('contract_version', contract_version);
    l_obj.put('as_at', iso(systimestamp));
    if p_change_number is not null then
      l_obj.put('change_number', p_change_number);
    end if;
    if p_scope is not null then
      l_obj.put('scope', p_scope);
    end if;
    return l_obj.to_clob;
  end envelope;

  function with_version(p_body in clob) return clob is
    l_obj json_object_t;
  begin
    if p_body is null then
      return p_body;
    end if;
    l_obj := json_object_t.parse(p_body);
    l_obj.put('contract_version', contract_version);
    return l_obj.to_clob;
  exception
    when others then
      -- Not a JSON object. Returned as it was: this helper must never turn a response into an error.
      return p_body;
  end with_version;

  procedure respond(p_status in number, p_body in clob) is
    l_len    number := nvl(dbms_lob.getlength(p_body), 0);
    l_offset number := 1;
    c_chunk  constant number := 8000;
  begin
    owa_util.mime_header('application/json', false, 'UTF-8');
    owa_util.status_line(p_status, null, true);
    while l_offset <= l_len loop
      htp.prn(dbms_lob.substr(p_body, c_chunk, l_offset));
      l_offset := l_offset + c_chunk;
    end loop;
  end respond;

  procedure unauthorized is
  begin
    respond(401, json_object('error' value 'UNAUTHORIZED',
                             'message' value 'No session could be established',
                             'contract_version' value contract_version));
  end unauthorized;

  function version_ok(p_accept_version in varchar2) return boolean is
  begin
    if p_accept_version is null or regexp_substr(trim(p_accept_version), '^[0-9]+') = major_version then
      return true;
    end if;
    respond(400, json_object('error' value 'VERSION_MISMATCH',
                             'message' value 'This surface serves contract major version ' || major_version,
                             'contract_version' value contract_version));
    return false;
  end version_ok;

  procedure fail(p_sqlcode in number, p_sqlerrm in varchar2, p_backtrace in varchar2, p_context in varchar2) is
    l_status number;
    l_body   clob;
  begin
    if p_sqlcode in (-40441, -40587, -40834) then
      l_status := 400;
      l_body := json_object('error' value 'VALIDATION_ERROR', 'message' value 'The request body is not valid JSON');
    elsif p_sqlcode between -20999 and -20000 then
      error_api.handle_known(p_sqlcode, p_sqlerrm, l_status, l_body);
    else
      error_api.handle_unknown(p_sqlerrm, p_backtrace, p_context, l_status, l_body);
    end if;
    respond(l_status, with_version(l_body));
  end fail;

end road_surface_api;
/
