# Handoff: state on 15 November 2026

Read this after `AGENTS.md`. It records where road-kit stands and where the next session starts.

## Start here: spec-patch 16 is built; a release is Simon's call

Spec-patch 16 (`planning/spec-patch-16-gsc-reference-implementation.md`) makes road-kit the reference
implementation of the gsc definition. It is **built and tested on `ROAD_KIT_DEV`, not committed, not
tagged** at the time of writing. Section 9 of the spec says where the build differs from the plan.

What exists now:

- `road_contract` and `road_surface_api`; `GET /contract/` (public); the contract version on every
  body, errors included; `Accept-Version`.
- `scripts/contract-to-sql.mjs`, `scripts/generate-modules.mjs` (routes in `api/routes.mjs`),
  `scripts/lib/contract-merge.mjs`, `test/contract/check-contract-coverage.mjs`.
- Contract fragments `contract/fragments/road-agents.json` and `road-session.json`, merged into an
  application's contract by its `x-road-include`.
- The todo demo as a governed surface: `contract/hello_world.gsc.json`, `demo_todo_api` rebuilt,
  generated `todos` and `agents` modules, `road-cli` commands (`todos`, `todo-add`, `todo-done`,
  `todo-reopen`), the generated skill `skills/hello_world/`, and `contract/checklist.md` (29 of 35
  pass; 3 not used; 3 not yet, all row-level access).
- Atlas B-05 and RK-14 are updated (uncommitted in `../road-atlas`); neither is closed until a release.

Next, in order:

1. **Review and commit** the working tree. Nothing from this build is committed. Tag atlas
   `Atlas-Id: B-05` and `RK-14` in the commit.
2. **Release** (Simon). Spec-patch 15 is not tagged either; one tag can cover both. Then close B-05.
3. **Adoption.** road-tracker replaces the generic half of its `rt_action_pkg` and `rt_rest_pkg`,
   `rt_contract` and its scripts with road-kit's at its next upgrade (spec-patch-16 section 6.7).
   Uncomment the spec-patch-15 and 16 lines in `bin/check-road-kit-parity.sh` in that commit.
4. **Later patches:** the admin API converted to decisions (6.5); row-level access (checklist 27, 28,
   30); the MCP projector for 0.3.0 contracts (RK-11); batches (spec-patch-14, unruled).

## How to test

- Framework PL/SQL, all suites: `bin/run-sql.sh --env dev --script test/plsql/run-framework-tests.sql`.
- Agents, the governed surface, `road-cli` and the My agents page, with fixtures made and removed, no
  password: `bin/run-agent-tests.sh --env dev`. It reuses a Playwright browser folder if
  `PLAYWRIGHT_BROWSERS_PATH` names one (road-tracker's `.playwright-browsers` has version 1217).
- A fresh Claude Code session using the generated skill (costs about 0.16 USD):
  `bin/run-skill-acceptance.sh --env dev`.
- Contract: `node scripts/validate-gsc-contract.mjs contract/hello_world.gsc.json`;
  `node test/contract/check-contract-coverage.mjs --env dev` (deployed handlers against the contract);
  `node scripts/generate-modules.mjs --check`; `node scripts/generate-skill.mjs skills/hello_world/skill.config.mjs --check`;
  `node test/skill/generate-skill.test.mjs`; `bin/check-handler-coverage.sh`.
- After changing the contract: `node scripts/contract-to-sql.mjs`, then
  `bin/run-sql.sh --env dev --script deploy/create/generated/96_contract.sql`.
- `bin/run-sql.sh` reports SUCCESS when a package fails to compile: read the log's `USER_ERRORS_CHECK`.
- A private package function cannot be called inside SQL (PLS-00231).

`ROAD_KIT_DEV` is on QuorateDB, which holds live data (atlas F-07): work only in that schema.

## Open

- **`bin/run-endpoint-tests.sh` has not been run** since spec-patch 15: it needs `ROAD_TEST_PASSWORD`
  in `config/local.env` (gitignored; it holds only `ROAD_ORDS_HOST` and `AUTH_PROFILE`). Simon's to add.
  `test/endpoint/todos.endpoint.sh` was rewritten for the governed demo and passes when run by hand with
  fixture tokens.
- **Agents work under the scaffold profile only** (`spec/authentication-spec-v1.md` 11.6).
- **Parity:** the new framework files are listed, commented, in `bin/check-road-kit-parity.sh`.

## Waiting on Simon

- Spec-patch 14 (batches and the database-user identity path): written 14 November, not ruled.
- `ROAD_TEST_PASSWORD` for the endpoint suite.
- A release tag, and whether spec-patch 15 and 16 go in one.
