The ROAD core: React, ORDS, PL/SQL and Oracle AI Database, with no middleware. Apps copy from here.

The rules for this file are in `road-atlas/patterns/SPEC.md`. Check it with
`../road-atlas/bin/check-patterns.sh .`

## Database

### Secured session context
- **Slug:** road-session-context
- **Summary:** Each ORDS handler calls `begin_request` to load the caller's identity, roles and permissions into an application context that only one package can write to. Handlers then call `require_permission`. If the context was never loaded, every check fails.
- **Location:** `db/package_specs/road_ctx_pkg.pks`, `db/package_bodies/road_ctx_pkg.pkb`, `deploy/create/65_contexts.sql`, `spec/database-session-context-v1.md`
- **Status:** in-use
- **Notes:** Application contexts are database-wide, not per schema. `namespace()` gives each schema its own context name, so two apps on one ADB don't take over each other's context. Handler coverage is checked by `bin/check-handler-coverage.sh` (see `handler-coverage-check`).

### Principals, roles and permissions
- **Slug:** road-rbac
- **Summary:** Tables for principals, roles and permissions, plus an admin API to grant and revoke roles. Granting a reserved role needs an extra permission, so a user admin cannot promote anyone, themselves included, to system admin.
- **Location:** `db/tables/road_principals.create.sql`, `db/tables/road_roles.create.sql`, `db/tables/road_permissions.create.sql`, `db/tables/road_role_permissions.create.sql`, `db/tables/road_principal_roles.create.sql`, `db/package_specs/road_admin_api.pks`, `db/package_bodies/road_admin_api.pkb`, `api/modules/admin/module.create.sql`
- **Status:** in-use
- **Notes:** Depends on `road-session-context`. quorate holds a more advanced auth model that is owed back to road-kit (road-atlas ledger B-01).

### SQL assertions that guard the role model
- **Slug:** road-rbac-assertions
- **Summary:** Two `CREATE ASSERTION` constraints stop reserved permissions being attached to the wrong roles, and make sure some role can always grant roles. They run after the seed data, so a bad seed fails the deploy.
- **Location:** `deploy/create/96_assertions.sql`, `admin/grant-schema-privileges.sql`
- **Status:** in-use
- **Notes:** Needs the schema-scoped `CREATE ASSERTION` privilege, which Oracle AI Database 26ai provides. Pairs with `road-rbac`.

### Optimistic concurrency with read tokens
- **Slug:** read-token-concurrency
- **Summary:** A read returns a token, logged as a row in `road_api_log`. A later write passes the token back, and `check_fresh` rejects it if the record has changed since the read. The same row records the outcome for audit.
- **Location:** `db/package_specs/road_audit_api.pks`, `db/package_bodies/road_audit_api.pkb`, `db/tables/road_api_log.create.sql`
- **Status:** in-use
- **Notes:** `demo_todo_api` shows it in use (see `framework-canary-app`).

### Admin action audit
- **Slug:** admin-action-audit
- **Summary:** `log_admin_action` writes an audit row in an autonomous transaction, so the record survives a rolled-back operation. It takes the actor from the session context, never from a parameter, so a caller cannot misattribute what it did.
- **Location:** `db/package_specs/road_audit_api.pks`, `db/package_bodies/road_audit_api.pkb`, `db/tables/road_api_log.create.sql`
- **Status:** in-use
- **Notes:** Rejected business decisions are recorded the same way, autonomously, by `governed-decision-record`.

### Governed decision record
- **Slug:** governed-decision-record
- **Summary:** A governed action returns an outcome with HTTP 200, accepted or rejected, and never raises a business rejection. `road_decision_api` writes the decision record and builds the outcome: accepted records in the caller's transaction, rejected records in an autonomous one so they survive the rollback. The same table replays an earlier outcome for a repeated idempotency key.
- **Location:** `db/tables/road_decisions.create.sql`, `db/indexes/road_decisions_idempotency.create.sql`, `db/package_specs/road_decision_api.pks`, `db/package_bodies/road_decision_api.pkb`, `db/package_bodies/road_decision_api_test.pkb`, `planning/spec-patch-12-business-decisions-and-decision-record.md`
- **Status:** experimental
- **Notes:** Implements GSC definition 0.1.0 sections 6.4 to 6.7 and ledger D-05. `demo_todo_api` and `road_agent_api` use it over HTTP, through `road_surface_api` (`surface-contract-served`). Depends on `road-session-context` for the principal. Records decisions, not field changes (ledger F-12).

