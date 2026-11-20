# Handoff: state on 19 November 2026

Read this after `AGENTS.md`. It records where road-kit stands and where the next session starts.

## Spec-patch 14 (20 November): identity path built, batches deferred

Simon reviewed the batch design and ruled it too much for the framework: a batch is application PL/SQL
with local variables and a savepoint. Spec-patch 14 now covers only `road_ctx_pkg.begin_database_request`
(built, `road_ctx_pkg_test` 15 tests and all framework suites pass on dev). Not tested: the accepted path,
which needs a second database user. Not committed. Atlas B-02 is updated (road-kit `partial`).

## Start here: spec-patches 15 to 17 are committed; spec-patch 18 is next

Spec-patch 16 (`planning/spec-patch-16-gsc-reference-implementation.md`) makes road-kit the reference
implementation of the gsc definition. It is built, tested on `ROAD_KIT_DEV` and committed
(`4ce6b4a`). Section 9 of the spec says where the build differs from the plan.

Spec-patch 17 (`planning/spec-patch-17-todo-page.md`) is built, tested and committed (`0dddb22`): a Todos page
in `hello_world` that uses the governed todo API (list, add, edit, done, reopen, delete; stale tokens
and refusals shown as answers). `client.ts` now sends `Accept-Version: 0` and, on a 401, clears the
token and goes to Login. `bin/run-agent-tests.sh` runs its browser test, `e2e/todos.smoke.spec.ts`,
beside My agents.

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
- Atlas B-05 and RK-14 are updated in `../road-atlas`; neither is closed until a release.

Next, in order:

1. **Release.** Tag `v0.4.0` covers spec-patches 15 to 17. Then close B-05 in the atlas.
2. **Spec-patch 18** (below): review and merge; it is built.
3. **Adoption.** road-tracker replaces the generic half of its `rt_action_pkg` and `rt_rest_pkg`,
   `rt_contract` and its scripts with road-kit's at its next upgrade (spec-patch-16 section 6.7).
   Uncomment the spec-patch-15 and 16 lines in `bin/check-road-kit-parity.sh` in that commit.
4. **Default look and components (ADR 02, accepted 2026-11-19).** `planning/adr-02-default-look-and-components.md`:
   road-kit now ships the app shell, components and palette, and each app overrides the look in
   `src/brand.css`. Spec-patch 18 (`planning/spec-patch-18-default-look-and-shell.md`) builds it
   in `hello_world`, from the design canvas https://claude.ai/artifact/4wztTJzttNDT1pLH6Mp2ks.
   Ruled 19 November (all eight recommendations in section 11 accepted) and **built** the same day,
   tested on dev (build, theme check, nine browser tests); section 12 lists where the build differs.
   The login smoke test and the endpoint suite also pass on dev (19 November). Atlas D-02 is amended, and ADR 02 is copied into the six repos that hold ADR 01 (committed there, not pushed).
5. **Spec-patch 9 (provider profiles).** Ruled 19 November: finish under the self-issued JWT only. The
   §12 conformance rows already pass under the scaffold (build plan 09, phase 6). Left: a from-empty
   drop-and-rebuild of `ROAD_KIT_DEV`, which also removes the dev test passwords (set `ADMIN`'s again
   with `bin/set-principal-password.sh`). The `external_oidc` position and phase 7 adoption are deferred.
6. **Spec-patches 10 and 11 are withdrawn** (19 November): the todo demo stays a simple list, with its
   contract describing only what that app needs, and Simon ruled that it satisfies the proof plan's
   W3. Events are left to one of the more complex apps. Open for Simon: W4's wording, which still ends
   in an event, and whether the three row-level access items (checklist 27, 28, 30) matter for a
   simple per-user todo list.
7. **Later patches:** the admin API converted to decisions (6.5); row-level access (checklist 27, 28,
   30); the MCP projector for 0.3.0 contracts (RK-11); batches (deferred 20 November; spec-patch-14 section 6 lists what is open).

## How to test

- Framework PL/SQL, all suites: `bin/run-sql.sh --env dev --script test/plsql/run-framework-tests.sql`.
- Agents, the governed surface, `road-cli` and the My agents, Todos and app shell pages, with fixtures made and removed, no
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

- **The endpoint and login tests need `config/local.env` loaded.** `bin/run-endpoint-tests.sh` and
  `bin/run-browser-smoke.sh` do not source it themselves: run `source config/local.env` first. Both
  passed on dev on 19 November, after the ADMIN test password was reset
  (`bin/set-principal-password.sh --env dev --subject ADMIN`) and `ROAD_TEST_PASSWORD` was added.
- **Agents work under the scaffold profile only** (`spec/authentication-spec-v1.md` 11.6).
- **Parity:** the new framework files are listed, commented, in `bin/check-road-kit-parity.sh`.

## Waiting on Simon

- Commit of spec-patch 14 (identity path only; built and tested on dev 20 November, uncommitted).
- Pushing `main` and the `v0.4.0` tag (local, on the commit before spec-patch 18).
