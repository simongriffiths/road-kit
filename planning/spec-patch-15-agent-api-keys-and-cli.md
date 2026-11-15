# Specification Patch 15 — Agent API Keys and the Command-Line Tool

**Applies to:** framework surface. A new table `road_api_keys`, a new package `road_api_key_api`, a
new public ORDS module `/api-auth/`, three governed admin actions, an admin page in the React
scaffold, and two new tools: `tools/road-cli/` (a command-line core that applications extend with
task commands) and `scripts/generate-skill.mjs` (a Claude Code skill generated from a contract).
**Status:** design, 15 November 2026. Not built. Section 6 recommends an answer to each open point;
each needs Simon's ruling before building.
**Decisions it implements:** road-atlas ledger B-04 (road-tracker's agent API keys and `rt` tool are
owed to road-kit). It follows the Governed Surface Contract definition 0.1.0 (draft), sections 5.2
(the acting principal is always the one evaluated) and 9 (generated artefacts).
**Depends on:** spec-patch-12 (`road_decision_api`), spec-patch-13 (the contract schema). It sits
beside spec-patch-14's database-user identity path; section 3 says how.
**Proven in:** road-tracker, contract 0.8.0, 15 November 2026: `rt_agent_key_api`,
`api/modules/agent_auth`, `skills/road-tracker/rt`, `scripts/generate-skill.mjs`, and a fresh
headless Claude Code session that worked an item end to end with an API key
(`road-tracker/planning/release-checks-r1.md`, acceptance test 12).

---

## 1. What this is

An agent, such as Claude Code on a developer's machine, works an application's governed REST
surface as its own principal. Today road-kit gives it two poor options: a token minted by a script
for a fixed time (`bin/get-test-token.sh`), or the raw API, which costs it many calls and tokens.

This patch adds the model cloud services use, and the tooling that makes it cheap for an agent:

1. **API keys.** An administrator makes a key for a principal in the app, names it for where it will
   run, and copies it once. Only a SHA-256 hash is stored. Revoking it stops it at once.
2. **The key exchange.** A tool trades the key at a public endpoint for a short-lived JWT, which ORDS
   validates like any other bearer token. ORDS accepts only JWTs, so a raw key cannot be the bearer
   credential.
3. **A command-line core.** `road-cli` signs in with the key, keeps the token, makes governed calls
   (read tokens, idempotency keys, one retry on a stale token) and prints one line per answer. Each
   application adds its own task commands; road-tracker's `rt next / claim / show / done / file` is
   the reference.
4. **A skill generated from the contract.** A short Claude Code skill around the tool, generated
   from the contract and checked against the tool's calls, with a `--check` mode for staleness.

## 2. Why

Research on current practice for agent access (15 November 2026; Anthropic's "Writing effective
tools for agents" and "Code execution with MCP", the MCP authorization specification, and vendor
guidance on agent identity) agrees on: task-level tools rather than one per endpoint; short, filtered
answers; a separate identity per agent; short-lived tokens. road-tracker measured it: the raw-API
skill made the agent copy 64-character read tokens and make up keys across about eight calls per
item; with `rt`, a fresh session worked an item in 16 turns for about 0.31 USD, nearly all of it
Claude Code's own cached context. The cost of an agent task is its number of turns, so commands that
do several steps (`rt done`: comment, move, release) save most.

## 3. Relation to spec-patch-14's database-user path

B-02's rulings (20 and 23 October 2026) say agents run batch work as database users, and no session
adopts another's identity. This patch does not change either:

| | Database-user path (spec-patch-14) | API key path (this patch) |
|---|---|---|
| Who | A process with database credentials: batch jobs, road-planner's agents | An agent on a developer machine, using only the REST surface |
| Identity | `SESSION_USER` mapped to a principal; cannot be forged | The key's principal; the token says who, the request cannot |
| Surface | PL/SQL binding | REST binding, the same handlers people use |
| Credential | A database password, held by a DBA | An API key, made and revoked by an app admin |

Both keep "one principal per caller, never borrowed". The API key path is for agents that should
not hold database credentials at all: with them, a tool could start a session as any principal and
skip the governed actions. It also answers the gsc definition's open question E.5 (a command line
calls the REST binding as its own principal).

## 4. Design

### 4.1 Table `road_api_keys`

`key_id`, `principal_id` (FK `road_principals`), `name` (where it runs, up to 80 characters),
`key_prefix` (first 12 characters, to recognise it), `key_hash` (SHA-256 hex, unique),
`created_by`, `created_at`, `last_used_at`, `expires_at` (optional), `revoked_at`, `revoked_by`.
No tenant column in road-kit; an application with tenancy adds one and puts the table under its
isolation policy, as road-tracker did.

### 4.2 Package `road_api_key_api`

- `create_key(p_body json, p_idempotency_key varchar2) return json`: governed action
  `api_keys.create`, permission `road.api_key.manage`. Rule `PRINCIPAL_NOT_ELIGIBLE` (section 6.1).
  The key is `<prefix>_` and 48 hex characters (192 random bits, `DBMS_CRYPTO.RANDOMBYTES`). It is
  added to the answer **after** `road_decision_api.accept` records the decision, so the decision
  record never holds it; a replay of the same key returns the outcome without it.
- `revoke_key(p_key_id number, p_idempotency_key varchar2) return json`: `api_keys.delete`, rule
  `API_KEY_NOT_FOUND`.
- `list_keys return clob`: view `api_keys.list`: keys with name, prefix, holder, made, last used,
  revoked; never the key or its hash.