### Contract served from the database, version on every response
- **Slug:** surface-contract-served
- **Summary:** `scripts/contract-to-sql.mjs` validates the application's contract (with the framework fragments it includes) and loads it into `road_contract`. `GET /contract/` serves that document without a token. `road_surface_api` reads the version from the same row and stamps it on every body, errors included, and answers a wrong `Accept-Version` major with a 400. The file, the table, the served document and the responses cannot disagree.
- **Location:** `db/tables/road_contract.create.sql`, `db/package_specs/road_surface_api.pks`, `db/package_bodies/road_surface_api.pkb`, `scripts/contract-to-sql.mjs`, `scripts/lib/contract-merge.mjs`, `contract/fragments/`, `api/modules/contract/module.create.sql`
- **Status:** in-use
- **Notes:** From road-tracker's `rt_rest_pkg`, `rt_contract` and `rt_action_pkg` (ledger B-05). `error_api` is unchanged: `road_surface_api.fail` wraps it. Framework fragments (`road-agents`, `road-session`) are merged by the application's `x-road-include`, so a surface has one contract (ledger D-04). Depends on `governed-decision-record`.

### Read-token natural key
- **Slug:** read-token-natural-key
- **Summary:** An action on an existing record is idempotent on (principal, record id, read token). One read returns one token for many records, so a key made from the token alone would treat two proposals on different records from one read as a repeat. The same token and record replays the first accepted answer; a token from before a change gets `STALE_TOKEN`.
- **Location:** `db/package_specs/road_surface_api.pks`, `db/package_bodies/road_surface_api.pkb`, `db/package_bodies/demo_todo_api.pkb`, `db/package_bodies/road_surface_api_test.pkb`
- **Status:** in-use
- **Notes:** Extends `read-token-concurrency` and `governed-decision-record`. `demo_todo_api.decide` is the worked example: one shared decision shape for revise, complete, reopen and delete.

### Key-value framework settings
- **Slug:** road-config-table
- **Summary:** A narrow key-value table for framework settings that must outlast the JWT scaffold, such as the default role for new principals. Adding a setting doesn't need a schema change.
- **Location:** `db/tables/road_config.create.sql`, `db/triggers/road_config_updated_at.create.sql`
- **Status:** experimental
- **Notes:** Small. Included as the place framework settings go, rather than as reusable logic.

## API (ORDS)

### Error envelope
- **Slug:** error-envelope
- **Summary:** `error_api` turns an application error in the -20000 to -20999 range into a fixed JSON body and HTTP status. Any other exception is logged in full to `error_log` and returned as a generic 500, so no raw exception reaches a client.
- **Location:** `db/package_specs/error_api.pks`, `db/package_bodies/error_api.pkb`, `db/tables/error_log.create.sql`, `spec/error-handling-contract-v1.md`
- **Status:** in-use
- **Notes:** Wrong calls only (4xx). Since spec-patch-12 (ledger D-05) a business rejection is not an error: it returns 200 with an outcome through `governed-decision-record`. `-20003`/422 was removed.

### JSON in, JSON out packages
- **Slug:** json-package-boundary
- **Summary:** Application packages take native JSON and return native JSON, with no ref cursors or collections at the boundary. They check permissions themselves and never commit. A handler, an MCP tool or a batch job then calls the same code under the same rules, and tests can roll back.
- **Location:** `db/package_specs/road_admin_api.pks`, `db/package_specs/demo_todo_api.pks`, `db/package_bodies/demo_todo_api.pkb`, `api/modules/todos/module.create.sql`
- **Status:** in-use
- **Notes:** A convention more than a single piece of code. `demo_todo_api` is the smallest complete example.

## Auth and security

