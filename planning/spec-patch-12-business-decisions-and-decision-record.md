# Specification Patch 12 — Business Decisions Return 200, and the Decision Record

**Applies to:** framework surface. `spec/error-handling-contract-v1.md` (to 2.0),
`spec/ords-api-design-standards-v1.md` (to 1.1), `spec/react-project-structure-conventions-v1.md`,
`spec/automated-testing-strategy-v1.md`, `error_api`, and the new `road_decisions` table and
`road_decision_api` package.
**Status:** built and tested on `road_kit_dev`, 14 November 2026.
**Decisions it implements:** road-atlas ledger D-05 (business decisions return HTTP 200 with a
structured outcome, and rejections are audited). The decision record follows section 6.7 of the
Governed Surface Contract definition, version 0.1.0 (draft), in the `gsc` repository.

---

## 1. What changes

| Before | After |
|---|---|
| A business rule failure is raised as `-20003` and returned as HTTP 422 | A governed action returns an outcome with HTTP 200, accepted or rejected |
| `error_api` maps `-20003` to `AGENDA_LOCKED`/422 | `-20003` is unmapped. A package that still raises it gets a logged 500 |
| The error contract's code list (`-20001` not found, `-20002` validation, ...) contradicts `error_api` | The contract lists `error_api`'s actual mapping |
| No framework decision record. `road_api_log` records calls and read tokens | `road_decisions` records every decision: principal, action, contract version, decision, rejections, records involved, idempotency key, time |
| Each governed action would design its own decisions table (spec-patch-11 section 6) | Every governed action uses `road_decision_api` |

## 2. The three result classes

Every response falls into one class. The dividing line is whether the decision code ran.

| Class | HTTP | Examples |
|---|---|---|
| The system failed | 5xx, or no response | Network fault, unhandled exception |
| The call was wrong | 4xx | No token, no permission for the endpoint, malformed input, unknown resource on a read |
| The business decided | 200 | Accepted; or rejected with `rule_id`, `message`, `retryable`, `ids`, plus `audit_id` |

A permission that depends only on the principal may still be checked first, by
`road_ctx_pkg.require_permission`, and is then a 403. A rule that depends on state, including
access rules such as "is still a contributor", is a business decision.

## 3. The outcome

```json
{ "contract_version": "1.0.0", "decision": "accepted", "result": { ... }, "audit_id": 91877 }

{ "contract_version": "1.0.0", "decision": "rejected",
  "rejections": [ { "rule_id": "STALE_TOKEN", "message": "...", "retryable": true, "ids": [42] } ],
  "audit_id": 91878 }
```

`audit_id` is `road_decisions.decision_id`. The shape is built in one place,
`road_decision_api`, so every adopter returns the same thing.

## 4. The decision record

### 4.1 Table

`db/tables/road_decisions.create.sql`. One row per proposal that reached a decision.

| Column | Meaning |
|---|---|
| `decision_id` | Identity. Returned as `audit_id` |
| `decided_at` | Time of the decision |
| `principal_id` | From `road_ctx_pkg`, never a parameter. Null for a public action. No foreign key, so the record outlives the principal |
| `action_id`, `contract_version` | Which action, under which contract version |
| `decision` | `accepted` or `rejected`: the true decision |
| `disclosed` | False for a non-disclosing rejection reported to the consumer as an acceptance (GSC 6.4.4) |
| `idempotency_key` | The caller's key or the derived natural key |
| `record_ids`, `result`, `rejections` | JSON. `result` is what an accepted outcome returned; `rejections` is the full list |

`road_api_log` is unchanged. It keeps read tokens, admin actions and call audit.

### 4.2 Transactions

| Decision | Written by | Transaction |
|---|---|---|
| Accepted | `accept` | The caller's. If the change rolls back, so does the record |
| Rejected | `reject`, `reject_undisclosed` | Autonomous, after the caller has rolled back to its savepoint. The record survives |

Unlike `road_audit_api.log_admin_action`, the autonomous write does not swallow its own failure.
The record is part of the decision. If it cannot be written, the handler answers 500.

