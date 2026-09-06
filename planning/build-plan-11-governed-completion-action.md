# Build Plan 11 — Governed Completion Action and Todo Contributors

**Design:** `planning/spec-patch-11-governed-completion-action.md`. Read it first; this file
sequences the work and records what each phase actually cost.

**Status: not started.**

**Hard precondition: build plan 10 complete and deployed.** The action emits through
`road_event_api`, which does not exist until then. Do not start phase 4 without it.

**Standing discipline for every phase**, per `AGENTS.md`: search the engineering history before
touching the database, INTENT block in every script, execute through `bin/run-sql.sh`, review the
run log. Record the run id in each phase's table.

---

## Phase 1 — Spike: does ORDS commit after a caught exception?

**Do this first, before writing anything real.** The entire audit design in spec-patch-11 §6
rests on one behaviour: that a decision row written *before* a `raise_application_error` survives,
because the ORDS handler catches the exception, returns a status and body, and completes
normally — so ORDS commits.

`api/modules/todos/module.create.sql` contains no `rollback` in any exception path, and PL/SQL
does not roll back on exception. So it should hold. But the audit design depends on it, it was
twice reasoned about wrongly during design, and it costs half an hour to settle.

**A PL/SQL test cannot prove this** — the suites roll back to a savepoint, and the behaviour under
test is ORDS's, not the package's. It needs a real HTTP request.

**Approach.** Scratch objects, in `scratch/`, following the precedent of
`scratch/phase4-audit-api-apply.sql`:

1. A scratch table.
2. A scratch ORDS endpoint whose body inserts a row, then raises `-20004`, wrapped in the
   standard handler pattern copied verbatim from `module.create.sql`.
3. Call it over HTTP. Expect 404 and a well-formed `{"error":"NOT_FOUND",...}` body.
4. Query the scratch table **from a separate session**. Row present or absent?
5. Drop the scratch objects.

**Verification**

| Check | Result |
|---|---|
| Endpoint returns 404 with a well-formed body, no raw ORA- | |
| Row written before the raise, read from another session | present / absent |
| Scratch objects removed | |
| Run id | |

**If the row is absent**, spec-patch-11 §6 is wrong and rejection audit must move to an autonomous
write before any further phase proceeds. Stop and revise the design rather than working around it.

---

## Phase 2 — Tables and the assertion

**Files**

- `db/tables/demo_todo_contributors.create.sql` / `.drop.sql` — ORA-955/942-tolerant
- `db/tables/demo_todo_decisions.create.sql` / `.drop.sql`
- the assertion, in `deploy/create/96_assertions.sql`
- table creates registered in `deploy/create/97_demo.sql`, not `10_tables.sql` — these are demo
  objects and adopters must never receive them

**The assertion must use a comma join, not ANSI.** `JOIN ... ON` is rejected with `ORA-08735`
inside an `ORA-08689` wrapper on 26ai (`spike-07-1` §3.3). An ANSI rewrite looks like tidying and
fails at deploy time rather than review time.

**Verification**

| Check | Result |
|---|---|
| Both tables in `user_tables`, with their constraints | |
| `DEMO_TODO_OWNER_NOT_CONTRIBUTOR` assertion created | |
| Assertion refuses: adding the owner as a contributor | |
| Assertion refuses: **reassigning a todo's owner to an existing contributor** | |
| Soft-delete round trip: remove sets `removed_at`, re-add clears it, no second row | |
| Both create scripts run twice — silent | |
| Run id | |

The second assertion check is the one that justifies using an assertion at all — it is the
parent-table update a trigger on the child would never see (spec-patch-11 §3).

---

## Phase 3 — Contributor management

Enough surface for a caller to add and remove contributors, because phase 6's tests need it. No
more than that; anything beyond is not evidence.

Owner-only, guarded by the existing **`todo.update`** permission. No new permission — a
contributor list is part of the todo's shape, and inventing `todo.contribute` would add a seed
entry, a role wiring and a test for no gain.

**Verification**

| Check | Result |
|---|---|
| Owner can add and remove a contributor | |
| Non-owner cannot, and gets a structured refusal | |
| Adding the owner is refused by the assertion, surfaced as 403 not 500 | |
| Run id | |

`error_api` already maps `ORA-8601` to `FORBIDDEN`/403, so the assertion violation should degrade
safely without further work. Confirm it does rather than assuming.

---

## Phase 4 — `request_completion`

**Precondition: build plan 10 deployed.**

The decision path itself. Package spec and body changes to `demo_todo_api`, plus the
`todo.complete` permission seeded in `97_demo.sql` and attached to the demo role.