### Local JWT issuer for development
- **Slug:** jwt-scaffold-issuer
- **Summary:** PL/SQL that signs RS256 JWTs, publishes a JWKS document and registers ORDS's trust in them, so an app has working login with no external identity provider. Token overrides let tests build expired, wrong-issuer and wrong-audience tokens.
- **Location:** `db/package_specs/jwt_scaffold_auth_api.pks`, `db/package_bodies/jwt_scaffold_auth_api.pkb`, `db/tables/jwt_scaffold_config.create.sql`, `db/tables/jwt_scaffold_credentials.create.sql`, `api/modules/auth/module.create.sql`, `deploy/create/80_standalone.sql.tmpl`, `spec/authentication-spec-v1.md`
- **Status:** in-use
- **Notes:** Development only. It is dropped when a deployment switches to `external_oidc` (see `auth-provider-profiles`).

### PBKDF2 in PL/SQL
- **Slug:** plsql-pbkdf2
- **Summary:** PBKDF2-HMAC-SHA256 written in PL/SQL, because `DBMS_CRYPTO` on 26ai has no key-derivation function. Each stored hash records its iteration count and algorithm, so the count can be raised without breaking existing passwords.
- **Location:** `db/package_specs/jwt_scaffold_crypto.pks`, `db/package_bodies/jwt_scaffold_crypto.pkb`, `db/package_bodies/jwt_scaffold_crypto_test.pkb`
- **Status:** in-use
- **Notes:** `set-password-offline` holds a second implementation that must agree with this one. Both are pinned to the same published test vector.

### Setting a password without sending it to the database
- **Slug:** set-password-offline
- **Summary:** A script that reads a password from the terminal, derives the PBKDF2 hash locally with Python's standard library, and sends only hex to the database. The plaintext never appears in SQL, logs, process arguments or shell history.
- **Location:** `bin/set-principal-password.sh`
- **Status:** in-use
- **Notes:** Run `--self-test` after changing either PBKDF2 implementation. Pairs with `plsql-pbkdf2`.

### Per-environment signing key
- **Slug:** per-env-signing-key
- **Summary:** Generates each environment's RSA signing key with openssl and pipes it straight into the database. The key is never written to a file or committed.
- **Location:** `bin/ensure-auth-key.sh`
- **Status:** in-use
- **Notes:** Replaced an earlier setup where one key was committed and shared by every environment.

### Switchable auth provider profiles
- **Slug:** auth-provider-profiles
- **Summary:** `AUTH_PROFILE` chooses between the local JWT scaffold and an external OIDC provider such as Auth0 at deploy time. The script renders the ORDS JWT profile registration, and decides whether the scaffold's login endpoint is deployed at all.
- **Location:** `bin/render-auth-config.sh`, `deploy/create/80_standalone.sql.tmpl`, `deploy/create/80_standalone.external_oidc.sql.tmpl`, `spec/authentication-spec-v1.md`
- **Status:** in-use
- **Notes:** road-blogger runs `external_oidc` in production. quorate holds the end-user Auth0 flow for single-page apps (ledger L-01).

### Agents with API keys, traded for short-lived tokens
- **Slug:** api-key-exchange
- **Summary:** A person makes an agent of their own, a separate principal they own that holds only the application's agent role, and makes API keys for it. A key is shown once and stored as a SHA-256 hash, and is added to the answer only after the decision is recorded, so the decision record never holds it. A tool trades the key at a public endpoint for a short-lived JWT that ORDS validates like any other; revoking the key, retiring the agent or suspending its owner stops new tokens at once.
- **Location:** `db/package_bodies/road_agent_api.pkb`, `db/tables/road_agents.create.sql`, `db/tables/road_api_keys.create.sql`, `api/modules/agents/`, `api/modules/api_auth/`, `hello_world/src/pages/AgentsPage.tsx`, `planning/spec-patch-15-agent-api-keys-and-cli.md`
- **Status:** experimental
- **Notes:** From road-tracker (ledger B-04), where keys sit under its tenant isolation policy. ORDS accepts only JWTs as bearer tokens, hence the exchange. Scaffold profile only (`spec/authentication-spec-v1.md` 11.6). An agent role should include `session.me.read`.