This replaces spec-patch-11 section 6's plan to write the rejection row in the caller's
transaction and rely on ORDS committing after a caught exception. With an autonomous write, the
record no longer depends on that behaviour, so build plan 11's phase 1 spike is no longer needed.

### 4.3 Idempotency

`prior_outcome(action, key)` returns the earlier outcome for the same action, principal and key,
so a repeated proposal changes nothing. The unique index `road_decisions_idempotency_ux` allows one
accepted decision per (action, principal, key). When two copies race, the second insert fails with
`DUP_VAL_ON_INDEX` once the first commits, and the action answers with `prior_outcome`. Keys are
scoped to the principal, so one consumer's key cannot replay another's outcome.

### 4.4 A rejection does not use up its key

By default `prior_outcome` replays accepted outcomes only. A consumer that gets a retryable
rejection can retry later with the same key and be accepted. Read literally, GSC definition 6.5
would replay the rejection for ever. road-tracker's alignment note (item A3) raises the same
point. `p_replay_rejections => true` gives the literal reading for an action that wants it. This
is raised as an open question for the definition (section 8).

## 5. Error mapping, corrected

`error_api` is the reference. The contract now lists it: `-20001` 400, `-20004` 404, `-20009` 409,
`-20403` 403, `-8601` 403. `-20002` and `-20003` are not used. This closes spec-patch-11 section
10.1.

## 6. Client

- `GovernedOutcome` and `Rejection` types in `hello_world/src/types/api.ts`. A rejected outcome is
  a normal 200 result, shown by the component that proposed it, never a toast.
- Fixed in passing: `hello_world/src/api/client.ts` read the error code from `payload.code`, but
  `error_api` sends `error`, so every error reached the UI as `HTTP_ERROR`.

## 7. Verification

Run `20261114_203310_spec-patch-12-apply` on `road_kit_dev`. The script, `scratch/spec-patch-12-apply.sql`, is
untracked like the rest of `scratch/`. Its INTENT block and output are in the tracked run log under `logs/dev/runs/`.


| Check | Result |
|---|---|
| `ROAD_DECISIONS`, `ROAD_DECISIONS_IDEMPOTENCY_UX`, both packages and test packages | VALID |
| `error_api_test.run_all`, including `-20003` now a logged 500 | 7 passed, 0 failed |
| `road_decision_api_test.run_all` | 10 passed, 0 failed |
| Accepted record rolls back with the caller | Pass |
| Rejected record survives the caller's rollback | Pass |
| Replay is per principal; a second principal with the same key gets nothing | Pass |
| A rejection leaves its key usable; a second accepted decision under one key is refused | Pass |
| Non-disclosing rejection: consumer sees accepted, record holds rejected | Pass |
| Test rows left behind | 0 |
| `tsc --noEmit` on `hello_world` | Clean |

Not verified: an endpoint returning an outcome over HTTP. road-kit has no governed action yet;
the first is spec-patch-11's completion request (build plan 11), which now builds on this patch.

The first apply (run `20261114_203248`) compiled `road_decision_api` with PLS-00306:
`json_element_t.parse` has no overload for the native `JSON` type on 26ai. The body now serialises
through SQL first. `run-sql.sh` reported that run as SUCCESS although a body was INVALID. Read the
compile-errors section of the log, not only the exit status.

## 8. For other repositories

- **Adopters of `error_api`** (quorate, road-cal, road-blogger, aida): any package that raises
  `-20003` must convert that rule to a governed action outcome, or keep a local mapping, when it
  adopts this patch. road-blogger is live (ledger F-06).
- **road-tracker:** uses `road_decisions` instead of its planned `rt_decisions` (alignment item
  A2). Its idempotency rule (A1) fits `prior_outcome` with a natural key.
- **gsc:** open question for Appendix E: should section 6.5 replay only accepted outcomes (4.4
  above)?

## 9. Out of scope

- Field-level change history (ledger F-12). GSC 6.7.5 keeps it separate from the decision record.
- Contract version discovery at request time (GSC 5.3.3). That belongs with the two-section schema,
  spec-patch-13.
- Batches (spec-patch-14).
