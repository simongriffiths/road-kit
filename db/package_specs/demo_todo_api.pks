create or replace package demo_todo_api as

  -- The demo application (planning/spec-patch-08-road-kit-demo-app.md, in road-cal).
  --
  -- This package exists to be READ, and to fail loudly when the framework breaks. It is the
  -- smallest application that pulls on every seam an adopter will pull on: permission-gated
  -- handlers, an application role, a RESERVED application permission, per-principal ownership, and
  -- optimistic concurrency through road_audit_api.
  --
  -- It is not a product and not a starter template. Nobody should build on top of it.
  --
  -- Rule 1 of the patch, which keeps it honest: THE DEMO APP MAY NEVER CAUSE A FRAMEWORK CHANGE.
  -- If it needs something road-kit lacks, that is a specification question for the framework,
  -- raised separately -- never a change smuggled in under a demo.
  --
  -- Signature convention matches road_admin_api and road-cal's event_api: native JSON in, native
  -- JSON out, no ref cursors or PL/SQL collections across the package boundary. Never commits --
  -- ORDS commits on success and tests roll back to a savepoint.
  --
  -- Authorisation is enforced HERE, not only in the handler, for the same reason road_admin_api
  -- does it: a second caller -- an MCP tool, a batch job, another package -- must not reach a
  -- privileged operation by not being an ORDS handler.

  -- Error codes, matching error_api's fixed mapping exactly. Listed here so the demo reads as
  -- documentation of the contract an adopter inherits.
  c_validation constant number := -20001;  -- 400 VALIDATION_ERROR
  c_not_found  constant number := -20004;  -- 404 NOT_FOUND
  c_conflict   constant number := -20009;  -- 409 CONFLICT

  -- Fixed 409 wording. It must read as a request to RE-EVALUATE, never as an instruction to retry
  -- (spec-patch-02-mcp.md section 5). An agent told to retry will retry, and the second write is
  -- the one that silently destroys the change it could not see. Do not vary this text per call.
  c_conflict_message constant varchar2(300) :=
    'The todo changed since you read it. Call GET /todos/{todo_id}/ to see the current state, ' ||
    'then decide whether the change is still appropriate.';

  -- GET /todos/   requires todo.list
  -- p_request: { "status": "OPEN|DONE|DELETED", "q": "<term>", "owner": n,
  --              "offset": n, "limit": n }  -- all optional
  -- Returns:   { "items": [ <todo>, ... ], "hasMore": bool, "limit": n, "offset": n, "count": n,
  --              "read_token": "<guid>" }
  --
  -- Scoped to the caller's own rows unless "owner" names someone else, which requires
  -- todo.list_all. The same endpoint with permission-dependent scope, deliberately, rather than a
  -- separate /todos/all/ route: it is the case adopters actually hit and the one that is easy to
  -- get wrong. A route-shaped check teaches nothing transferable (spec-patch-08 section 6.1).
  --
  -- DELETED rows are excluded unless "status" asks for them by name.
  --
  -- hasMore comes from fetching limit+1 rows and discarding the extra. There is deliberately no
  -- total count, which would be a second full scan to render a number nothing needs.
  function get_todos(p_request in json default null) return json;

  -- POST /todos/   requires todo.create
  -- p_request: { "title": "...", "notes": "...", "due_at": "<iso8601>" }
  -- Returns:   the created todo object. NO read_token -- read it back via get_todo before
  --            updating, matching road-cal's create endpoints.
  --
  -- owner_principal_id is taken from road_ctx_pkg.principal_id and is NEVER read from the body,
  -- for the same reason granted_by is not on grant_role and attached_by is not on
  -- attach_permission: a caller who could nominate it could forge the record of who owns what. A
  -- body that supplies it is a 400, not a silently ignored field -- silently ignoring an attempt
  -- to set ownership tells the caller their forgery worked.
  function create_todo(p_request in json) return json;

  -- GET /todos/:todo_id/   requires todo.get
  -- p_request: { "todo_id": n }
  -- Returns:   { "todo": <todo>, "read_token": "<guid>" }
  function get_todo(p_request in json) return json;

  -- PATCH /todos/:todo_id/   requires todo.update
  -- p_request: { "todo_id": n, "read_token": "<guid>",
  --              "title": "...", "notes": "...", "due_at": "...", "status": "OPEN|DONE" }
  -- Returns:   the updated todo object.
  --
  -- status accepts OPEN and DONE only. DELETED is reachable through delete_todo alone, so
  -- "I finished it" and "I want it gone" stay distinguishable.
  --
  -- read_token is required and checked with road_audit_api.check_fresh. Stale -> c_conflict.
  function update_todo(p_request in json) return json;

  -- DELETE /todos/:todo_id/   requires todo.delete
  -- p_request: { "todo_id": n, "read_token": "<guid>" }
  -- Returns:   { "todo_id": n, "deleted": true|false }
  --            deleted=false when it was already DELETED -- idempotent, not an error, matching
  --            grant_role and attach_permission.
  --
  -- Soft delete. The row survives; only purge removes it.
  function delete_todo(p_request in json) return json;

  -- POST /todos/purge/   requires todo.purge  -- RESERVED
  -- p_request: { "before": "<iso8601>" }
  -- Returns:   { "purged": n }
  --
  -- Hard-deletes DONE and DELETED rows older than the cutoff, ACROSS ALL OWNERS. Irreversible,
  -- which is exactly what qualifies it to be the reserved permission's subject.
  --
  -- todo.purge is reserved and does NOT start with road. -- spec-patch-07 section 3.1's worked
  -- example, and the whole reason road-kit needed an application: a prefix rule would let any
  -- road.role.compose holder attach this from the composition UI, and the entire point of it is to
  -- be the permission nobody holds by default.
  function purge(p_request in json) return json;

end demo_todo_api;
/