### A command-line core applications extend
- **Slug:** road-cli-core
- **Summary:** `tools/road-cli/road-cli` signs in with an agent's API key, keeps the token, makes calls, turns a governed outcome into a result or a refusal (exit 3), reads a record before changing it and retries once on a stale read. Each application adds task commands in `commands.js` beside it, one per step of the work, each printing one line, so an agent spends few turns and no tokens on bookkeeping.
- **Location:** `tools/road-cli/`, `test/agents/road-cli.test.mjs`
- **Status:** experimental
- **Notes:** road-tracker's `rt` is the fuller example (`next`, `claim`, `done`, `file`). Read standard input as a stream: `readFileSync(0)` fails with EAGAIN on a pipe. Ask for a key with echo off, never on the command line.

### Agent skill generated from the contract
- **Slug:** skill-from-contract
- **Summary:** `scripts/generate-skill.mjs` writes an application's Claude Code skill around its road-cli commands from its Governed Surface Contract and the agent role's permissions. It fails when a command calls a resource the contract lacks or the agent may not use, leaves out what the contract keeps from consumers, and `--check` fails when the skill is stale.
- **Location:** `scripts/generate-skill.mjs`, `test/skill/generate-skill.test.mjs`, `skills/hello_world/skill.config.mjs`, `skills/hello_world/SKILL.md`, `bin/run-skill-acceptance.sh`
- **Status:** in-use
- **Notes:** Meets the gsc checklist's items 33 and 34 without MCP. `bin/run-skill-acceptance.sh` is the acceptance test: a fresh headless session uses the generated skill (about 0.16 USD, 9 turns, 25 seconds on the demo). In road-tracker a fresh headless Claude Code session using the skill worked an item end to end for about 0.31 USD; the cost of an agent task is mostly its number of turns.

### Check that every handler loads the session context
- **Slug:** handler-coverage-check
- **Summary:** A static check that every ORDS handler on a protected module calls `begin_request`. Otherwise a handler runs with whatever identity the pooled connection last held.
- **Location:** `bin/check-handler-coverage.sh`
- **Status:** in-use
- **Notes:** Needed because ORDS gives a schema no pre-dispatch hook. Pairs with `road-session-context`.

### Check that every handler has a contract entry and every entry a handler
- **Slug:** contract-handler-coverage
- **Summary:** Reads the deployed ORDS handlers from `USER_ORDS_HANDLERS` and the contract, and fails unless each handler has a contract entry and each entry a handler. It also checks that the contract version is the same in the file, the table and the served document. Public and framework endpoints are listed as outside the surface, each with a reason.
- **Location:** `test/contract/check-contract-coverage.mjs`, `test/contract/read-deployed-surface.sql`
- **Status:** in-use
- **Notes:** GSC definition 9.5. From road-tracker. Read-only, through `bin/run-sql.sh`. Pairs with `generated-thin-handlers`.

### Thin ORDS handlers generated from a route list
- **Slug:** generated-thin-handlers
- **Summary:** `scripts/generate-modules.mjs` writes an application's ORDS modules from `api/routes.mjs`. Every handler has one shape: establish the session or answer 401, check `Accept-Version`, make one package call, respond, and send any failure through `road_surface_api.fail`. No business rule can live in a handler. `--check` fails when a generated file was edited by hand.
- **Location:** `scripts/generate-modules.mjs`, `api/routes.mjs`, `api/modules/todos/module.create.sql`, `api/modules/agents/module.create.sql`
- **Status:** in-use
- **Notes:** GSC definition 6.3. Privileges stay hand-written. Handlers that build one answer from several queries (`session`) and the public ones stay hand-written too. `bin/check-handler-coverage.sh` still checks the generated files.

### Schema user setup
- **Slug:** schema-user-setup
- **Summary:** Admin scripts that create an application schema user and grant it exactly the privileges road-kit needs, including schema-scoped `CREATE ASSERTION`.
- **Location:** `admin/create-schema-user.sql`, `admin/grant-schema-privileges.sql`, `admin/drop-schema-user.sql`, `admin/README.md`
- **Status:** in-use

