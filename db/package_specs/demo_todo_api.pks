create or replace package demo_todo_api as

  -- The reference governed surface (planning/spec-patch-16-gsc-reference-implementation.md): a
  -- small todo list that shows each part of a Governed Surface Contract once. Its contract is
  -- contract/hello_world.gsc.json, and everything below is an action or a view in it.
  --
  -- It is a reference, not a product and not a starter template. Copy the WIRING and throw the
  -- domain away: permission checks in the package, the owner taken from the session, one decision
  -- shape in every action, read tokens for staleness, the standard fields on every view.
  --
  -- Rule 1 of spec-patch-08, which keeps it honest: THE DEMO APP MAY NEVER CAUSE A FRAMEWORK CHANGE.
  -- If it needs something road-kit lacks, that is a specification question for the framework, raised
  -- separately -- never a change smuggled in under a demo.
  --
  -- The shape of every action (spec-patch-12; road_decision_api's header): check the call is
  -- well formed (a wrong call raises, and error_api answers 400), look for the prior outcome of the
  -- same idempotency key, take a savepoint, re-read the record and lock it, test the rules in the
  -- contract's order, then accept, or roll back to the savepoint and reject. A rule that fails is a
  -- decision, not an error: the answer is 200 with a decision record, and refusals are audited.
  --
  -- Never commits: ORDS commits on success, and the tests roll back to a savepoint. Authorisation is
  -- enforced HERE, not only in the handler, so a second caller -- an MCP tool, a batch job, another
  -- package -- cannot reach an operation by not being an ORDS handler.
  --
  -- Handlers are generated from api/routes.mjs and call these functions and nothing else.

  -- Action ids, as in the contract.
  c_create   constant varchar2(30) := 'todos.create';
  c_revise   constant varchar2(30) := 'todos.revise';
  c_complete constant varchar2(30) := 'todos.complete';
  c_reopen   constant varchar2(30) := 'todos.reopen';
  c_delete   constant varchar2(30) := 'todos.delete';
  c_purge    constant varchar2(30) := 'todos.purge';

  -- What every view says about withheld data (definition 7.4).
  c_scope constant varchar2(200) :=
    'Results are limited to your own todos unless you may list everyone''s. Deleted todos are left out unless asked for.';

  -- todos.list: GET /todos/   requires todo.list
  -- Another owner's todos need todo.list_all as well. The check is on the VALUE: passing your own id
  -- is not an escalation. DELETED rows are left out unless p_status asks for them by name. hasMore
  -- comes from fetching limit+1 rows; there is deliberately no total, which would be a second scan.
  -- Returns the view with its standard fields and ONE read token for the whole read: it covers every
  -- todo in items, and an action on a todo carries it with the todo's id.
  function list_todos(
    p_offset in number   default null,
    p_limit  in number   default null,
    p_status in varchar2 default null,
    p_query  in varchar2 default null,
    p_owner  in number   default null
  ) return clob;

  -- todos.get: GET /todos/{id}/   requires todo.get
  -- The caller's own todo, or any todo for a holder of todo.list_all. A missing todo, another
  -- owner's and a deleted one are all 404: the permission is held and the ROW is out of scope, and a
  -- 403 would confirm the row exists.
  function get_todo(p_todo_id in number) return clob;

  -- todos.create: POST /todos/   requires todo.create; Idempotency-Key
  -- p_body: { "title": "...", "notes": "...", "due_at": "<iso8601>" }
  -- The owner is the caller and is NEVER read from the body: a body that names one is a wrong call
  -- (400), not silently ignored, because ignoring it would tell a prober the forgery worked.
  -- Rule: TITLE_TAKEN.
  function create_todo(p_body in json, p_idempotency_key in varchar2) return json;

  -- The next four change a todo the caller read, so each carries the read token (p_body.read_token)
  -- and its natural idempotency key is (principal, id, read token). Rules, in order:
  -- TODO_NOT_FOUND, STALE_TOKEN, then the action's own. Only the owner may act: another owner's todo
  -- looks missing.

  -- todos.revise: POST /todos/{id}/revisions/   requires todo.update
  -- p_body: { "read_token", and at least one of "title", "notes", "due_at" }. Rule: TODO_DONE.
  function revise_todo(p_todo_id in number, p_body in json) return json;

  -- todos.complete: POST /todos/{id}/completions/   requires todo.update. Rule: TODO_DONE.
  function complete_todo(p_todo_id in number, p_body in json) return json;

  -- todos.reopen: POST /todos/{id}/reopenings/   requires todo.update. Rule: TODO_NOT_DONE.
  function reopen_todo(p_todo_id in number, p_body in json) return json;

  -- todos.delete: DELETE /todos/{id}/   requires todo.delete
  -- A soft delete: the row stays, and only the purge removes it.
  function delete_todo(p_todo_id in number, p_body in json) return json;

  -- todos.purge: POST /todos/purges/   requires todo.purge -- RESERVED; Idempotency-Key
  -- p_body: { "before": "<iso8601>" }. Rule: PURGE_CUTOFF_IN_FUTURE.
  -- Hard-deletes DONE and DELETED rows last changed before the cutoff, ACROSS ALL OWNERS.
  -- Irreversible, which is what qualifies it to be the reserved permission's subject: todo.purge
  -- does NOT start with road., so a prefix rule would let any road.role.compose holder attach it
  -- (spec-patch-07 section 3.1's worked example).
  function purge_todos(p_body in json, p_idempotency_key in varchar2) return json;

end demo_todo_api;
/
