-- road_api_keys: API keys for agents (spec-patch-15 section 4.3).
--
-- A key is shown once, when it is made, and never stored: only its SHA-256 (hex) is kept, and
-- road_agent_api adds the key to its answer after the decision is recorded, so road_decisions never
-- holds it either. A tool trades a key at POST /api-auth/tokens for a short-lived JWT. A key stops
-- at revoked_at or expires_at, or when its agent or the agent's owner is not ACTIVE.
-- ORA-955-tolerant, matching its drop script (road-atlas F-10).
begin
  execute immediate q'[
    create table road_api_keys (
      key_id        number generated always as identity constraint road_api_keys_pk primary key,
      principal_id  number not null constraint road_api_keys_agent_fk references road_agents,
      name          varchar2(80 char) not null,
      key_prefix    varchar2(16 char) not null,
      key_hash      varchar2(64 char) not null constraint road_api_keys_hash_uk unique,
      created_by    number not null constraint road_api_keys_by_fk references road_principals,
      created_at    timestamp with time zone default systimestamp not null,
      last_used_at  timestamp with time zone,
      expires_at    timestamp with time zone,
      revoked_at    timestamp with time zone,
      revoked_by    number constraint road_api_keys_revoked_by_fk references road_principals
    )
  ]';
exception
  when others then
    if sqlcode != -955 then
      raise;
    end if;
end;
/

comment on table road_api_keys is 'API keys for agents. Only the SHA-256 of each key is kept; the key is shown once when made. spec-patch-15.';