## UI

### React login shell
- **Slug:** react-auth-shell
- **Summary:** A React starter with a fetch client that attaches the bearer token, a login page, and a route guard that redirects to login when there is no token. Runtime settings come from one config module.
- **Location:** `hello_world/src/api/client.ts`, `hello_world/src/api/auth.ts`, `hello_world/src/components/RequireAuth.tsx`, `hello_world/src/config/runtime.ts`, `hello_world/src/router.tsx`, `hello_world/src/pages/LoginPage.tsx`
- **Status:** in-use
- **Notes:** The sign-in page (`LoginPage.tsx`) sits outside the app shell and lands on Home. Since spec-patch-17 the client sends `Accept-Version` (from `config/runtime.ts`) and, on a 401 for a call that carried a token, clears the token and redirects to Login with no banner (`spec/error-handling-contract-v1.md` 6.5).

### React client for a governed surface
- **Slug:** react-governed-client
- **Summary:** A page that proposes governed actions and reads the answers in one place. `utils/outcome.ts` reads a decision; `hooks/useTodos.ts` holds the list, its read token and one `settle` function: accepted reloads the list, a rejection shows the database's own message, a stale token keeps the person's edit in the form and says so. A create keeps its Idempotency-Key until an accepted answer replaces it.
- **Location:** `hello_world/src/api/todos.ts`, `hello_world/src/hooks/useTodos.ts`, `hello_world/src/utils/outcome.ts`, `hello_world/src/components/todos/`, `hello_world/src/pages/TodosPage.tsx`, `hello_world/e2e/todos.smoke.spec.ts`
- **Status:** in-use
- **Notes:** spec-patch-17. Follows road-tracker's `settle`. Depends on `governed-decision-record` and `read-token-concurrency`. The browser test covers the stale-token path, a keyboard-only add and a 320-pixel width.

### Theme tokens and their check
- **Slug:** theme-token-check
- **Summary:** Colours and fonts live only in `tokens.css` and the app's `brand.css`, and the Tailwind and shadcn theme reads from them. `tokens.css` holds the light and dark values, the derived shades and the chart colours. A script fails the build if a colour appears anywhere else, if `brand.css` sets a name `tokens.css` does not define, if `tokens.css` or `theme.css` differs from road-kit's, or if a text, status or chart colour falls below its contrast ratio in either theme.
- **Location:** `hello_world/src/tokens.css`, `hello_world/src/theme.css`, `hello_world/src/brand.css`, `hello_world/scripts/check-theme-tokens.mjs`
- **Status:** in-use
- **Notes:** Written after quorate's stylesheet drifted to nearly twice the size of road-kit's while the standard said they were identical. Ledger D-02. Extended by spec-patch-18 (ADR 02). The contrast check computes the `color-mix()` shades itself, in OKLab, so it needs no browser.

### Per-app look in one file
- **Slug:** road-brand-override
- **Summary:** An app changes its colours, fonts and corner radius in `src/brand.css`, which may set only tokens that `tokens.css` defines. The derived shades (hover, selected tint, primary hover) follow from what it sets. The app's name, mark, layout and nav are in `src/config/app.ts` and `components/road/AppMark.tsx`.
- **Location:** `hello_world/src/brand.css`, `hello_world/src/config/app.ts`, `hello_world/src/components/road/AppMark.tsx`
- **Status:** in-use
- **Notes:** ADR 02. ai-live-hub's `theme/brand.ts` does the same job from a database row. Dark values go under `:root.dark` in `brand.css`; a value set only in `:root` does not reach the dark theme.

### App shell with top bar or sidebar
- **Slug:** road-app-shell
- **Summary:** The frame around every signed-in screen: a top bar or a sidebar (set in `config/app.ts`), a bottom tab bar below 768 px, a skip link, the account menu, the session drawer and a toaster. Pages render into it. Shared page parts: page header, stat tile, status badge, notice, empty state, data list and segmented control.
- **Location:** `hello_world/src/components/road/`, `hello_world/src/router.tsx`, `hello_world/e2e/shell.smoke.spec.ts`
- **Status:** in-use
- **Notes:** ADR 02, spec-patch-18. The theme switch is `hooks/useTheme.ts` (light, dark or system, kept in localStorage; `index.html` sets the class before first paint). Browser tests cover keyboard use, the theme, 320 px and an axe scan in both themes.

