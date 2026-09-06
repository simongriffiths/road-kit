# Specification Patch 11 — Governed Completion Action and Todo Contributors

**Applies to:** the demo application (`demo_todo_api`, `demo_todos`), deployed via
`deploy/create/97_demo.sql`. No framework surface changes here.
**Status:** design, 2026-09-04. Not built.
**Depends on:** `planning/spec-patch-10-event-emission.md`, built and deployed first.

**Related:**
`planning/governed-state-contracts-proof-plan-v1.md` — W3. This patch is W3.
`spec/governed-state-contract.schema.json` — the contract schema this action must satisfy
(`v0.1.0`).
`scripts/project-mcp-descriptor.mjs` — projects this action's contract into the MCP descriptor
an agent actually sees (`v0.2.0`).

---

## 1. What this is

The first complete governed action in road-kit: a **proposal resource** whose decision is made
by the database, not by the caller.

An agent submits "todo 42 should be completed." It does not perform a completion. The
operational authority re-reads current state, applies business rules, decides, records the
decision in the same transaction as any state change, and emits an event only if it committed.

Everything before this patch has been the contract's *description* of that loop. This is the
loop.

### 1.1 The scenario this exists to catch

An agent is acting for Alice, a contributor on Bob's todo. It reads the todo and forms a
proposal. Before it submits, **Alice is removed as a contributor** — reassigned, rolled off,
access revoked.

The proposal is well-formed. Alice's token is still valid. Her scope still contains
`todo.complete`. Nothing about the *caller* has changed.

The authority refuses.

That refusal is the patch's reason to exist, because no amount of validating the caller catches
it. Conventional systems answer "may this actor do this?" when the token is minted; this one
answers it at the moment of decision, against business state the auth system has never heard of.
**Scope is necessary and not sufficient.**

### 1.2 What it is not

It is not delegation. The agent uses Alice's own credentials and *is* Alice as far as road-kit is
concerned, so the contract's `authority.actor.model` here is `authenticated`, not `delegated`.
True on-behalf-of is a separate identity-model question — see `planning/identity-model-gaps.md`,
road-atlas `B-01` and `F-09` — and claiming it here would be over-reading what gets built.

Scenario 1.1 does not depend on it. Alice's *own* token, Alice's *own* revoked relationship.

### 1.3 Rule 1 compliance

`demo_todo_api`'s constitution forbids the demo causing a framework change. Two candidates came
up and both are handled honestly:

- **Event emission** — genuinely missing from the framework. Raised as patch 10 and built first,
  not smuggled in here.
- **Decision audit** — not a framework gap on inspection. Unexpected failures are already logged
  autonomously by `error_api.handle_unknown` to `error_log`, and `road_audit_api.log_admin_action`
  covers `road_admin_api`'s admin actions. What is left is one table holding this action's
  accepted and rejected decisions, whose columns are visibly this domain's (`todo_id`, this
  action's rejection codes). Demo-local, and no framework patch implied. See §6.

## 2. Contributors

```sql
create table demo_todo_contributors (
  todo_id                number not null references demo_todos,
  principal_id           number not null references road_principals,
  added_at               timestamp with time zone default systimestamp not null,
  added_by_principal_id  number not null references road_principals,
  removed_at             timestamp with time zone,
  removed_by_principal_id number references road_principals,
  constraint demo_todo_contributors_pk primary key (todo_id, principal_id)
);
```

**Removal is soft, and that is load-bearing** — not tidiness. §5's disclosure rule needs to
distinguish "was a contributor and was removed" from "never had anything to do with this todo,"
and a deleted row cannot answer that. It also gives scenario 1.1 an audit trail that shows the
revocation actually happened, rather than asking a reader to take it on trust.

A row is *current* when `removed_at is null`. Re-adding a removed contributor updates the
existing row (clears `removed_at`) rather than inserting a second — hence the natural primary
key.

## 3. The assertion

One genuine cross-table invariant: **a todo's owner is never also a current contributor.**
Otherwise the notify list double-counts them and "where does Bob's authority come from" has two
answers.