Sequence inside one transaction: re-read state → evaluate preconditions → update `demo_todos` →
insert `demo_todo_decisions` → `road_event_api.emit` → return. Rejections write their decision row
and then raise.

The proposer is always `road_ctx_pkg.principal_id`, never read from the body — the rule
`create_todo` already applies to ownership, for the same reason.

**Verification**

| Check | Result |
|---|---|
| `DEMO_TODO_API` spec + body VALID, no `USER_ERRORS` | |
| `todo.complete` seeded, attached to the demo role, seed count updated in the INTENT block | |
| Accepted path: `demo_todos` updated, one decision row, one event row, all in one transaction | |
| Run id | |

`97_demo.sql`'s INTENT block currently says "7 permissions, 1 role." Update it, or the next
reader trusts a stale count.

---

## Phase 5 — ORDS endpoint

`POST /todos/completion-requests/`, in `api/modules/todos/module.create.sql`, plus its privilege
entry.

Thin handler: one package call, the standard exception block, no logic.

**Verification**

| Check | Result |
|---|---|
| Endpoint registered in `USER_ORDS_*` | |
| Privilege requires `todo.complete` | |
| Happy path returns 200 with a well-formed body | |
| Run id | |

---

## Phase 6 — PL/SQL tests

The seven scenarios of spec-patch-11 §9, extending `demo_todo_api_test`.

**Verification**

| Check | Result |
|---|---|
| `demo_todo_api_test.run_all` | _n_ passed, 0 failed |
| 1. Contributor proposes, current → accepted, one decision row, one event | |
| 2. **Contributor removed in between → `NOT_A_CONTRIBUTOR`, structured, no ORA- leak** | |
| 3. Stranger → `TODO_NOT_FOUND`, indistinguishable from a nonexistent id | |
| 4. Already `DONE` → accepted, `already_complete: true`, **no second event row** | |
| 5. Rollback → no decision row and no event row | |
| 6. Owner proposes → accepted | |
| 7. Assertion, both directions | |
| Run id | |

Scenario 2 is the headline of the whole proof plan. Scenario 4's "no second event" is the one
most likely to be got wrong and least likely to be noticed.

---

## Phase 7 — Endpoint tests

Scenarios 1-4 over real HTTP, in `test/endpoint/`, following `todos.endpoint.sh`.

The PL/SQL suite proves the decision; only HTTP proves what an agent actually receives. RK-09
records that road-kit's central claim went unproven for weeks precisely because every test stopped
inside the database — do not repeat it here.

**Verification**

| Check | Result |
|---|---|
| Status codes: 200, 403, 404, 200 | |
| Bodies carry the `error` code, never a raw ORA- | |
| Run id | |

---

## Phase 8 — Close the loop

`spec/contracts/demo.todo-completion-request.json` — a real contract instance conforming to
`governed-state-contract.schema.json` `v0.1.0`, describing what phases 4-7 actually built.

Extend `test/mcp/validate-mcp-descriptor-projection.mjs` to project it, not only the W1 fixture.

**Verification**

| Check | Result |
|---|---|
| Contract validates against the v0.1.0 schema | |
| `node scripts/project-mcp-descriptor.mjs spec/contracts/demo.todo-completion-request.json` | |
| Descriptor's `inputSchema` matches what the endpoint actually accepts | |
| Projection test green | |

**The third check is the one with teeth.** A contract that describes an endpoint it does not match
is worse than no contract — and nothing automated catches that drift today. Assert it by hand here
and note it as a gap worth closing later.

---

## Phase 9 — Release

1. All suites green, recorded above.
2. Commit; `git diff` shows only intended files.
3. Simon approves.
4. Annotated tag `v0.4.0` (assuming build plan 10 took `v0.3.0`).
5. Record in road-atlas as the next `RK-nn`. This one is `origin: road-kit` but demo-scoped —
   say so plainly, so no adopter reads it as framework surface they inherit.
6. Update `planning/governed-state-contracts-proof-plan-v1.md`: W3 complete, and what W4 still
   needs.

---

## Findings

_To be filled in as the work is done. Anything that changes what another repository should do goes
to road-atlas, not only here._

Two already known, carried from spec-patch-11 §10:

1. `spec/error-handling-contract-v1.md` contradicts `error_api.pkb` on error-code mapping. Not
   fixed by this plan. Worth a road-atlas `F-` entry — an adopter reading the spec would build to
   the wrong codes.
2. Watch for a second decisions table anywhere in the estate. That is the trigger for a framework
   primitive, generalised from two real shapes rather than guessed from one.
