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

  -- GET /admin/principals   requires road.role.grant
  -- p_request: { "offset": n, "limit": n, "q": "<term>", "status": "ACTIVE|SUSPENDED|RETIRED" }
  --            all optional; offset defaults to 0, limit to 25 and is clamped to 1..100.
  -- Returns:   { "items": [ { "principal_id", "issuer", "subject", "email", "display_name",
  --              "status", "created_at",
  --              "roles": [ { "role_name", "is_reserved" }, ... ] }, ... ],
  --              "hasMore": bool, "limit": n, "offset": n, "count": n }
  --
  -- roles carries is_reserved (spec-patch-07 section 8.1), not bare names -- a client that infers
  -- reserved-ness from the road. prefix disagrees with assert_may_manage the moment they diverge.
  --
  -- The OrdsCollection wrapper the React conventions already define, so no new client type.
  -- hasMore comes from fetching limit+1 rows and discarding the extra -- there is deliberately no
  -- total count, which would be a second full scan to render a number nothing needs.
  --
  -- Gated on road.role.grant rather than road.role.define: reading who exists is what a
  -- road.user_admin needs to do their job, and they can already read anyone's grants.
  --
  -- Returns email. Someone who can grant roles can already read any principal's grants, so the
  -- login address does not widen that audience -- and subject is opaque by design (patch 4.2)
  -- while display_name is nullable, so without it an administrator often cannot tell two
  -- principals apart. It is still PII: never put q or the result in a URL a browser will log.
  --
  -- Deliberately NOT returned: effective permissions (they belong to roles, and get_roles already
  -- carries the mapping -- flattening them here would duplicate the composition in two places)
  -- and credentials_changed_at (credential-store surface, not role administration).
  function get_principals(p_request in json default null) return json;

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
  -- Skips RESERVED permissions, and skips road.* ones. Both conditions, deliberately -- they are
  -- not the same question and neither implies the other. is_reserved answers "may a session attach
  -- this at all"; the road. prefix answers "is this the framework's own authority". A framework
  -- permission that is legitimately unreserved should still not be swept into an application role
  -- by a blanket grant, and an APPLICATION permission that is reserved (events.purge, todo.purge)
  -- does not start with road. at all -- which is precisely the case spec-patch-07 section 3.1 says
  -- a prefix rule gets wrong. This filter read the prefix ALONE until 2026-08-19; road-cal noticed
  -- the symptom when events.purge arrived and worked around it by hand-listing its user grants
  -- (95_data.sql), leaving the cause shipping. Do not "simplify" the two conditions back into one.
  --
  -- Even correct, it is only a convenience for the simple case. Any application with an admin-only
  -- permission, or with an unreserved permission not every role should hold, spells its grants out
  -- in 95_data.sql instead -- as road-cal does, and as the demo app in spec patch 08 does.
  --
  -- attached_by is written NULL explicitly (spec-patch-07 section 10 question 3), not by omission
  -- -- this is the deploy-attached case road_reserved_composition's guard depends on being able to
  -- tell apart from a session attach. See attach_permission below.
  procedure grant_all_app_permissions(p_role_name in varchar2);

  -- Role composition (spec-patch-07 section 7). Attaching an existing permission to an existing
  -- role is genuinely runtime data -- road_ctx_pkg.begin_request reloads effective permissions per
  -- request, so the change takes effect on the caller's next request with no new machinery.
  -- Creating a permission is NOT: that is a release-time act (section 2), and this package
  -- deliberately has no function for it.

  -- GET /admin/permissions/   requires road.role.compose
  -- Returns: { "permissions": [ { permission_name, description, is_reserved, roles: [...] }, ... ] }
  --
  -- Not a convenience: there is currently no other way to list road_permissions at all, so
  -- nothing can offer a catalogue to compose from.
  function get_permissions(p_request in json default null) return json;

  -- POST /admin/roles/:role_name/permissions/   requires road.role.compose
  -- p_request: { "role_name": "<name>", "permission_name": "<name>" }
  -- Returns:   { "role_name", "permission_name", "attached": true|false }
  --            attached=false when already held -- idempotent, not an error, matching grant_role.
  --
  -- Refuses, as a flat refusal rather than a permission tier (unlike assert_may_manage's
  -- road.role.define escalation for roles -- section 7 draws this distinction deliberately):
  --   - a permission with is_reserved = 'Y' -- the framework's own authority is composed at
  --     deploy time only, enforced in the database by road_reserved_composition
  --   - a role with is_reserved = 'Y' -- a reserved role's composition is framework-owned
  --
  -- attached_by comes from road_ctx_pkg.principal_id and is never read from the body, for the same
  -- reason granted_by is not on grant_role: a caller who could nominate it could forge the record
  -- of who authorised an escalation.
  function attach_permission(p_request in json) return json;

  -- DELETE /admin/roles/:role_name/permissions/:permission_name/   requires road.role.compose
  -- p_request: { "role_name": "<name>", "permission_name": "<name>" }
  -- Returns:   { "role_name", "permission_name", "detached": true|false }
  --
  -- Same two refusals as attach_permission. Detaching road.role.grant from the last role that
  -- holds it is refused by the database (road_admin_reachable), not by this function -- that
  -- assertion covers every writer, including ones that don't go through this package.
  function detach_permission(p_request in json) return json;

end road_admin_api;
/