### Session details behind the account menu
- **Slug:** road-account-menu-session-drawer
- **Summary:** The signed-in person's menu (session details, agents, theme, sign out) opens a side panel with the principal, token and connection facts read from `/session/me/`, each with a copy button. Focus returns to the menu button when the panel closes.
- **Location:** `hello_world/src/components/road/AccountMenu.tsx`, `hello_world/src/components/road/SessionDrawer.tsx`, `hello_world/src/components/road/SessionSections.tsx`, `hello_world/src/hooks/useSession.ts`, `hello_world/src/pages/SessionPage.tsx`
- **Status:** in-use
- **Notes:** ADR 02. Replaces the build settings and session data that the old home page showed. The `/session` route renders the same facts as a page.

## AI

### Governed State Contract schema
- **Slug:** governed-state-contract
- **Summary:** A JSON Schema for declaring a governed action: who may call it, its request, its preconditions, the outcomes it can return, and the audit and events it produces. Any client, including an AI agent, then works under the same rules. A validator checks contracts against the schema.
- **Location:** `spec/governed-state-contract.schema.json`, `test/contract/validate-governed-state-contract-schema.mjs`, `test/contract/fixtures/governed-state-contract.valid.json`
- **Status:** superseded
- **Notes:** Released as v0.1.0 (W1), and that tag is unchanged. Superseded by `governed-surface-contract`, which describes a whole surface and reuses this action shape with the changes in spec-patch-13 section 3.

### Governed Surface Contract schema
- **Slug:** governed-surface-contract
- **Summary:** A JSON Schema for one contract per surface: a shared envelope (identity, versioning, bindings), a state section of governed actions and an optional batch, and a publication section of governed views. A dependency-free validator checks a contract against the schema and checks the cross-references the schema cannot express.
- **Location:** `spec/governed-surface-contract.schema.json`, `scripts/validate-gsc-contract.mjs`, `scripts/lib/json-schema-subset.mjs`, `test/contract/validate-governed-surface-contract-schema.mjs`, `test/contract/fixtures/governed-surface-contract.valid.json`, `planning/spec-patch-13-governed-surface-contract-schema.md`
- **Status:** experimental
- **Notes:** Draft. Implements GSC definition 0.1.0; the publication section and batch are Provisional there. No surface has a contract written to it yet, and the MCP projector does not read it yet.

### MCP tool descriptor from a contract
- **Slug:** mcp-descriptor-projection
- **Summary:** Turns a Governed State Contract into an MCP tool descriptor (name, description and input schema), with the same output every time, so an agent's tool list is derived from the contract and never written by hand.
- **Location:** `scripts/project-mcp-descriptor.mjs`, `test/mcp/validate-mcp-descriptor-projection.mjs`
- **Status:** demo
- **Notes:** Released as v0.2.0 (W2). Depends on `governed-state-contract`.

## Deployment and tooling

### SQL runner with INTENT blocks and history
- **Slug:** run-sql-with-history
- **Summary:** All database work goes through `run-sql.sh`. Each script states its intent in a header, and every run is recorded in a SQLite history that can be searched by task, object name or Oracle error before trying something again.
- **Location:** `bin/run-sql.sh`, `bin/db-history-common.sh`, `bin/db-history-similar.sh`, `bin/db-history-failures.sh`, `skills/sql-runner/SKILL.md`, `skills/sql-runner/scripts/install-sql-runner.sh`
- **Status:** in-use
- **Notes:** This is an installed copy. The canonical entries are in sql-runner's catalogue: `sqlcl-audited-run`, `sql-intent-block`, `sqlite-run-history`, `run-history-search` and `sql-runner-installer`. Make changes in sql-runner and reinstall, because reinstalling overwrites local edits.

