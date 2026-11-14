# Specification Patch 14 — Batches, References and the Database-User Identity Path

**Applies to:** framework surface. `road_ctx_pkg` (one new function), a new `road_batch_api`
package, `road_decision_api` (batch mode), and the batch section of
`spec/governed-surface-contract.schema.json`.
**Status:** design, 14 November 2026. Not built. Sections 5.1 to 5.7 recommend an answer to each
of B-02's seven open design points; each recommendation needs Simon's ruling before building.
**Decisions it implements:** road-atlas ledger B-02 (road-planner's batch and agent identity path
are owed to road-kit, with positional references). It follows sections 5.2, 5.6 and 6.9 of the
Governed Surface Contract definition, version 0.1.0 (draft). Section 6.9 is Provisional.
**Depends on:** spec-patch-12 (`road_decision_api`) and spec-patch-13 (the schema's `batch`).

---

## 1. What this is

Two things road-planner built and road-kit lacks (ledger B-02):

1. **A batch.** An ordered list of governed actions decided as one unit: all applied or none,
   with a dry run.
2. **A database-user identity path.** An agent or batch process connects as its own database user,
   and a definer's-rights wrapper maps that session to a road principal. Identity is never a
   parameter.

Both are one logical PL/SQL API, with REST as a thin layer over it (definition P6).

road-tracker does not need a batch in Release 1 (its alignment note, item A4). road-planner adopts
this when it replaces `apply_changes`'s `$new1` keys.

## 2. Rulings this patch carries over (B-02, 20 and 23 October 2026)

- **Two ways in.** Agents run batch work as database users. End users run batches as themselves
  through REST.
- **No borrowed identity.** No session adopts an end user's security context. A process with no
  end user runs as its system owner, a database user.
- **Database-issued ids.** road-planner's client-chosen `$new1` keys are replaced. A later
  operation refers to an earlier result through a reference the authority resolves: by default the
  last record of a type created in this batch, or the n-th.

## 3. The database-user identity path

### 3.1 Framework function

One new function in `road_ctx_pkg`:

```sql
-- Establishes identity for a database-user binding call: maps SESSION_USER to the principal
-- (issuer 'urn:oracle-db', subject = the database user name). Returns false, never raises, when
-- no ACTIVE principal exists for it. Refuses ORDS's own connection user, so the REST path can
-- never reach a database-user identity.
function begin_database_request return boolean;

c_database_issuer constant varchar2(20) := 'urn:oracle-db';
```

It calls `begin_request(sys_context('USERENV', 'SESSION_USER'), c_database_issuer)`.
`SESSION_USER` is the user that logged in, and a definer's-rights wrapper cannot change it, so the
mapping cannot be forged. This is road-planner's `plan_agent_api` mapping (its D15, AG-10), moved
to the framework.

A system process with no end user runs as its system owner (definition 5.2.4). Its database user
gets a principal like any other, with the roles the process needs.

### 3.2 The application's wrapper

Each application writes one definer's-rights wrapper package per database-user surface. road-kit
ships the pattern, not a generic wrapper, because the wrapper's functions are the application's
actions:

```sql
create or replace package item_agent_api as   -- definer's rights, the default
  function claim_item(p_request in json) return json;
  function apply_batch(p_request in json) return json;
end;

function claim_item(p_request in json) return json is
  l_outcome json;
begin
  if not road_ctx_pkg.begin_database_request then
    raise_application_error(road_ctx_pkg.c_forbidden, 'No principal for this database user');
  end if;
  l_outcome := item_api.request_claim(p_request);  -- the same decision code REST calls
  commit;                                           -- one transaction per call
  road_ctx_pkg.end_request;
  return l_outcome;
exception
  when others then
    rollback;
    road_ctx_pkg.end_request;
    raise;
end;
```

Rules, all from road-planner AG-10:

- The agent's database user has `EXECUTE` on the wrapper and nothing else: no table grants, no
  grant on the application package or `road_ctx_pkg`.
- One transaction per call. The wrapper is the only code in the application that commits. No
  session holds a lock or an identity between calls.
- The wrapper calls the same package function the REST handler calls (definition 5.6).

## 4. The batch

### 4.1 Request

REST: `POST /batches`, with an `Idempotency-Key` header. Database binding: the wrapper's
`apply_batch`.

```json
{
  "dry_run": false,
  "operations": [
    { "action": "items.create", "request": { "project_id": 7, "title": "Parent" } },
    { "action": "items.create", "request": { "project_id": 7, "title": "Child",
                                             "parent_id": { "created": "item", "nth": 1 } } },
    { "action": "items.revise", "request": { "item_id": { "created": "item" },
                                             "description": "Split from the parent." } }
  ]
}
```

### 4.2 References

A reference is a closed token: a JSON object of exactly the form `{ "created": "<type>" }` or
`{ "created": "<type>", "nth": <n> }`. The authority resolves it to a number, which is bound into
SQL as a value and never concatenated into a statement (definition 6.9.6).

- `{ "created": "item" }` is the last item created so far in this batch.
- `{ "created": "item", "nth": 1 }` is the first. `nth` counts from 1, in creation order, so a
  parent's id stays reachable after later creates of the same type.
- A reference that does not resolve is a rejection, `BATCH_REFERENCE_UNRESOLVED`, at that
  operation's position.

### 4.3 Framework package `road_batch_api`

```sql
-- Starts a batch: clears all reference state (5.1), checks the operation count against the limit,
-- and puts road_decision_api into batch mode.
procedure begin_batch(p_operation_count in pls_integer, p_max_operations in pls_integer);

-- Called by an action when it creates a record inside a batch.
procedure created(p_type in varchar2, p_id in number);

-- Resolves a request value: a number is returned as it is; a reference token is resolved; any
-- other shape is a rejection.
function resolve(p_value in json) return number;

-- Builds the batch outcome and writes the batch's decision record. Ends batch mode.
function finish(p_action_id in varchar2, p_contract_version in varchar2,
                p_results in json, p_dry_run in boolean, p_idempotency_key in varchar2) return json;

-- Records a rejected batch (autonomous) with the failing position. Ends batch mode.
function fail(p_action_id in varchar2, p_contract_version in varchar2, p_position in pls_integer,
              p_rejections in json, p_idempotency_key in varchar2) return json;
```

The application owns the loop. Its batch function dispatches each operation by action id to the
same decision function its single-action endpoint calls, with a `case` statement and no dynamic
SQL, then runs its cross-record checks once against the final state (definition 6.9.3):

```sql
function apply_batch(p_request in json) return json is ...
begin
  l_prior := road_decision_api.prior_outcome(c_batch, l_key);
  if l_prior is not null then return l_prior; end if;
  savepoint batch;
  road_batch_api.begin_batch(l_count, c_max_operations);
  for i in 1 .. l_count loop
    l_out := case l_action
               when 'items.create' then item_api.request_create(l_request)
               when 'items.revise' then item_api.request_revision(l_request)
             end;
    if json_value(l_out, '$.decision') = 'rejected' then
      rollback to savepoint batch;
      return road_batch_api.fail(c_batch, c_version, i, <rejections of l_out>, l_key);
    end if;
  end loop;
  l_final := item_api.check_final_state;            -- cross-record rules, once
  if l_final is not null then
    rollback to savepoint batch;
    return road_batch_api.fail(c_batch, c_version, null, l_final, l_key);
  end if;
  l_out := road_batch_api.finish(c_batch, c_version, l_results, l_dry_run, l_key);
  if l_dry_run then rollback to savepoint batch; end if;
  return l_out;
end;
```

### 4.4 Decision records inside a batch

In batch mode `road_decision_api` changes behaviour:

- `accept` writes the operation's record in the caller's transaction, as always. A failed batch
  rolls it back with everything else.
- `reject` does **not** write an autonomous record. It returns the rejected outcome only, and the
  batch records one rejection for the whole batch through `road_batch_api.fail`. Otherwise a
  failed batch would leave one record for the failing operation and one for the batch.
- Each operation's own idempotency key is ignored. The batch key governs the whole unit.

An accepted batch therefore leaves one record per operation and one for the batch, all in one
transaction. A rejected batch leaves one record: the batch's, with the failing position.

### 4.5 Outcome

Accepted:

```json
{
  "contract_version": "1.0.0",
  "decision": "accepted",
  "result": {
    "dry_run": false,
    "operations": [
      { "position": 1, "action": "items.create", "result": { "item_id": 901 } },
      { "position": 2, "action": "items.create", "result": { "item_id": 902 } },
      { "position": 3, "action": "items.revise", "result": { "item_id": 902 } }
    ],
    "created": { "item": [901, 902] }
  },
  "audit_id": 120044
}
```

Rejected: the usual rejected outcome. Each rejection carries `position`, the 1-based index of the
failing operation, or no `position` for a cross-record rule tested on the final state
(definition 6.9.4). HTTP 200 either way. A batch over its limit is a wrong call, 400, because it is
stopped before any decision code runs.

## 5. The seven open design points

Each is open in B-02 and in definition Appendix E question 3. These are recommendations.

### 5.1 Reset state per batch

**Recommendation: yes.** `begin_batch` clears all reference state, and both `finish` and `fail`
clear it again. Package state is per session, and a pooled ORDS session would otherwise carry the
last batch's references into the next caller's batch. This is the same reasoning as
`road_ctx_pkg.begin_request` clearing identity first.

### 5.2 The form of the closed reference token

**Recommendation:** `{ "created": "<type>", "nth"?: n }`, as section 4.2. It is a fixed-shape JSON
object, so it cannot be confused with a literal value, and resolving it never builds SQL text.
road-planner's `$new1` strings are client-chosen names, which B-02 replaced.

### 5.3 Declared created types

**Recommendation: yes.** Each action in the contract declares the record types it can create, as
`creates: ["item"]`. A consumer then knows what it can reference, and `created` can refuse an
undeclared type. This needs one optional property on the schema's action. It is not in schema 0.3.0
and would be added on this ruling.

### 5.4 At most one record per type per operation

**Recommendation: yes, for now.** It keeps "the last item created" unambiguous at every step, and
road-planner's operations already meet it. `created` refuses a second record of one type in one
operation. It can be relaxed later without breaking any existing batch.

### 5.5 A batch idempotency key

**Recommendation: required.** The batch is the unit a consumer retries after a dropped connection,
so it carries the key, in the `Idempotency-Key` header, and `prior_outcome` replays it. Operation
keys inside a batch are ignored (section 4.4). This is road-planner's AG-12.

### 5.6 Dry run

**Recommendation:** a dry run returns the full outcome, including derived changes, rolls back,
emits no events, and **writes no decision record**, because nothing was decided. Its outcome has
`"dry_run": true` and `"audit_id": null`. Definition 6.4.1 requires an `audit_id` in every outcome,
so this needs the definition to allow null for a dry run. Raise it in gsc Appendix E.

### 5.7 Limits

**Recommendation:** `max_operations` declared in the contract, default 500 as road-planner's
AG-13. No duration limit in the batch itself. A long batch is bounded by the database's own
resource limits, and a duration limit inside PL/SQL could only be checked between operations.

## 6. Schema

Schema 0.3.0 already has `state.batch` (`provisional`, `action_resource`, `operations`, `limits`,
`idempotency`, `dry_run`). Rulings on 5.3 add `creates` to the action. Rulings on 5.6 may change
the outcome's `audit_id` rule.

## 7. Build plan, once ruled

1. `road_ctx_pkg.begin_database_request`, with tests: a mapped user is established; an unmapped
   user is refused; ORDS's connection user is refused; a pooled session is cleared.
2. `road_decision_api` batch mode, with tests for section 4.4.
3. `road_batch_api`, with tests: reference resolution, `nth`, unresolved reference, reset between
   batches, limit, one-record-per-type.
4. A demo batch over `demo_todo_api` with a REST endpoint and a database-user wrapper. Endpoint
   tests prove both bindings reach the same decision code.
5. Atlas: B-02 moves road-kit to `applied`; road-planner becomes `candidate` to adopt.

## 8. Out of scope

- Delegation, where an agent acts for a person (definition Appendix E question 1).
- Asynchronous or long-running batches.
- A command line binding (definition Appendix E question 5).
