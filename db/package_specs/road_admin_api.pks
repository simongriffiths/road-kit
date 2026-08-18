create or replace package road_admin_api as

  -- Role administration (spec-patch-06 section 5, build plan phase 4).
  --
  -- Signature convention matches event_api: native JSON in, native JSON out, no ref cursors or
  -- PL/SQL collections across the package boundary. Never commits -- ORDS commits on success and
  -- tests roll back to a savepoint.
  --
  -- Authorisation is enforced HERE, not only in the handler. The handler's job is to establish
  -- session context from :current_user; the permission requirement travels with the operation, so
  -- a second caller -- an MCP tool, a batch job, another package -- cannot reach a privileged
  -- operation by not being an ORDS handler.

  -- GET /admin/principals/:principal_id/roles   requires road.role.grant
  -- p_request: { "principal_id": <number> }
  -- Returns:   { "principal_id": n, "subject": "...", "roles": [ { "role_name", "granted_at",
  --              "granted_by" }, ... ] }
  function get_principal_roles(p_request in json) return json;

  -- POST /admin/principals/:principal_id/roles   requires road.role.grant
  -- p_request: { "principal_id": <number>, "role_name": "<name>" }
  -- Returns:   { "principal_id": n, "role_name": "...", "granted": true|false }
  --            granted=false when the principal already held it -- idempotent, not an error.
  --
  -- granted_by is taken from road_ctx_pkg.principal_id and is never read from the request body.
  -- Granting a RESERVED role additionally requires road.role.define, which is what stops a
  -- road.user_admin promoting anyone -- including themselves -- to road.system_admin.
  function grant_role(p_request in json) return json;

  -- DELETE /admin/principals/:principal_id/roles/:role_name   requires road.role.revoke
  -- p_request: { "principal_id": <number>, "role_name": "<name>" }
  -- Returns:   { "principal_id": n, "role_name": "...", "revoked": true|false }
  --
  -- Revoking a reserved role also requires road.role.define, for the same reason as granting: a
  -- road.user_admin who could revoke road.system_admin could lock the real administrators out.
  -- Revoking the LAST holder of road.system_admin is refused outright.
  function revoke_role(p_request in json) return json;

  -- GET /admin/roles   requires road.role.grant
  -- Returns: { "roles": [ { "role_name", "display_name", "description", "is_reserved",
  --            "permissions": [...] }, ... ] }
  function get_roles(p_request in json default null) return json;

  -- POST /admin/roles   requires road.role.define
  -- p_request: { "role_name": "<name>", "display_name": "...", "description": "..." }
  -- Returns:   the created role object.
  --
  -- Refuses the road. prefix: that namespace is reserved for the framework's own administration
  -- surface, and an application inventing a road.* role would be claiming framework authority.
  function define_role(p_request in json) return json;

  -- Deploy-time convenience (patch section 5.1). Grants every non-road. permission to a role by
  -- writing EXPLICIT ROWS -- it is not a runtime rule, because as a runtime rule it would be a
  -- wildcard and every permission added later would be acquired silently, violating rule 4.
  --
  -- Deliberately NOT permission-gated: it is called from deploy scripts running as the schema
  -- owner, where no session context exists. Gating it on "allow when no context is established"
  -- would be a fail-open, and gating it on a permission would make the deploy path need a
  -- principal. Do not call it from a handler.
  --
  -- Correct only while an application has no admin-only permission. road-cal graduates from it in
  -- phase 7, when events.purge arrives and the blanket grant stops being right.
  procedure grant_all_app_permissions(p_role_name in varchar2);

end road_admin_api;
/