```sql
-- ASSERTION, not a trigger, for the same structural reason as road_reserved_composition
-- (spec-patch-07 section 5.1, spike-07-1 section 3.4): the violation can be introduced by
-- updating the PARENT row. A trigger on demo_todo_contributors catches "add Bob to Bob's todo"
-- but never sees "reassign this todo's owner to Bob, who is already a contributor."
--
-- COMMA JOIN, NOT ANSI. `JOIN ... ON` is rejected with ORA-08735 inside an ORA-08689 wrapper on
-- 26ai (spike-07-1 section 3.3). An ANSI rewrite looks like tidying and fails at deploy time,
-- not review time. Do not "simplify" this.
create assertion demo_todo_owner_not_contributor check (
  not exists (
    select 1
      from demo_todos t, demo_todo_contributors c
     where c.todo_id = t.todo_id
       and c.principal_id = t.owner_principal_id
       and c.removed_at is null
  )
);
```

Registered in `deploy/create/96_assertions.sql`. Needs no new privilege —
`admin/grant-schema-privileges.sql` already grants schema-scoped `CREATE ASSERTION`.

`error_api` already maps `ORA-8601` (assertion violation) to `FORBIDDEN`/403 rather than leaking
a 500, so a violation degrades safely at the API boundary without further work.

## 4. The action

```
POST /todos/completion-requests/     requires todo.complete
```

**The proposal is the resource.** You do not `PATCH` the todo; you submit a completion request
and the authority decides what to do with it. The URL says so, which is worth more than a
paragraph of documentation saying so.

`todo.complete` is a new demo permission seeded in `97_demo.sql`. Holding it is **necessary and
not sufficient** — it gets the caller to the door, and the contributor relationship gets them
through it. That gap is the entire point of §1.1.

```sql
  -- POST /todos/completion-requests/   requires todo.complete
  -- p_request: { "todo_id": n }
  -- Returns:   { "todo_id": n, "decision": "ACCEPTED", "status": "DONE",
  --              "already_complete": bool, "event_id": n|null }
  --
  -- A PROPOSAL, not an instruction. Every precondition is re-read here at decision time; a
  -- caller that read the todo a moment ago has told us what it WANTED, not what is true.
  function request_completion(p_request in json) return json;
```

### 4.1 Preconditions, all re-read at decision time

| Rule id | Meaning |
|---|---|
| `TODO_EXISTS` | the todo row exists and is not `DELETED` |
| `TODO_IS_OPEN` | status is `OPEN` (or already `DONE` — see idempotency, §4.3) |
| `PROPOSER_IS_OWNER_OR_CONTRIBUTOR` | caller is the owner, or a **current** contributor |
| `CONTRIBUTOR_STATUS_RECHECKED` | contributor currency is read now, not taken from the request |

The proposer is always `road_ctx_pkg.principal_id`. It is never read from the body — the same
rule `create_todo` already applies to `owner_principal_id`, and for the same reason: a caller who
could nominate it could forge it.

### 4.2 Outcomes

| Code | Status | ORA | Retryable | When |
|---|---|---|---|---|
| *(accepted)* | 200 | — | — | completed, or already complete |
| `NOT_A_CONTRIBUTOR` | 403 | `-20403` | false | caller was a contributor and has been removed |
| `TODO_NOT_FOUND` | 404 | `-20004` | false | no such todo, deleted, or caller never had access (§5) |

Both rejections are **non-retryable, and that is a substantive claim**: retrying changes neither
your contributor status nor whether the todo exists. This is the same instinct already written
into `demo_todo_api.c_conflict_message` — tell an agent to re-evaluate, never to retry, because
"an agent told to retry will retry."

Codes and statuses come from the *implementation's* fixed mapping in `error_api.pkb`
(`-20403`→403, `-20004`→404), not from `spec/error-handling-contract-v1.md` §4.2, whose constant
list is stale and contradicts both the implementation and `demo_todo_api`. See §10.

### 4.3 Idempotency

Natural key: `todo_id`. An agent that retries after a network timeout must not be told its
successful call failed.

Already `DONE` → **accepted**, `already_complete: true`, **and no second event is emitted**.
Idempotency covers the *effects*, not merely the row: notifying the contributors twice because a
client retried would be the failure everyone actually notices.

