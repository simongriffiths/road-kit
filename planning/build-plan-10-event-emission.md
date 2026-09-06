# Build Plan 10 — After-Commit Event Emission

**Design:** `planning/spec-patch-10-event-emission.md`. Read it first; this file sequences the
work and records what each phase actually cost.

**Status: not started.**

**Standing discipline for every phase below**, per `AGENTS.md`: search the engineering history
before touching the database, include an INTENT block in every script, execute through
`bin/run-sql.sh`, and review the run log afterwards. Record the run id in the phase's table.

---

## Phase 1 — `road_events` table and index

Framework table. Create and drop scripts, wired into the deploy chain.

**Files**

- `db/tables/road_events.create.sql` — ORA-955-tolerant, per road-atlas `F-10` and the pattern in
  `db/tables/demo_todos.create.sql`
- `db/tables/road_events.drop.sql` — ORA-942-tolerant, matching its sibling
- registered in `deploy/create/10_tables.sql`, index in `20_indexes.sql`, drops in the
  corresponding `deploy/drop/` files

**Verification**

| Check | Result |
|---|---|
| `ROAD_EVENTS` in `user_tables` | |
| `ROAD_EVENTS_STATUS` in `user_indexes` | |
| `status` check constraint rejects a value outside PENDING/DISPATCHED/FAILED | |
| Create script run **twice** — second run silent, no ORA-955 | |
| Drop script run against a non-existent table — silent, no ORA-942 | |
| Run id | |

The double-run is the point of the ORA-955 tolerance and is exactly what `F-10` was raised
about. Running it once proves nothing.

---

## Phase 2 — `road_event_api`

**Files**

- `db/package_specs/road_event_api.pks`
- `db/package_bodies/road_event_api.pkb`
- registered in `deploy/create/60_package_specs.sql` and `70_package_bodies.sql`

`emit` is **not** autonomous — that is the whole design, and it is the one line most likely to be
"tidied" by someone later who assumes all audit-shaped writes are autonomous. The package comment
must say so loudly enough that it survives.

**Verification**

| Check | Result |
|---|---|
| `ROAD_EVENT_API` spec + body | |
| `USER_ERRORS` for the package | |
| Create-chain references all resolve | |
| Run id | |

---

## Phase 3 — `road_event_api_test`

The seven tests of spec-patch-10 §7, structured as `road_audit_api_test` is. Tests roll back to a
savepoint; the package never commits.

**Test 2 is the one that matters** — emit, roll back, assert no row. It is the assertion that
proves `after_commit` rather than naming it, and it is the line the white paper will quote.

**Verification**

| Check | Result |
|---|---|
| `ROAD_EVENT_API_TEST` spec + body VALID | |
| `road_event_api_test.run_all` | _n_ passed, 0 failed |
| Test 2 (emit → rollback → no row) passes | |
| Test 7 (null payload and null capability_id both accepted) passes | |
| Run id | |

Test 7 exists because a framework primitive that only works fully-populated is a trap for the
first adopter, not because anything currently calls it that way.

---

## Phase 4 — Deploy chain integrity

Verify the new objects deploy in the right order from the create chain: `10_tables` →
`20_indexes` → `60_package_specs` → `70_package_bodies`, and that the drop chain removes them.

**Not a full `00_full` drop-and-rebuild.** Build plan 09 deferred that from its phase 1 to its
phase 6 for the same reason — tearing down `road_kit_dev` to prove a leaf object is the wrong
trade — and it is *still outstanding there* (RK-09: "deploy ordering for the new objects is
unproven end to end"). This patch adds objects to that same unproven chain.

**That is a known, inherited risk and this plan does not clear it.** Whoever eventually runs the
full rebuild for patch 09 phase 6 clears it for both at once. Say so rather than implying these
objects are proven in a clean build when they are not.

**Verification**

| Check | Result |
|---|---|
| Create-chain references resolve, in order | |
| Drop chain removes table, index, spec and body | |
| Run id | |

---

## Phase 5 — Release

Only after phases 1-4 are green.

1. `road_event_api_test.run_all` green, recorded above.
2. Commit; `git diff` shows only the intended files.
3. Simon approves the release.
4. Annotated tag — `v0.3.0`, continuing the sequence from `v0.2.0` per the convention chosen for
   W2.
5. Record in road-atlas as the next `RK-nn`, `kind: framework-patch`, `origin: road-kit`, naming
   candidate consumers explicitly.

---

## Findings

_To be filled in as the work is done. Anything discovered that changes what another repository
should do goes to road-atlas, not only here._
