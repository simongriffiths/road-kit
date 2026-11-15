# Handoff: state on 15 November 2026

Read this after `AGENTS.md`. It records where road-kit stands and where the next session starts.

## Start here: build spec-patch 16

`planning/spec-patch-16-gsc-reference-implementation.md`, ruled 15 November 2026 with every
recommendation accepted, not built. It makes road-kit the reference implementation of the gsc
definition: road-tracker's contract serving and checking pieces as framework (`road_surface_api`,
`road_contract`, `GET /contract/`, generated thin handlers, contract-to-handler coverage), contract
fragments for the agents and session endpoints, and the todo demo rebuilt as a governed surface with
its own contract, agents, `road-cli` commands, a generated skill and the gsc checklist. Section 7 is
the build plan, in order.

Sources to copy from and make generic, all in `../road-tracker` (contract 0.8.0, its Release 1 checks
in `planning/release-checks-r1.md`):

| road-kit piece | road-tracker source |
|---|---|
| `road_surface_api` | `db/package_specs/rt_action_pkg.pks` and body (natural key, tokens, accept/reject, not-found), `rt_rest_pkg` (respond, fail with the version, `version_ok`, `contract`) |
| `road_contract`, `scripts/contract-to-sql.mjs` | `db/tables/rt_contract.create.sql`, `scripts/contract-to-sql.mjs` |
| `scripts/generate-modules.mjs` | `scripts/generate-modules.mjs` (route list, one handler shape) |
| `test/contract/check-contract-coverage.mjs` | the same file and `test/contract/read-deployed-surface.sql` |
| The demo's contract and checks | `contract/road-tracker.gsc.json`, `test/contract/check-road-tracker-contract.mjs`, `contract/checklist.md` |
| The demo's agent skill | `scripts/generate-skill.mjs` here (spec-patch 15) and road-tracker's `skills/road-tracker/` |
| Acceptance in a fresh session | `bin/run-skill-acceptance.sh` and `test/skill/` there |

Lessons from road-tracker that apply: a private package function cannot be called inside SQL
(PLS-00231); MERGE fails a VPD check option whose predicate has a subquery (atlas F-17); ORDS reserves
the `q` query parameter (F-16); `bin/run-sql.sh` reports SUCCESS when a package fails to compile, so
read the log's `USER_ERRORS_CHECK` section; a headless Claude Code session ignores an untrusted
folder's settings, so pass `--allowedTools` on the command line.

## Spec-patch 15: built, not released

Agents, API keys, `/api-auth/tokens`, the My agents page, `tools/road-cli/` and
`scripts/generate-skill.mjs`, built and tested on `ROAD_KIT_DEV` (commit `1264ebd`). Open:

- **Not tagged.** A release (and atlas RK-15) waits for Simon; spec-patch 16 may go in the same one.
- **road-kit's own endpoint suite was not rerun** after it: `bin/run-endpoint-tests.sh` needs
  `ROAD_TEST_PASSWORD` in `config/local.env` (gitignored; it holds only `ROAD_ORDS_HOST` and
  `AUTH_PROFILE` so far). Simon's to add.
- **Agents work under the scaffold profile only** (`spec/authentication-spec-v1.md` 11.6).
- **Parity:** the new framework files are listed, commented, in `bin/check-road-kit-parity.sh`.
- **road-tracker** has its own tenancy-aware version and adopts road-kit's at its next upgrade
  (spec-patch 15 section 6.7).

## How to test

- Framework PL/SQL, all suites: `bin/run-sql.sh --env dev --script test/plsql/run-framework-tests.sql`.
- Agents, keys, `road-cli` and the My agents page, with fixtures made and removed, no password:
  `bin/run-agent-tests.sh --env dev`. It reuses a Playwright browser folder if
  `PLAYWRIGHT_BROWSERS_PATH` names one (road-tracker's `.playwright-browsers` has version 1217).
- Skill generator: `node test/skill/generate-skill.test.mjs`.
- Handler coverage: `bin/check-handler-coverage.sh`.

`ROAD_KIT_DEV` is on QuorateDB, which holds live data (atlas F-07): work only in that schema.

## Waiting on Simon

- Spec-patch 14 (batches and the database-user identity path): written 14 November, not ruled.
- `ROAD_TEST_PASSWORD` for the endpoint suite, above.