This holds even if somebody else completed it. The proposal's intent — "this should be done" —
is satisfied; the audit records who actually did it.

## 5. The disclosure rule

Refusal must not leak which todos exist. But refusing *identically* in all cases destroys the
agent's ability to respond sensibly, which is scenario 1.1's whole value.

**Refuse in the shape of what the caller already legitimately knew.**

- **Never associated with the todo** (not owner, no contributor row ever) → `TODO_NOT_FOUND`,
  404, indistinguishable from a todo that does not exist. A stranger cannot enumerate ids.
- **Was a contributor, now removed** → `NOT_A_CONTRIBUTOR`, 403. They already knew it existed;
  concealing it now protects nothing and misleads the agent into "that todo vanished" when the
  truth is "your access was revoked." Those warrant different responses.

This is why §2's removal is soft. The alternative — always 403 when the row exists — is simpler
and leaks existence to strangers, which would be a strange thing to ship in a governance
demonstration.

The choice between actionable refusal and non-disclosure is a real one, and the contract makes it
**explicit and machine-readable** rather than an accident of whichever branch happened to run
first.

## 6. Transactional audit

```sql
create table demo_todo_decisions (
  decision_id      number generated always as identity,
  todo_id          number not null,
  capability_id    varchar2(200 char) not null,
  proposer_principal_id number not null references road_principals,
  decision         varchar2(20 char) not null,
  rejection_code   varchar2(60 char),
  event_id         number,
  decided_at       timestamp with time zone default systimestamp not null,
  constraint demo_todo_decisions_pk primary key (decision_id),
  constraint demo_todo_decisions_ck check (decision in ('ACCEPTED', 'REJECTED'))
);
```

