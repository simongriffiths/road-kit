create or replace package road_audit_api as

  -- Issues a read-token GUID and logs the read as a road_api_log row (caller_type/caller_ref/
  -- app_schema/endpoint). Per spec-patch-01-concurrency.md §6.
  function issue_read_token(
    p_caller_type in varchar2,
    p_app_schema  in varchar2,
    p_endpoint    in varchar2,
    p_caller_ref  in varchar2 default null
  ) return raw;

  -- TRUE if p_current_updated_at is no later than the token's issued_at (nothing touched by
  -- this entity has changed since the read that issued p_guid) — FALSE otherwise, including
  -- when p_guid does not correspond to any issued token. Also annotates the token's
  -- road_api_log row with entity_type/entity_id/outcome ('OK' or 'STALE_REJECTED') so the one
  -- row serves concurrency, observability and audit together (spec-patch-01-concurrency.md §5).
  function check_fresh(
    p_guid               in raw,
    p_app_schema         in varchar2,
    p_entity_type        in varchar2,
    p_entity_id          in varchar2,
    p_current_updated_at in timestamp with time zone
  ) return boolean;

  -- Records an administrative action against road_api_log, taking the actor from road_ctx rather
  -- than from a parameter -- the caller cannot misattribute what it did.
  --
  -- Autonomous, so the audit row survives a failed or rolled-back operation. An action that was
  -- attempted and failed is exactly the one worth having a record of.
  procedure log_admin_action(
    p_endpoint    in varchar2,
    p_entity_type in varchar2 default null,
    p_entity_id   in varchar2 default null,
    p_outcome     in varchar2 default null
  );

end road_audit_api;
/
