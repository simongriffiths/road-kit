# Specification Patch 15 — Agents, API Keys and the Command-Line Tool

**Applies to:** framework surface. New tables `road_agents` and `road_api_keys`, a new package
`road_agent_api`, a new public ORDS module `/api-auth/`, governed actions for agents and their keys,
a "My agents" page and an admin view in the React scaffold, and two new tools: `tools/road-cli/` (a
command-line core that applications extend with task commands) and `scripts/generate-skill.mjs` (a
Claude Code skill generated from a contract).
**Status:** ruled and built 15 November 2026 (section 9), not yet released. Simon accepted the recommendations in section 6 and
ruled that people make their own agents and keys (self-serve), each agent its own principal owned by
the person who made it, rather than personal keys that act as the person (section 4.2). Two details
were added in this revision to carry out that ruling and are open to change: the `road_agents` table
(4.1) and a default limit of five live agents per person (4.4).
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

1. **Self-serve agents and API keys.** A person makes their own agent in the app ("Simon's Claude
   Code"), a principal of its own that they own, and makes keys for it, named for where each will
   run and copied once. Only a SHA-256 hash is stored. Revoking a key stops it at once. Admins see
   and revoke every agent's keys, and make shared agents with no person as owner.
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
calls the REST binding as its own principal), and, with section 4.2, E.1 (delegation).

## 4. Design

### 4.1 Table `road_agents`

`principal_id` (primary key, FK `road_principals`), `owner_principal_id` (FK `road_principals`, null
for a shared agent an admin made), `created_by`, `created_at`. A principal is an agent if and only if
it has a row here. `road_principals` itself does not change: road-blogger is live (atlas F-06).

### 4.2 Agents are their own principals, owned by a person

Simon's ruling: self-serve, but never a key that acts as the person. An agent:

- **is a principal of its own**, with a subject the framework issues (`AGENT_<n>`), the application's
  JWT issuer, the display name its owner gives, and no password;