Written **in the same transaction** as the state change — the schema's `audit.transactional:
true`, meant literally.

`event_id` references the row `road_event_api.emit` returned, so the decision and the effect it
authorised are linked in the record rather than merely adjacent in time.

**Rejections are audited the same way, and they also commit.** Verified against
`api/modules/todos/module.create.sql`: a handler catches the raise, calls `error_api.handle_known`,
emits a status and body, and completes normally. There is no `rollback` in the exception path, and
PL/SQL does not roll back on exception — only the failed statement is undone. So a decision row
written before the raise survives, and ORDS commits it. A refusal nobody can see is not
governance, and this is what makes the refusal visible.

Three outcomes, two mechanisms:

| Outcome | Audit |
|---|---|
| Accepted | this table, in-transaction, alongside the state change and the event |
| Rejected | this table, in-transaction, then raise → handler converts to 403/404 + body |
| Unexpected failure | `error_api.handle_unknown` → `error_log`, autonomous, already built |

**One behaviour to prove rather than assume** (build-plan-11 phase 1): that ORDS does commit when
a handler completes normally *after* catching an exception, so the rejection row genuinely
persists. `demo_todo_api`'s header states "Never commits — ORDS commits on success," and a
caught-and-handled exception should qualify, but the audit design rests on it and it costs ten
minutes to demonstrate.

`todo_id` has no foreign key deliberately: a decision about a todo that was later purged is still
a decision that was made, and `demo_todo_api.purge` hard-deletes.

## 7. The contract document

`spec/contracts/demo.todo-completion-request.json` — a real Governed State Contract instance
conforming to `governed-state-contract.schema.json` `v0.1.0`, carrying:

- `capability_id`: `demo.todo-completion-request`
- `action_resource`: `POST /todos/completion-requests/`
- `authority.actor`: `authenticated`, `required_permissions: ["todo.complete"]`
- `request.idempotency`: `natural_key` on `["todo_id"]`
- `preconditions`: §4.1's four rules, `current_state_recheck: true`
- `outcomes`: §4.2
- `audit.transactional: true` with §6's fields
- `events.emitted`: `todo.completed`, `after_commit`

New directory `spec/contracts/` for contract instances, distinct from the schema they conform to.
`spec/` holds documents rather than deployed objects, so this reaches no adopter's schema.

**This is what closes the loop.** `node scripts/project-mcp-descriptor.mjs
spec/contracts/demo.todo-completion-request.json` yields the descriptor an agent sees, from the
same document the database implements — W1, W2 and W3 as one line rather than three artefacts
that coexist.

## 8. The event

`todo.completed`, emitted after the decision commits, via `road_event_api.emit`. Payload carries
the todo, who completed it, and **the current contributor list as recipients**.

Nothing delivers it. Per patch 10 §5, delivery is conventional integration and proves nothing
about governance; the event carries who should be told, and that is the governed part.

## 9. Test plan

**PL/SQL** (`demo_todo_api_test`, extending the existing suite; savepoint rollback, no commits):
the four scenarios of the proof plan, plus idempotency.

1. Contributor proposes, still current → `ACCEPTED`, status `DONE`, one decision row, one event.
2. **Contributor proposes, removed in between → `NOT_A_CONTRIBUTOR`/403.** The headline. Must
   assert a *structured rejection*, not an `ORA-` leak.
3. Stranger proposes → `TODO_NOT_FOUND`/404, indistinguishable from a nonexistent id (§5).
4. Already `DONE` → accepted, `already_complete: true`, **no second event row**.
5. Decision rolls back → no `demo_todo_decisions` row and no `road_events` row.
6. Owner proposes → accepted (ownership is authority independent of contribution).
7. Assertion: adding the owner as a contributor is refused; *and* reassigning a todo's owner to an
   existing contributor is refused — the parent-update case a trigger would miss (§3).

**Endpoint** (`test/endpoint/`, curl-level, following `todos.endpoint.sh`): scenarios 1–4 over
real HTTP, asserting status codes and the `error` code in the body, because the PL/SQL suite
proves the decision and only HTTP proves what an agent actually receives.

**Projection**: extend `test/mcp/validate-mcp-descriptor-projection.mjs` to project §7's real
contract, not only the W1 fixture.

## 10. Findings raised, not absorbed

1. **`spec/error-handling-contract-v1.md` is stale.** Its constants (§ around line 67) declare
   `-20001` not_found, `-20002` validation, `-20003` business_rule, `-20004` forbidden. The
   implementation in `error_api.pkb` maps `-20001`→`VALIDATION_ERROR`/400, `-20003`→
   `AGENDA_LOCKED`/422, `-20004`→`NOT_FOUND`/404, `-20009`→`CONFLICT`/409, `-20403`→
   `FORBIDDEN`/403, `-8601`→`FORBIDDEN`/403. `demo_todo_api.pks` agrees with the implementation.
   The spec document is wrong and should be corrected separately — not inside this patch, and
   worth a road-atlas entry since any adopter reading the spec would build to the wrong codes.
2. **Watch for a second decisions table.** §6's table is application-shaped and belongs in the
   demo. But if a second governed action anywhere in the estate copies it wholesale, that is the
   signal that a framework primitive is warranted — generalised from two real shapes rather than
   guessed from one. Not a gap today; a trigger condition to watch for.

## 11. Out of scope

- Email or any other delivery of `todo.completed` (patch 10 §5).
- Delegation / on-behalf-of tokens (§1.2).
- Making the existing `update_todo` a governed action. It is the owner mutating their own row
  with optimistic concurrency, it works, and governing it would prove nothing.
- Contributor management UI. Adding and removing contributors needs an API surface for the tests;
  anything beyond that is not evidence.
- Fixing `spec/error-handling-contract-v1.md` (§10.1).
- A framework transactional-audit primitive (§10.2).

## 12. Provenance

Read 2026-09-04: `db/package_specs/demo_todo_api.pks`, `db/tables/demo_todos.create.sql`,
`db/package_specs/road_audit_api.pks`, `db/package_specs/error_api.pks`,
`db/package_bodies/error_api.pkb` (status mapping, lines ~34–66), `deploy/create/96_assertions.sql`
(assertion precedent, comma-join constraint, privilege), `deploy/create/97_demo.sql` (demo
placement and seed counts), `spec/error-handling-contract-v1.md` (the stale constants of §10.1).
`road-blogger/db/package_specs/sub_api.pks` confirmed the honeypot precedent referenced by W1.
