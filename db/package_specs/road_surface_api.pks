create or replace package road_surface_api as

  -- What every governed surface's handlers and packages share (spec-patch-16 section 3.2), made
  -- generic from road-tracker's rt_action_pkg and rt_rest_pkg. A governed action follows the shape
  -- in road_decision_api's header: prior_outcome, savepoint, re-read, test the rules, then accept,
  -- or roll back to the savepoint and reject. This package holds only the parts every surface
  -- shares. It owns no business rule, and error_api is unchanged: fail wraps it.

  -- Raised for a call that is wrong (error_api maps it to 400). Business rules never raise.
  c_bad_request constant number := -20001;
  -- Raised for a read of a record that does not exist or is hidden (error_api maps it to 404).
  c_not_found   constant number := -20004;

  -- What a response states when no contract has been loaded into road_contract yet, such as a
  -- framework-only deploy. An application's contract replaces it.
  c_framework_version constant varchar2(20) := '0.4.0';

  -- The statement a view makes about withheld data when its surface gives none (definition 7.4).
  c_default_scope constant varchar2(200) := 'Results are limited to the records you may see.';

  -- The contract version this deployment serves: the one in road_contract, which
  -- scripts/contract-to-sql.mjs loads from the contract file. Read on each call, so a reload
  -- reaches pooled sessions at once.
  function contract_version return varchar2;

  -- The leading number of contract_version, which an Accept-Version header must match.
  function major_version return varchar2;

  -- The contract document, for GET /contract/.
  function contract return clob;

  -- Raises c_bad_request with p_message.
  procedure bad_request(p_message in varchar2);

  -- The idempotency key for an action that changes an existing record: the record's id and the
  -- read token the caller sent. road-kit issues one token per read, and one read (a list) returns
  -- many records with the same token, so the id is needed to tell two proposals apart.
  -- road_decision_api scopes keys to the principal, which makes the natural key (principal, id,
  -- read token) the contract declares. A null token gives a null key.
  function natural_key(p_record_id in number, p_read_token in varchar2) return varchar2;

  -- A read token as the RAW road_audit_api stores, from the hex text a consumer sends. A missing
  -- or malformed token is a wrong call (400).
  function token_raw(p_read_token in varchar2) return raw;

  -- True when the record has not changed since the token was issued. An unknown token is not fresh.
  function is_fresh(p_token in raw, p_entity in varchar2, p_id in number,
                    p_updated_at in timestamp with time zone) return boolean;

  -- A new read token, as hex text, for a view or for an action's result. The caller type is
  -- AGENT for a principal in road_agents, BROWSER otherwise.
  function new_token(p_endpoint in varchar2) return varchar2;

  -- A timestamp as ISO 8601 UTC text, for responses.
  function iso(p_ts in timestamp with time zone) return varchar2;

  -- road_decision_api.accept and reject with this surface's contract version.
  function accept(
    p_action_id       in varchar2,
    p_result          in json     default null,
    p_record_ids      in json     default null,
    p_idempotency_key in varchar2 default null
  ) return json;

  -- The same, with the result as JSON text, which is what JSON_OBJECT returns in PL/SQL.
  function accept(
    p_action_id       in varchar2,
    p_result_text     in varchar2,
    p_record_ids      in json     default null,
    p_idempotency_key in varchar2 default null
  ) return json;

  function reject(
    p_action_id       in varchar2,
    p_rejections      in json,
    p_record_ids      in json     default null,
    p_idempotency_key in varchar2 default null
  ) return json;

  -- The non-disclosing refusal for a record that does not exist or is not the caller's: not
  -- retryable, and carrying no ids, so a hidden record and a missing one get the same answer. The
  -- caller rolls back to its savepoint first, as for any rejection. p_rule_id is the surface's
  -- own rule, such as TODO_NOT_FOUND.
  function record_not_found(
    p_action_id       in varchar2,
    p_rule_id         in varchar2,
    p_message         in varchar2 default 'No such record.',
    p_idempotency_key in varchar2 default null
  ) return json;

  -- A view body with the standard fields (definition 7.3): contract_version, as_at, scope and, when
  -- the view states one, change_number. A null p_scope leaves scope out, for a view whose own
  -- result has a field of that name (the session). Returned as text, which is what a handler sends.
  function envelope(
    p_body          in json,
    p_scope         in varchar2 default c_default_scope,
    p_change_number in number   default null
  ) return clob;

  -- Adds contract_version to a JSON object body, such as error_api's 4xx and 5xx responses, so
  -- every response states the contract version. A body that is not a JSON object is returned
  -- unchanged.
  function with_version(p_body in clob) return clob;

  -- Sends a JSON body with the given status. Bodies of any size.
  procedure respond(p_status in number, p_body in clob);

  -- 401 with the contract version, when no session could be established.
  procedure unauthorized;

  -- False, having sent a 400, when Accept-Version is present and names another major version.
  function version_ok(p_accept_version in varchar2) return boolean;

  -- Maps an exception to a 4xx or 5xx response through error_api, adding the contract version. A
  -- request body that is not JSON is a 400.
  procedure fail(p_sqlcode in number, p_sqlerrm in varchar2, p_backtrace in varchar2, p_context in varchar2);

end road_surface_api;
/