- **holds one role, the application's agent role** (`road_config` key `agents.role`, for example
  road-tracker's `rt_agent`), never its owner's roles. The application chooses what agents may do,
  and its agent rules (road-tracker's claims, "agents cannot close") keep working because the agent
  is not its owner;
- **is attributed to itself**: history and `road_decisions` record the agent's principal; the owner is
  one join away in `road_agents`, so a screen can say "Simon's Claude Code";
- **stops when its owner stops**: the exchange refuses a key whose agent or owner is not `ACTIVE`, so
  suspending a person suspends their agents.

This is a worked answer to the gsc definition's open question E.1 (delegation): the agent acts for
its owner under its own identity, and the acting principal, the agent, is the one evaluated (5.2).

Self-serve is off until an application sets `agents.role` and grants `road.agent.self_serve` to the
roles whose holders may make agents.

### 4.3 Table `road_api_keys`

`key_id`, `principal_id` (the agent; FK `road_agents`), `name` (where it runs, up to 80
characters), `key_prefix` (first 12 characters, to recognise it), `key_hash` (SHA-256 hex, unique),
`created_by`, `created_at`, `last_used_at`, `expires_at` (optional), `revoked_at`, `revoked_by`.
No tenant column in road-kit; an application with tenancy adds one to both tables and puts them under
its isolation policy, as road-tracker did.

### 4.4 Package `road_agent_api`

Governed actions (spec-patch-12), each through `road_decision_api`:

| Action | Resource | Who | Rules |
|---|---|---|---|
| `agents.create` | `POST /agents/` `{display_name}` | holders of `road.agent.self_serve` (owner: the caller); holders of `road.api_key.manage` may set `"shared": true` (no owner) | `AGENT_LIMIT_REACHED` (at most `agents.limit_per_owner`, default 5, live agents per owner) |
| `agents.retire` | `DELETE /agents/{id}/` | the owner, or `road.api_key.manage` | `AGENT_NOT_FOUND` (not yours, or not an agent) |
| `api_keys.create` | `POST /agents/{id}/keys/` `{name, expires_at?}` | the owner, or `road.api_key.manage` | `AGENT_NOT_FOUND`, `AGENT_RETIRED` |
| `api_keys.delete` | `DELETE /agents/{id}/keys/{key_id}/` | the owner, or `road.api_key.manage` | `AGENT_NOT_FOUND`, `API_KEY_NOT_FOUND` |

Views: `agents.list` (`GET /agents/`: the caller's agents with their keys; with `?all=true`, every
agent, for `road.api_key.manage`). Never a key or its hash.

A key is `<prefix>_` and 48 hex characters (192 random bits, `DBMS_CRYPTO.RANDOMBYTES`). It is added
to the answer **after** `road_decision_api.accept` records the decision, so the decision record
never holds it; a replay of the same Idempotency-Key returns the outcome without it. Retiring an
agent revokes its keys and sets its principal `RETIRED`.

`exchange(p_body clob, p_status out number, p_response out clob)`: `{"api_key": "..."}` in. 200
with `access_token`, `token_type`, `expires_in` and `subject`; 401 `invalid_key` for a key that is
unknown, revoked or expired, or whose agent or owner is not `ACTIVE`; 400 for no key. Records
`last_used_at`. Mints with `jwt_scaffold_auth_api.issue_token` (or the provider profile's
equivalent, spec-patch-09).

### 4.5 ORDS modules

`POST /api-auth/tokens`, public, beside `/jwt-auth/login`, on `bin/check-handler-coverage.sh`'s
allowlist with its reason: requiring a session to get a session is circular. The handler calls
`road_agent_api.exchange` and sends what it returns. `/api/v1/agents/` carries the actions and view
above, protected like any other module.

### 4.6 The pages

**My agents**, for everyone with `road.agent.self_serve`: make an agent, make a key for it (shown
once, with a copy button and the setup command `<cli> login --url ...`, the key pasted at a prompt,
never on the command line), see each key's last use, revoke keys, retire the agent. **All agents**,
for `road.api_key.manage`: the same over every agent, with owners, and shared agents.

### 4.7 `tools/road-cli/`

A single Node file, no dependencies, that an application copies and extends, as it copies the React
scaffold:

- `login --url <API base>`: asks for the key with echo off, or reads it from a pipe; stores URL and
  key under `~/.config/<app>/` (mode 600).
- Token handling: exchanges the key, caches the token until a minute before expiry, retries once
  with a new token on 401.
- `call`, `settle` (an outcome becomes a result, or a refusal with `rule_id` and message, exit 3),
  `onRecord` (read for a fresh read token, act, retry once on `STALE_TOKEN`), idempotency keys per
  create, standard input read as a stream (`readFileSync(0)` fails with EAGAIN on a pipe).
- `whoami` (the agent and its owner), `api METHOD PATH [JSON]` for anything the task commands do not
  cover.
- An extension point, `commands.js`, for the application's task commands.

Exit codes: 0 done, 1 error, 2 usage, 3 refused by a rule, and codes from 4 for the application.

### 4.8 `scripts/generate-skill.mjs`

Generates `skills/<app>/SKILL.md` and `reference.md` from the contract and the agent role's
permissions. The application supplies the workflow text and a map of each CLI command to the
contract entries it uses; generation fails if an entry is missing, closed to the agent role, or its
path is not one the CLI calls. `--check` fails when the skill is stale. It meets checklist items 33
and 34 (deterministic, states the contract version, leaves out `consumer_visible: false` rules and
`x-mcp-exclude` fields) without MCP.

## 5. Tests

PL/SQL: a person makes an agent, which gets the agent role and none of theirs; the per-owner limit;
a key made, shown once, hashed, absent from `road_decisions`; replay without it; another person
cannot see, key or retire your agent, an admin can; exchange 200, 401 for wrong, revoked, expired,
retired agent and suspended owner, 400 for none; last use recorded; self-serve off when
`agents.role` is unset. Endpoint: the exchange, and a call with the token it
returns. CLI: login, whoami, `api`, a refusal's exit code, a revoked key. Browser: make a key, see it
once, revoke it. Generator: `--check`, and a command mapped to a missing entry fails.

## 6. Rulings (15 November 2026)

### 6.1 Who makes agents and keys

**Ruled: self-serve.** People make their own agents and keys (`road.agent.self_serve`); admins
(`road.api_key.manage`) see and revoke all of them and make shared agents. The first draft
recommended admin-only keys for principals whose role allowed them; Simon asked for self-serve, and
the choice between a personal key that acts as the person and an agent of one's own was ruled for
the agent (section 4.2).

### 6.2 What an agent may do

**Ruled:** the application's agent role, set in `agents.role`, never its owner's roles. Limiting an
agent further to what its owner may do is not in this patch.

### 6.3 Token lifetime

**Ruled:** 15 minutes, set in `JWT_SCAFFOLD_CONFIG`. Revocation then takes effect within 15 minutes
for a token already issued, at once for new ones.

### 6.4 Key expiry

**Ruled:** optional `expires_at`, unset by default, shown on the pages; no automatic rotation.

### 6.5 The key prefix

**Ruled:** set per application in `road.config` (road-tracker's is `rtk`), so a leaked key names its
source, and secret scanners can be taught the pattern.

### 6.6 Where the CLI and generator live, and how applications take them

**Ruled:** in road-kit under `tools/road-cli/` and `scripts/`, copied into an application with the
scaffold and checked by `bin/check-road-kit-parity.sh` like other framework files; the application's
own `commands.js` and skill workflow text are not checked.

### 6.7 road-tracker's copy

road-tracker built admin-made keys with tenancy: keys under its admin-only isolation policy, the
exchange's lookup in its tenancy schema, and agent principals made by a platform script.
**Ruled:** road-tracker adopts the framework version when it next upgrades road-kit. Self-serve
there needs a person to create an agent inside their own tenant, which crosses its isolation
boundary, so it takes one more narrow function in `ROAD_TRACKER_TENANCY` beside `RT_KEY_API`:
create an agent principal in the caller's tenant, with the agent role, owned by the caller. Its
tenancy wrapper stays the documented extension for multi-tenant applications.

## 7. Build plan, once ruled

1. Tables `road_agents` and `road_api_keys`, package `road_agent_api` and tests; the permissions
   and `road_config` keys (`deploy/create`, rerunnable).
2. The `api_auth` and `agents` modules, the allowlist entry; endpoint tests.
3. The My agents and All agents pages in the scaffold app; browser tests.
4. `tools/road-cli/` with a demo extension for the todos example, and its tests.
5. `scripts/generate-skill.mjs` with the todos example's skill, and `--check` in the release
   checks.
6. Spec: authentication section for the key exchange; PATTERNS.md (`api-key-exchange`,
   `skill-from-contract`); a release note; road-atlas RK-15 when released, B-04 closed.

road-blogger is live (atlas F-06): every change is additive, no existing table, package or module
changes, and nothing is switched on until an application sets `agents.role` and grants the
permissions.

## 8. Out of scope

- Personal keys that act as the person (ruled out in 6.1).
- Limiting an agent to the intersection of its role and its owner's permissions (6.2).
- OAuth 2.1 for MCP clients; an MCP server generated from the contract (RK-11) can sit beside the
  CLI later and use the same key exchange or a proper authorization server.
- Scoped keys (a key limited to some permissions of its principal).

## 9. Built, 15 November 2026

On `ROAD_KIT_DEV` (QuorateDB), with the full create chain (run `20261115_120445_00_full`) and the demo.

| Check | Result |
|---|---|
| PL/SQL | `road_agent_api_test` 8 passed: self-serve off without `agents.role`; a person's agent is its own principal with only the agent role; the per-owner limit, and retired agents not counting; a key shown once, hashed, absent from `road_decisions`, not replayed; another person cannot see, key or retire it, a manager can; shared agents need the manager; the exchange (200, and 401 for wrong, revoked, expired, retired agent and suspended owner, 400 for none); wrong calls. All nine framework suites pass (`test/plsql/run-framework-tests.sql`, new) |
| HTTP | `test/agents/agents.test.mjs` 19 passed: a person makes an agent and a key, the key buys a token, the token is the agent (`/session/me/`) and works todos with the agent role but cannot manage agents, another person sees nothing, the admin sees all and revokes, revoked and retired keys buy nothing |
| CLI | `test/agents/road-cli.test.mjs` 12 passed: login with a key made over HTTP, whoami, the demo's todo commands, `api`, exit codes, a revoked key shut out |
| Browser | `hello_world/e2e/agents.smoke.spec.ts` passed: make an agent and a key, see it once, revoke, retire |
| Generator | `test/skill/generate-skill.test.mjs` 8 passed, against `test/contract/fixtures/governed-surface-contract.valid.json` |
| Handler coverage | 21 protected handlers covered; `api_auth` on the public allowlist with its reason |

All of it, with fixtures made and removed: `bin/run-agent-tests.sh --env dev` (no password needed:
person tokens are minted directly). road-kit's existing endpoint suite needs `ROAD_TEST_PASSWORD`,
which is Simon's to set in `config/local.env`, and was not rerun.

**Found while building:**

- **An agent role should include `session.me.read`**, or an agent cannot read its own identity; the
  demo's `todo_agent` does, and the README says so.
- **The exchange works under the scaffold profile only.** It mints with the scaffold's signing key;
  an application on `external_oidc` (road-blogger's production profile) would have its tokens
  refused, so it needs its provider's machine-to-machine flow, or a later patch, before switching
  agents on (`spec/authentication-spec-v1.md` 11.6).
- **The new framework files are not yet on the parity list**, which compares against a consumer that
  has them; they are listed, commented, in `bin/check-road-kit-parity.sh`, to switch on in the first
  adoption commit.
- **The todo demo is not a governed API** (a stale change is 409), so `road-cli`'s `onRecord` retries
  on either a governed `STALE_TOKEN` or a 409.

Not done here: a release tag, and road-tracker's adoption (section 6.7).