### Ordered deploy stages with rerunnable scripts
- **Slug:** ordered-deploy-stages
- **Summary:** Deployment runs numbered stages in a fixed order, from types and tables through packages, REST modules, seed data and assertions to a final verify. Each object's create script tolerates the object already existing, so a deploy can be rerun.
- **Location:** `deploy/create/00_full.sql`, `deploy/create/99_verify.sql`, `db/tables/road_config.create.sql`, `db/tables/road_config.drop.sql`
- **Status:** in-use
- **Notes:** Ledger F-10 records which of road-kit's own scripts still lacked the error tolerance.

### React app served from the database
- **Slug:** spa-from-database
- **Summary:** The built React app is uploaded into a database table, and an ORDS module serves it: real files by path, with `index.html` for any other route. A missing asset returns a real 404, not the app shell.
- **Location:** `bin/deploy-react.sh`, `db/tables/ui_assets.create.sql`, `db/package_specs/ui_assets_api.pks`, `db/package_bodies/ui_assets_api.pkb`, `api/modules/ui/module.create.sql`, `spec/file-upload-and-ui-delivery-spec-v1.md`
- **Status:** in-use
- **Notes:** ORDS retries a wildcard GET with a trailing slash when the first attempt returns no rows. The module strips it so the retry resolves to the same file (ledger F-11).

### Parity check between copied repos
- **Slug:** repo-parity-check
- **Summary:** Compares the files that road-kit and road-cal are meant to hold identically, and reports any that differ.
- **Location:** `bin/check-road-kit-parity.sh`
- **Status:** experimental
- **Notes:** Ledger F-08 records a case it misses. road-cal is parked, so the script may only be worth reusing as a template for other copied pairs.

## Testing

### PL/SQL test packages
- **Slug:** plsql-test-packages
- **Summary:** Each package has a `_test` partner with a `run_all` procedure. Tests run against the deployed schema and roll back to a savepoint, so they leave no data behind.
- **Location:** `db/package_specs/road_ctx_pkg_test.pks`, `db/package_bodies/road_ctx_pkg_test.pkb`, `db/package_bodies/road_admin_api_test.pkb`, `deploy/test/00_test_setup.sql`, `test/smoke/00_smoke.sql`, `spec/automated-testing-strategy-v1.md`
- **Status:** in-use

### HTTP endpoint tests with real tokens
- **Slug:** endpoint-test-suite
- **Summary:** Shell tests that call the deployed ORDS endpoints with real tokens and check status codes and response bodies. They include an auth conformance suite that sends expired, wrong-issuer and wrong-audience tokens.
- **Location:** `bin/run-endpoint-tests.sh`, `bin/assert-http.sh`, `bin/get-test-token.sh`, `test/endpoint/00_endpoint.sh`, `test/endpoint/auth-conformance.endpoint.sh`
- **Status:** in-use

### Browser smoke test
- **Slug:** browser-smoke-test
- **Summary:** A Playwright test that logs in through the real React app against a deployed environment.
- **Location:** `bin/run-browser-smoke.sh`, `hello_world/e2e/login.smoke.spec.ts`
- **Status:** in-use

### Demo app that tests the framework
- **Slug:** framework-canary-app
- **Summary:** A to-do app, built as a governed surface with its own contract, that exercises every part of the framework an adopter uses: permission checks, an app role, a reserved permission, per-user ownership, read tokens, decision records, agents and a generated skill. If the framework breaks, the demo fails. It is the reference implementation of the Governed Surface Contract.
- **Location:** `db/package_specs/demo_todo_api.pks`, `db/package_bodies/demo_todo_api.pkb`, `db/package_bodies/demo_todo_api_test.pkb`, `api/routes.mjs`, `api/modules/todos/module.create.sql`, `contract/hello_world.gsc.json`, `contract/checklist.md`, `skills/hello_world/SKILL.md`, `deploy/create/97_demo.sql`, `test/endpoint/todos.endpoint.sh`, `test/agents/surface.test.mjs`
- **Status:** demo
- **Notes:** By its own rule the demo may never cause a framework change. Nobody should build on it.
