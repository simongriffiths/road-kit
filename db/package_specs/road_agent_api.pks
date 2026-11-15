create or replace package road_agent_api as
  -- Agents and their API keys (spec-patch-15, ledger B-04).
  --
  -- A person makes an agent of their own (self-serve): a principal of its own, owned by them, that
  -- holds the application's agent role (road_config agents.role) and never its owner's roles. They
  -- make keys for it, each shown once and stored only as a SHA-256 hash. A tool trades a key at
  -- POST /api-auth/tokens (exchange, below) for a short-lived JWT. Holders of road.api_key.manage see
  -- and revoke every agent's keys and make shared agents with no owner.
  --
  -- The four changes are governed actions (spec-patch-12): JSON in, outcome out, recorded in
  -- road_decisions, never committing. A wrong call raises -20001 (400), a missing permission -20403.
  --
  -- Settings in road_config: agents.role (unset: self-serve is off), agents.limit_per_owner
  -- (default 5), api_keys.prefix (default rk), api_keys.token_minutes (default 15).

  c_contract_version constant varchar2(20) := '0.4.0';  -- road-kit's version, for framework actions
  c_create_agent     constant varchar2(30) := 'agents.create';
  c_retire_agent     constant varchar2(30) := 'agents.retire';
  c_create_key       constant varchar2(30) := 'api_keys.create';
  c_delete_key       constant varchar2(30) := 'api_keys.delete';

  -- POST /agents/ {display_name, shared?}. Rules: AGENT_LIMIT_REACHED. "shared": true (no owner)
  -- needs road.api_key.manage.
  function create_agent(p_body in json, p_idempotency_key in varchar2) return json;
  -- DELETE /agents/{id}/. Its keys are revoked and its principal RETIRED. Rules: AGENT_NOT_FOUND.
  function retire_agent(p_agent_id in number, p_idempotency_key in varchar2) return json;
  -- POST /agents/{id}/keys/ {name, expires_at?}. Rules: AGENT_NOT_FOUND, AGENT_RETIRED. The key is
  -- in the result, once: added after the decision is recorded, so road_decisions never holds it,
  -- and a replay of the same Idempotency-Key returns the outcome without it.
  function create_key(p_agent_id in number, p_body in json, p_idempotency_key in varchar2) return json;
  -- DELETE /agents/{id}/keys/{key_id}/. Rules: AGENT_NOT_FOUND, API_KEY_NOT_FOUND.
  function revoke_key(p_agent_id in number, p_key_id in number, p_idempotency_key in varchar2) return json;

  -- GET /agents/: the caller's own agents and their keys; p_all = 'true' every agent, for
  -- road.api_key.manage. Never a key or its hash.
  function list_agents(p_all in varchar2 default null) return clob;

  -- POST /api-auth/tokens, public: {"api_key": "..."} in; HTTP status and body out. 200 with
  -- access_token, token_type, expires_in and subject; 401 invalid_key for a key that is unknown,
  -- revoked or expired, or whose agent or owner is not ACTIVE; 400 for no key. Records last use.
  procedure exchange(p_body in clob, p_status out number, p_response out clob);
end road_agent_api;
/