- `exchange(p_body clob, p_status out number, p_response out clob)`: `{"api_key": "..."}` in. 200
  with `access_token`, `token_type`, `expires_in` and `subject`; 401 `invalid_key` for unknown,
  revoked or expired; 400 for no key. Records `last_used_at`. Mints with
  `jwt_scaffold_auth_api.issue_token` (or the provider profile's equivalent, spec-patch-09).

### 4.3 ORDS module `api_auth`

`POST /api-auth/tokens`, public, beside `/jwt-auth/login`, on `bin/check-handler-coverage.sh`'s
allowlist with its reason: requiring a session to get a session is circular. The handler calls
`road_api_key_api.exchange` and sends what it returns.

### 4.4 The admin page

An "API keys" page in the scaffold app: choose a principal, name the key, make it; the key is shown
once with a copy button and the setup command (`<cli> login --url ...`, the key pasted at a prompt,
never on the command line). A list with last use and Revoke.

### 4.5 `tools/road-cli/`

A single Node file, no dependencies, that an application copies and extends, as it copies the React
scaffold:

- `login --url <API base>`: asks for the key with echo off, or reads it from a pipe; stores URL and
  key under `~/.config/<app>/` (mode 600).
- Token handling: exchanges the key, caches the token until a minute before expiry, retries once
  with a new token on 401.
- `call`, `settle` (an outcome becomes a result, or a refusal with `rule_id` and message, exit 3),
  `onRecord` (read for a fresh read token, act, retry once on `STALE_TOKEN`), idempotency keys per
  create, standard input read as a stream (`readFileSync(0)` fails with EAGAIN on a pipe).
- `whoami`, `api METHOD PATH [JSON]` for anything the task commands do not cover.
- An extension point, `commands.js`, for the application's task commands.

Exit codes: 0 done, 1 error, 2 usage, 3 refused by a rule, and codes from 4 for the application.

### 4.6 `scripts/generate-skill.mjs`

Generates `skills/<app>/SKILL.md` and `reference.md` from the contract and the agent role's
permissions. The application supplies the workflow text and a map of each CLI command to the
contract entries it uses; generation fails if an entry is missing, closed to the agent role, or its
path is not one the CLI calls. `--check` fails when the skill is stale. It meets checklist items 33
and 34 (deterministic, states the contract version, leaves out `consumer_visible: false` rules and
`x-mcp-exclude` fields) without MCP.

## 5. Tests

PL/SQL: a key made, shown once, hashed, absent from `road_decisions`; replay without it; the
eligibility rule; exchange 200, 401 for wrong, revoked and expired, 400 for none; last use recorded;
revoke and `API_KEY_NOT_FOUND`; the permission. Endpoint: the exchange, and a call with the token it
returns. CLI: login, whoami, `api`, a refusal's exit code, a revoked key. Browser: make a key, see it
once, revoke it. Generator: `--check`, and a command mapped to a missing entry fails.

## 6. Open points, with recommendations

### 6.1 Who may hold a key

Any principal, or only some. **Recommend:** principals that hold a role marked for API keys
(`road_roles.allows_api_keys`, a new column, default N), so people do not get long-lived keys by
default; road-tracker's `rt_agent` would be such a role. The rule is `PRINCIPAL_NOT_ELIGIBLE`.

### 6.2 Who makes them

**Recommend:** a new permission `road.api_key.manage`, held by `road.system_admin`; an application
grants it to its own admin role. A principal never makes its own key.

### 6.3 Token lifetime

**Recommend:** 15 minutes, set in `JWT_SCAFFOLD_CONFIG`. Revocation then takes effect within 15
minutes for a token already issued, at once for new ones.

### 6.4 Key expiry

**Recommend:** optional `expires_at`, unset by default, shown on the admin page; no automatic
rotation in this patch.

### 6.5 The key prefix

**Recommend:** set per application in `road.config` (road-tracker's is `rtk`), so a leaked key names
its source, and secret scanners can be taught the pattern.

### 6.6 Where the CLI and generator live, and how applications take them

**Recommend:** in road-kit under `tools/road-cli/` and `scripts/`, copied into an application with
the scaffold and checked by `bin/check-road-kit-parity.sh` like other framework files; the
application's own `commands.js` and skill workflow text are not checked.

### 6.7 road-tracker's copy

road-tracker built this with tenancy: keys under its admin-only isolation policy, and the exchange's
lookup in its tenancy schema. **Recommend:** road-tracker adopts the framework package when it next
upgrades road-kit, keeping its tenancy wrapper (tenant column, policy, `RT_KEY_API`) as the
documented extension for multi-tenant applications.

## 7. Build plan, once ruled

1. Table, package and tests; the permission and role column (`deploy/create`, rerunnable).
2. The `api_auth` module and its allowlist entry; endpoint tests.
3. The admin page in the scaffold app; browser test.
4. `tools/road-cli/` with a demo extension for the todos example, and its tests.
5. `scripts/generate-skill.mjs` with the todos example's skill, and `--check` in the release
   checks.
6. Spec: authentication section for the key exchange; PATTERNS.md (`api-key-exchange`,
   `skill-from-contract`); a release note; road-atlas RK-15 when released, B-04 closed.

road-blogger is live (atlas F-06): every change is additive, no existing table, package or module
changes, and nothing is switched on until an application grants `road.api_key.manage`.

## 8. Out of scope

- Making agent principals from the admin page (principal creation stays where it is).
- OAuth 2.1 for MCP clients; an MCP server generated from the contract (RK-11) can sit beside the
  CLI later and use the same key exchange or a proper authorization server.
- Scoped keys (a key limited to some permissions of its principal).
