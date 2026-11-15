# Specification Patch 16 — road-kit as the Reference Implementation of the Governed Surface Contract

**Applies to:** framework surface and the demo. A new package `road_surface_api` and table
`road_contract`; a public `GET /contract/` module; three scripts (`contract-to-sql.mjs`,
`generate-modules.mjs`, `check-contract-coverage.mjs`); framework contract fragments; and the todo
demo, rebuilt as a governed surface with its own contract.
**Status:** ruled 15 November 2026; **built the same day** on `ROAD_KIT_DEV`, not released. Simon
accepted every recommendation in section 6 as written. Section 9 records where the build differs from
the plan, and why.
**Decisions it implements:** Simon's intent that road-kit is the reference implementation of the
gsc definition (15 November 2026); road-atlas D-04 (one contract per surface), D-05 (decisions
answer 200), D-07 (the definition lives in gsc, road-kit implements it), RK-14's "not done" list, and
ledger B-05 (road-tracker's serving and checking pieces are owed to road-kit).
**Depends on:** spec-patch-12 (`road_decision_api`), 13 (the schema), 15 (agents, `road-cli`, the
skill generator).
**Proven in:** road-tracker, contract 0.8.0: `rt_action_pkg`, `rt_rest_pkg`, `rt_contract`,
`scripts/contract-to-sql.mjs`, `scripts/generate-modules.mjs`,
`test/contract/check-contract-coverage.mjs`; 34 of the gsc checklist's 35 items pass
(`road-tracker/planning/release-checks-r1.md`).

---

## 1. What this is

road-kit has the building blocks of a governed surface: the contract schema and its validator, the
decision record, read tokens, the error envelope, principals and permissions, and now agents. It has
no surface that uses them together. Its demo predates the definition (a stale edit is HTTP 409, there
are no decision records or idempotency keys), no road-kit API has a contract, and the pieces that
serve and check a contract exist only in road-tracker. A team reading road-kit to learn how to build a
governed surface finds the parts, but not the whole.

This patch makes road-kit the reference:

1. **The framework pieces a surface needs**, taken from road-tracker and made generic: the contract
   loaded into the database and served at `GET /contract/`; the contract version on every answer,
   errors included; `Accept-Version`; the read-token idempotency key; the standard fields on every
   view (as-at time and scope); thin handlers generated from a route list; and the check that every
   handler has a contract entry and every entry a handler.
2. **A reference surface**: the todo demo rebuilt as a governed surface with its own contract,
   governed actions and views, agents working it through `road-cli` with a generated skill, and the
   gsc checklist run against it.
3. **Contracts for road-kit's own endpoints**: agents and session as contract fragments every
   application's contract includes, so framework actions carry the application's contract version,
   not road-kit's (spec-patch-15 stamps them `0.4.0` until this patch).

## 2. Why the demo, rather than a new example

The demo is what an application copies first and reads to learn the patterns; quorate and
road-tracker both carry it. While it teaches the pre-definition model, every new surface starts from
the wrong example. It is small enough to show each part of a governed surface once, which is what a
reference needs.

## 3. Framework pieces

### 3.1 Table `road_contract` and `scripts/contract-to-sql.mjs`

One row: the contract document and its version. `scripts/contract-to-sql.mjs` writes
`deploy/create/generated/96_contract.sql` from `contract/<app>.gsc.json` (after merging the
framework fragments, 3.6), so the database serves exactly the file that was validated.

### 3.2 Package `road_surface_api`

What every governed surface's handlers and packages share, from road-tracker's `rt_action_pkg` and
`rt_rest_pkg`:

- `contract_version` (from `road_contract`, cached per call) and `major_version`;
- `version_ok(p_accept_version)`: answers 400 `VERSION_MISMATCH` for another major version;
- `natural_key(p_record_id, p_read_token)`: the idempotency key for an action on an existing record,
  (principal, record id, read token), because one read returns many records with one token;
- `token_raw`, `is_fresh`, `new_token`: read tokens through `road_audit_api`, a bad token a 400;
- `accept`, `reject`: `road_decision_api` with the surface's contract version;
- `record_not_found(p_action, p_key)`: the non-disclosing refusal for a hidden or missing record;
- `envelope(p_obj, p_change_number)`: `contract_version`, `as_at`, `change_number` where the view
  states one, and `scope`;
- `respond(p_status, p_body)` and `fail(...)`: every body as JSON with `contract_version`, 4xx and 5xx
  from `error_api` included (road-tracker alignment A10).

`error_api` itself is unchanged; `fail` wraps it.

### 3.3 `GET /contract/`

A public module (the definition's 5.5 discovery path), on the handler coverage allowlist: a consumer
reads the contract before it has a token.

### 3.4 `scripts/generate-modules.mjs`

Writes an application's ORDS modules from a route list in the application
(`api/routes.mjs`: module, base path, and per route its pattern, method, contract id, package call
and headers). Every handler has one shape: establish the session or answer 401, check
`Accept-Version`, make one package call, respond, and route failures through `road_surface_api.fail`.
No business rule can live in a handler (definition 6.3).

### 3.5 `test/contract/check-contract-coverage.mjs`

Reads the deployed handlers from `USER_ORDS_HANDLERS` and the contract, and fails unless every
handler has a contract entry and every entry a handler (definition 9.5), and the contract version is
the same in the file, the database and the served document. Public framework endpoints (health,
login, the key exchange, the contract itself) are listed as outside the surface.

### 3.6 Framework contract fragments

`contract/fragments/road-agents.json` (spec-patch-15's four actions and view) and
`contract/fragments/road-session.json` (`GET /session/me/`). `contract-to-sql.mjs` and the validator
merge the fragments an application lists in its contract's `x-road-include` into one document, so the
surface has one contract (D-04). `road_agent_api` then uses the surface's contract version.

## 4. The reference surface: the todo demo, governed

### 4.1 Contract `contract/hello_world.gsc.json`

| Action | Resource | Rules |
|---|---|---|
| `todos.create` | `POST /todos/` (Idempotency-Key) | none: a missing title is a wrong call (400); see 6.4 |
| `todos.revise` | `POST /todos/{id}/revisions/` (read token) | `TODO_NOT_FOUND`, `STALE_TOKEN`, `TODO_DONE` |
| `todos.complete` | `POST /todos/{id}/completions/` (read token) | `TODO_NOT_FOUND`, `STALE_TOKEN`, `TODO_DONE` |
| `todos.reopen` | `POST /todos/{id}/reopenings/` (read token) | `TODO_NOT_FOUND`, `STALE_TOKEN`, `TODO_NOT_DONE` |
| `todos.delete` | `DELETE /todos/{id}/` (Idempotency-Key) | `TODO_NOT_FOUND` |

Views: `todos.list` and `todos.get`, each with `as_at` and `scope`, and a read token per todo. The
purge stays an admin action, governed (`todos.purge`, rule `PURGE_CUTOFF_IN_FUTURE`), still needing
the reserved permission `todo.purge`. `TODO_NOT_FOUND` does not disclose: another owner's todo looks missing.

### 4.2 Package `demo_todo_api`, rebuilt

The decision shape of spec-patch-12 in every action: prior outcome, savepoint, re-read and lock,
rules, then accept or roll back and reject. Rules return 200 refusals; wrong calls raise 400. The
409 path is gone.

### 4.3 Agents, the CLI and the skill

The demo's `todo_agent` (spec-patch-15) works todos through `road-cli` (`todos`, `todo-add`,
`todo-done`, `todo-reopen`), and `skills/hello_world/SKILL.md` is generated from the contract. A
fresh headless Claude Code session using the skill is the acceptance test, as in road-tracker.

### 4.4 The checklist

`contract/checklist.md` records the gsc skill's 35 items against the demo with evidence, like
road-tracker's. Items the demo does not use (batches) say so.

## 5. Tests

PL/SQL: every demo rule refused, replays, a stale token leaving no change, views' envelope;
`road_surface_api` (natural key stable for one token and record, different for the next; a hidden
and a missing record answering alike; the envelope). HTTP: outcomes with `rule_id` and `audit_id`,
`contract_version` on 400, 403, 404 and 500 bodies, `Accept-Version`, `GET /contract/`, an agent
over a key. Contract: validation with fragments, coverage both ways, skill `--check`. Browser: the
scaffold's todo page, governed.

## 6. Rulings (15 November 2026: each recommendation accepted)

### 6.1 Replace the todo demo, or add a second example

**Ruled: replace it.** Two demos would leave the old model in the place people look first.
quorate and road-tracker carry the demo but depend on nothing in it (quorate mentions it only in
comments); each takes the new one at its next upgrade, or drops it.

### 6.2 Framework entries: fragments merged into the application's contract, or a separate contract

**Ruled: fragments merged.** One surface, one contract (D-04): the agents and session endpoints
are part of the application's API, under its alias, and a consumer should find them in its contract.

### 6.3 The contract version: from the table, or a constant in a package

road-tracker keeps a package constant and checks it against the file. **Ruled: the table,**
loaded with the document, so there is one source; the coverage check still compares file, table and
served document.

### 6.4 How much the demo shows

**Ruled:** keep it small: five actions, two views, the purge. Leave out change numbers and
polling (road-tracker shows them), and a uniqueness rule (`TITLE_TAKEN`) unless Simon wants one
integrity rule beyond the state rules; the four state rules already show refusal, staleness and
non-disclosure.

### 6.5 The admin API

`road_admin_api` also predates the definition (an idempotent no-op answers `granted: false`, refusals
are 403 or 409). **Ruled: a later patch.** Applications call it and road-blogger is live (F-06);
converting it is its own change with its own adoption plan. Until then the admin endpoints are listed
in the coverage check as outside the surface, with that reason.

### 6.6 Naming

**Ruled:** `road_surface_api` for the package, `road_contract` for the table, `contract/` for the
files, matching road-tracker's layout so its adoption is a rename.

### 6.7 road-tracker

**Ruled:** at its next road-kit upgrade, road-tracker replaces `rt_action_pkg`'s generic half and
`rt_rest_pkg` with `road_surface_api`, `rt_contract` with `road_contract`, and its scripts with the
framework's, keeping its own rules, tenancy and `rt` commands.

## 7. Build plan

1. `road_contract`, `road_surface_api` and its tests; `GET /contract/`.
2. The three scripts and the fragments; validator support for `x-road-include`.
3. The demo: contract, package, routes, generated modules, tests; the scaffold's todo page.
4. Agents on the demo: `road-cli` commands, generated skill, acceptance run; spec-patch-15's
   `road_agent_api` on the surface's contract version.
5. The checklist; `spec/error-handling-contract-v1.md` (version on every body),
   `spec/ords-api-design-standards-v1.md` (generated thin handlers), `PATTERNS.md`
   (`surface-contract-served`, `contract-handler-coverage`, `read-token-natural-key`,
   `generated-thin-handlers`); road-atlas RK-14 "not done" items closed, B-05 closed; a release.

road-blogger is live (F-06) and does not deploy the demo. Every framework change is additive:
`road_surface_api` is new, `error_api` is unchanged, and nothing changes for an application until
it adopts.

## 8. Out of scope

- **Row-level access**, the definition's section 8 (access enforced below the line): road-kit has no
  tenancy pattern yet (`planning/identity-model-gaps.md` section 2); quorate and road-tracker each
  have one. Its own patch, from them.
- **Batches and the database-user identity path:** spec-patch-14, awaiting ruling.
- **The MCP projector** reading 0.3.0 contracts (RK-11): its own patch, which this one's contract
  would feed.
- **The admin API** (6.5), and **agents under `external_oidc`** (spec-patch-15 section 9).

## 9. As built (15 November 2026)

Everything in sections 3 to 5 is built and tested on `ROAD_KIT_DEV`: `road_surface_api` (8 PL/SQL
tests), `demo_todo_api` (19), `road_agent_api` (8), `test/agents/surface.test.mjs` (26 HTTP checks),
`agents.test.mjs` (19), `road-cli.test.mjs` (15), one browser test, the coverage check (15 handlers,
15 contract entries), `bin/run-skill-acceptance.sh` (a fresh headless Claude Code session, 9 turns,
0.16 USD), and `todos.endpoint.sh` with fixture tokens. The checklist, `contract/checklist.md`, passes
29 of 35: three are not used (claims, events, batches) and three are not yet, all row-level access
below the line (27, 28, 30; section 8).

Where it differs from the plan:

1. **`todos.create` has a rule, `TITLE_TAKEN`.** The schema requires every action to declare at least
   one precondition, so "none" in 4.1 cannot validate. Section 6.4 had named `TITLE_TAKEN` as the
   one integrity rule to add if wanted; it is the smallest that fits (the caller has no other open
   todo with that title). Counting it, the demo has six rules.
2. **`todos.delete` carries a read token and a body, and its key is natural.** The schema requires
   an action that changes an existing record to declare a concurrency rule, which means a read token.
   4.1 had given it an Idempotency-Key and only `TODO_NOT_FOUND`. It now has `TODO_NOT_FOUND` and
   `STALE_TOKEN`, as `DELETE /todos/{id}/` with a JSON body, as road-tracker's claim release does.
3. **The purge is `POST /todos/purges/`**, a noun like the other actions, not `/todos/purge/`.
4. **The agents actions declare `changes_existing_record: false`.** Retiring an agent and revoking a
   key are idempotent end states keyed on the Idempotency-Key, with no read token (spec-patch-15), and
   the schema would otherwise demand a concurrency rule. Their request bodies are empty-object
   schemas, because the schema requires a body.
5. **`todos.get` answers 404, not a refusal, for a missing, hidden or deleted todo**, as every view
   does (definition 7); the actions answer 200 `TODO_NOT_FOUND`. Both are non-disclosing: no ids.
6. **`session.me` states `contract_version` and `as_at` but not `scope`.** Its body already has a
   `scope` field, the token's OAuth scope, and the view describes only the caller, so it declares
   `access_rules_apply: false`. `road_surface_api.envelope` leaves `scope` out when given a null.
7. **`record_not_found` takes the rule id** (`record_not_found(action, rule, message, key)`), where
   road-tracker's `item_not_found` and `project_not_found` were fixed. An accepted action returns a
   fresh read token in its result, so a caller can act again without another read.
8. **The contract is loaded by `97_demo.sql`, not the framework chain.** A framework-only deploy
   has no contract: `GET /contract/` answers 404 and `road_surface_api.contract_version` falls back
   to `c_framework_version` (`0.4.0`).
9. **There is no scaffold todo page to govern.** The plan's "browser: the scaffold's todo page" was a
   mistake: `hello_world/src` has no todos page. The browser test that exists is My agents, and it
   passes against the regenerated agents module.
10. **The session module stays hand-written** (one answer from several queries), but uses
    `road_surface_api` for 401, `Accept-Version`, the envelope and failures. The agents and todos
    modules are generated; `api/routes.mjs` lists only those.
11. **`generate-skill.mjs` merges fragments** before reading a contract, and `roleData` accepts the
    column aliases of a union's first row.

Found while building, worth knowing next time: a private package function cannot be called in SQL
(PLS-00231: `iso_or_null` and `principal_of` both hit it); `run-sql.sh` said SUCCESS twice with
compile errors in the log; `updated_at` is trigger-maintained, so a test cannot backdate a row (the
purge test waits a second instead); the same read token and todo replays the first accepted answer, so
a stale-token test needs a token from an earlier read.
