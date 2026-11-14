create or replace package body road_decision_api as

  procedure misuse(p_message in varchar2) is
  begin
    raise_application_error(c_misuse, 'road_decision_api: ' || p_message);
  end misuse;

  -- json_element_t.parse has no overload for the native JSON type on 26ai (PLS-00306), so a
  -- JSON value is serialised through SQL first.
  function to_element(p_json in json) return json_element_t is
    l_text clob;
  begin
    select json_serialize(p_json returning clob) into l_text from dual;
    return json_element_t.parse(l_text);
  end to_element;

  -- The one place the outcome shape is built, for a new decision and for a replay alike.
  function outcome(
    p_contract_version in varchar2,
    p_reported         in varchar2,
    p_result           in json,
    p_rejections       in json,
    p_audit_id         in number
  ) return json is
    l_out json_object_t := json_object_t();
  begin
    l_out.put('contract_version', p_contract_version);
    l_out.put('decision', p_reported);
    if p_reported = c_accepted then
      if p_result is null then
        l_out.put('result', json_object_t());
      else
        l_out.put('result', to_element(p_result));
      end if;
    else
      l_out.put('rejections', to_element(p_rejections));
    end if;
    l_out.put('audit_id', p_audit_id);
    return l_out.to_json;
  end outcome;

  -- Accepts one rejection object or an array of them, and checks each carries what GSC 6.4.2
  -- requires. Returns them as an array.
  function rejection_array(p_rejections in json) return json is
    l_el  json_element_t;
    l_arr json_array_t;
    l_obj json_object_t;
  begin
    if p_rejections is null then
      misuse('a rejected decision needs at least one rejection');
    end if;

    l_el := to_element(p_rejections);
    if l_el.is_array then
      l_arr := treat(l_el as json_array_t);
    elsif l_el.is_object then
      l_arr := json_array_t();
      l_arr.append(l_el);
    else
      misuse('rejections must be an object or an array of objects');
    end if;

    if l_arr.get_size = 0 then
      misuse('a rejected decision needs at least one rejection');
    end if;

    for i in 0 .. l_arr.get_size - 1 loop
      if not l_arr.get(i).is_object then
        misuse('rejection ' || i || ' is not an object');
      end if;
      l_obj := treat(l_arr.get(i) as json_object_t);
      if l_obj.get_string('rule_id') is null then
        misuse('rejection ' || i || ' has no rule_id');
      end if;
      if l_obj.get_string('message') is null then
        misuse('rejection ' || i || ' has no message');
      end if;
      if not l_obj.has('retryable') or not l_obj.get('retryable').is_boolean then
        misuse('rejection ' || i || ' has no boolean retryable');
      end if;
    end loop;

    return l_arr.to_json;
  end rejection_array;

  function rejection(
    p_rule_id   in varchar2,
    p_message   in varchar2,
    p_retryable in boolean,
    p_ids       in json default null
  ) return json is
    l_obj json_object_t := json_object_t();
  begin
    if p_rule_id is null or p_message is null or p_retryable is null then
      misuse('rejection needs a rule_id, a message and retryable');
    end if;
    l_obj.put('rule_id', p_rule_id);
    l_obj.put('message', p_message);
    l_obj.put('retryable', p_retryable);
    if p_ids is not null then
      l_obj.put('ids', to_element(p_ids));
    end if;
    return l_obj.to_json;
  end rejection;

  function accept(
    p_action_id        in varchar2,
    p_contract_version in varchar2,
    p_result           in json default null,
    p_record_ids       in json default null,
    p_idempotency_key  in varchar2 default null
  ) return json is
    l_id        number;
    l_principal number := road_ctx_pkg.principal_id;
  begin
    if p_action_id is null or p_contract_version is null then
      misuse('accept needs an action id and a contract version');
    end if;

    insert into road_decisions (
      principal_id, action_id, contract_version, decision, disclosed,
      idempotency_key, record_ids, result
    ) values (
      l_principal, p_action_id, p_contract_version, c_accepted, true,
      p_idempotency_key, p_record_ids, p_result
    )
    returning decision_id into l_id;

    return outcome(p_contract_version, c_accepted, p_result, null, l_id);
  end accept;

  -- Autonomous: the record of a rejection must survive the rollback of the rejected change
  -- (GSC definition section 6.7.4; ledger D-05).
  --
  -- Unlike road_audit_api.log_admin_action this does NOT swallow its own failure. The record is
  -- part of the decision; if it cannot be written, no decision is returned, and the handler's
  -- error_api.handle_unknown answers 500.
  function write_rejection(
    p_action_id        in varchar2,
    p_contract_version in varchar2,
    p_disclosed        in boolean,
    p_idempotency_key  in varchar2,
    p_record_ids       in json,
    p_result           in json,
    p_rejections       in json
  ) return number is
    pragma autonomous_transaction;
    l_id        number;
    l_principal number := road_ctx_pkg.principal_id;
  begin
    insert into road_decisions (
      principal_id, action_id, contract_version, decision, disclosed,
      idempotency_key, record_ids, result, rejections
    ) values (
      l_principal, p_action_id, p_contract_version, c_rejected, p_disclosed,
      p_idempotency_key, p_record_ids, p_result, p_rejections
    )
    returning decision_id into l_id;
    commit;
    return l_id;
  exception
    when others then
      rollback;
      raise;
  end write_rejection;

  function reject(
    p_action_id        in varchar2,
    p_contract_version in varchar2,
    p_rejections       in json,
    p_record_ids       in json default null,
    p_idempotency_key  in varchar2 default null
  ) return json is
    l_rejections json;
    l_id         number;
  begin
    if p_action_id is null or p_contract_version is null then
      misuse('reject needs an action id and a contract version');
    end if;
    l_rejections := rejection_array(p_rejections);
    l_id := write_rejection(p_action_id, p_contract_version, true, p_idempotency_key,
                            p_record_ids, null, l_rejections);
    return outcome(p_contract_version, c_rejected, null, l_rejections, l_id);
  end reject;

  function reject_undisclosed(
    p_action_id        in varchar2,
    p_contract_version in varchar2,
    p_rejections       in json,
    p_reported_result  in json default null,
    p_record_ids       in json default null,
    p_idempotency_key  in varchar2 default null
  ) return json is
    l_rejections json;
    l_id         number;
  begin
    if p_action_id is null or p_contract_version is null then
      misuse('reject_undisclosed needs an action id and a contract version');
    end if;
    l_rejections := rejection_array(p_rejections);
    l_id := write_rejection(p_action_id, p_contract_version, false, p_idempotency_key,
                            p_record_ids, p_reported_result, l_rejections);
    return outcome(p_contract_version, c_accepted, p_reported_result, null, l_id);
  end reject_undisclosed;

  function prior_outcome(
    p_action_id         in varchar2,
    p_idempotency_key   in varchar2,
    p_replay_rejections in boolean default false
  ) return json is
    l_principal  number := road_ctx_pkg.principal_id;
    l_any        varchar2(1) := case when p_replay_rejections then 'Y' else 'N' end;
    l_decision   road_decisions.decision%type;
    l_disclosed  boolean;
    l_version    road_decisions.contract_version%type;
    l_result     json;
    l_rejections json;
    l_id         number;
  begin
    if p_action_id is null or p_idempotency_key is null then
      return null;
    end if;

    select decision, disclosed, contract_version, result, rejections, decision_id
      into l_decision, l_disclosed, l_version, l_result, l_rejections, l_id
      from road_decisions
     where action_id = p_action_id
       and idempotency_key = p_idempotency_key
       and nvl(principal_id, 0) = nvl(l_principal, 0)
       and (decision = c_accepted or l_any = 'Y')
     order by decision_id desc
     fetch first 1 row only;

    -- An undisclosed rejection replays as the acceptance the consumer was shown.
    if l_decision = c_accepted or not l_disclosed then
      return outcome(l_version, c_accepted, l_result, null, l_id);
    end if;
    return outcome(l_version, c_rejected, null, l_rejections, l_id);
  exception
    when no_data_found then
      return null;
  end prior_outcome;

end road_decision_api;
/
