# Specification Patch 09 — Provider Profiles and Principal Credentials

**Applies to:** `spec/authentication-spec-v1.md` §8, §11 and §12.
**Status:** design, 2026-08-26. Not built.
**Canonical location.** This is framework work and road-kit is where it is built. See §1.3.

**Related, in other repositories:**
`road-cal/planning/spec-patch-09-adoption-note.md` — what road-cal takes and when.
`road-cal/planning/build-plan-01-auth0-adoption.md` and `auth0-manual-setup.md` — **superseded**,
kept for the free-plan caps and the auto-provisioning finding, both cited below.

---

## 1. What this is

**road-kit becomes the canonical implementation of both authentication provider profiles, with a
switch between them.** Simon, 2026-08-26: *"road-kit will be the canonical implementation with both
methods, but switchable."* Scaffold for development, Auth0 for production.

Two pieces of work, and the second is the point:

1. **The scaffold stops using hardcoded users.** Three usernames, three salts and three SHA-256
   digests are compiled into `jwt_scaffold_auth_api`'s package body as constants. They become
   **password-protected principals** — credentials stored as data, attached to `ROAD_PRINCIPALS`,
   set by a script.
2. **The two profiles become a switch rather than a rewrite.** `ords_local_jwt_scaffold` and
   `external_oidc`, selected by one configuration value.

### 1.1 This implements a claim the spec already makes

`authentication-spec-v1.md` §8 has listed three provider profiles since it was written; §9 defines
`external_oidc`, §11 defines `ords_local_jwt_scaffold`, and §1 states the contract "allows multiple
authentication provider profiles behind that contract".

Nothing in any ROAD repository has ever *selected* between them. road-kit and road-cal deploy the
scaffold unconditionally; road-blogger deploys Auth0 unconditionally. The choice is currently
expressed as which files exist in which repository, which is not a switch. This patch makes the
claim operational in the one repository that is supposed to hold the framework.

### 1.2 Why the scaffold is being kept rather than retired

Auth0's free plan caps **machine-to-machine tokens at 1,000 per month, tenant-wide**, and lifting
that cap costs **$35/month**. road-cal's endpoint suite alone carries 123 assertions. A development
harness that exists to be run repeatedly cannot sit behind a metered external dependency.

That is an argument about development, not about production — which is why the answer is two
profiles rather than a choice between them. The other two free-plan caps, 10 applications and 10 API
resource servers, are recorded in road-cal's superseded `auth0-manual-setup.md` §0.

### 1.3 Why road-kit, when the established direction is the opposite

Patches 06 and 07 were built in road-cal and backported here. That direction was right for those:
both were driven by a road-cal requirement and road-kit had no way to exercise them.

This one inverts, for three reasons:

- **It is not an application requirement.** No calendar behaviour depends on it. It is a property of
  the framework's authentication contract, and the contract is this repository's.
- **road-kit can prove both positions.** It has `hello_world` with real auth wiring — `RequireAuth`,
  `api/auth.ts`, `utils/auth.ts` — and a Playwright e2e suite. It has `demo_todo_api` and a
  `todo.rw` ORDS privilege. It is not a schema-only repository.
- **Three consumers, not one.** road-cal and road-blogger both adopt from here. Building it in
  road-cal would mean road-blogger adopting from an application repository, which is backwards.

**The scaffold package is byte-identical between road-kit and road-cal today** and is on the shared
surface list in `bin/check-road-kit-parity.sh` line 67. One change here copies across unmodified —
which is the mechanism that makes this direction cheap.

---

## 2. The switch

### 2.1 The value

`AUTH_PROFILE`, taking the profile names from `authentication-spec-v1.md` §8 character for
character:

```
AUTH_PROFILE=ords_local_jwt_scaffold     # development
AUTH_PROFILE=external_oidc               # production
```

Do not invent shorter names. The spec's §8 table is the registry.

### 2.2 What reads it — **corrected against the built mechanism, 2026-08-26**

One consumer, `bin/render-auth-config.sh`, producing two artifacts. The design originally said
`00_full.sql` itself would include or skip the scaffold-only objects; building phase 5 showed that
claim was both too broad and, on its own, insufficient — see below.

| Artifact | Behaviour |
|---|---|
| `deploy/create/80_standalone.generated.sql` | The JWT profile registration, rendered from one of two template bodies: `80_standalone.sql.tmpl` (scaffold, points at this schema's own JWKS endpoint) or `80_standalone.external_oidc.sql.tmpl` (points at the external provider's issuer, audience and JWKS URL) |
| `deploy/create/90_rest_auth.generated.sql` | Whether the scaffold's **public login endpoint** — `api/modules/auth/`, `/jwt-auth/login` and its JWKS document — deploys at all |

**Too broad, corrected:** only the ORDS module in the second row needs to be conditional. The
scaffold's tables and packages (`jwt_scaffold_config`, `jwt_scaffold_credentials`,
`jwt_scaffold_auth_api`, `jwt_scaffold_crypto`) stay deployed under both profiles, unconditionally.
See §2.3a for why that is safe rather than a shortcut.

**Insufficient on its own, found deploying against `road_kit_dev`:** simply not including
`api/modules/auth/module.create.sql`'s `@`-include stops the module being *created*, which is
correct for a fresh deploy — but a schema *switching* from the scaffold profile to `external_oidc`
already has that module registered from a prior deploy, and omitting the create script does nothing
to remove it. Confirmed the hard way: the first version of `90_rest_auth.generated.sql` rendered
under `external_oidc` was an empty no-op, redeployed `90_rest.sql`, and `/jwt-auth/` was still
there — a `SELECT` against `USER_ORDS_MODULES` proved it, not an assumption. The fix is that the
`external_oidc` rendering of `90_rest_auth.generated.sql` **actively calls
`ords.delete_module`**, guarded the same way every other `delete_module` call in this codebase is,
so a *switch* removes what a fresh deploy would simply never have created. Re-verified after the
fix: zero rows.

**Nothing else branches.** Not `road_ctx_pkg`, not `road_admin_api`, not `error_api`, not any ORDS
privilege, not any `require_permission` call, not the React app beyond its login control.

### 2.3 Why so little has to branch

`road_ctx_pkg.begin_request` reads the issuer from the schema's registered ORDS JWT profile rather
than being told it, and `95_data.sql` seeds the bootstrap administrator against that same issuer.
Repointing the profile repoints identity; everything above it is untouched.

This is not new. It is exactly the property road-blogger demonstrated by adopting Auth0 without
modifying anything in the `ROAD_*` surface, and the reason its build required no framework change.
This patch spends that property deliberately rather than rediscovering it a third time.

### 2.3a Why the scaffold's packages and tables stay deployed under `external_oidc`

Only the ORDS module is conditional (§2.2). `jwt_scaffold_auth_api` remains compiled, and
`jwt_scaffold_config` / `jwt_scaffold_credentials` remain in the schema, whichever profile is
selected. This is a deliberate narrowing of what an earlier draft of this section implied ("includes
or skips the scaffold-only objects" — plural, broad), made because the actual security property
does not require the wider skip.

**The registered ORDS JWT profile is the real trust boundary, and only one is ever registered at a
time.** `ords_security.create_jwt_profile` is called once per profile choice; whichever issuer that
call names is the *only* issuer ORDS will accept. `jwt_scaffold_auth_api.issue_token` can still be
called directly in PL/SQL under `external_oidc` — confirmed against `road_kit_dev`, deploying this
phase, calling it with a wrong password and getting a normal `401` back — but any token it mints
carries the scaffold's own issuer, which is not the issuer registered with ORDS under this profile.
ORDS rejects it exactly as it would reject a token from any other unrecognised source. A compiled,
reachable-in-PL/SQL, *unreachable-over-HTTP* package poses no exploitable risk this design needs to
close.

**The public HTTP endpoint is a different kind of residue and is the one thing removed.**
`/jwt-auth/login` and its JWKS document are reachable by anyone, unauthenticated, by construction —
that is what a login endpoint is. Leaving one live that mints tokens ORDS will not honour is not a
vulnerability in the sense above, but it is unnecessary attack surface, a false signal to anyone
auditing the deployed API surface, and confusing. §2.2 is where it is removed, and removed actively
on a *switch*, not merely uncreated on a fresh deploy.

**What this buys:** the conditional-deploy mechanism stays to one file
(`90_rest_auth.generated.sql`) instead of five (tables, triggers, package specs, package bodies,
ORDS modules), verified completely rather than partially, instead of touching every chain file for
a security property that does not need it.

### 2.4 The rule that keeps the switch honest

**A profile may add artefacts. It may not change the contract.** Any behaviour a caller can
observe — status codes, claim names, the `/session/me/` payload, the 401/403 boundary — differing
between profiles is a defect in this patch, not a property of the profile. §5 enumerates the
contract and §6 tests it.

---

## 3. Scaffold credentials

### 3.1 Objects and namespace

| Object | Status |
|---|---|
| `jwt_scaffold_credentials` (table) | **New** |
| `jwt_scaffold_config` | Unchanged |
| `jwt_scaffold_auth_api` | Rewritten: credentials read from the table; PBKDF2 replaces single-round SHA-256 |
| `api/modules/auth/` | Unchanged |
| `bin/set-principal-password.sh` | **New** |
| `bin/rotate-scaffold-credential.sh` | **Deleted** — it rewrites constants that no longer exist |
| `bin/ensure-auth-key.sh` | Unchanged, scaffold-only |

All of it is scaffold-namespaced and all of it is skipped under `external_oidc`.

**Credentials do not go on `ROAD_PRINCIPALS`.** A password column there would couple the framework
to being its own identity provider — precisely the coupling §2.3 depends on not existing.
`ROAD_PRINCIPALS` stays keyed on `(issuer, subject)` and stays ignorant of how a subject was
authenticated. The credential table references it, never the reverse.

### 3.2 Shape

```
jwt_scaffold_credentials
  principal_id    number       pk, fk -> road_principals(principal_id) on delete cascade
  salt            raw(16)      not null
  password_hash   raw(32)      not null
  iterations      number       not null
  algorithm       varchar2(30) not null   -- 'PBKDF2-HMAC-SHA256'
  created_at      timestamp with time zone
  updated_at      timestamp with time zone
```

`iterations` and `algorithm` are stored per row rather than assumed, so the cost can be raised later
without invalidating existing rows: each row is verified with the parameters it was written with.

**No username column.** The username *is* the principal's `subject`. Login resolves
`(issuer from the JWT profile, subject = upper(trim(username)))` against `ROAD_PRINCIPALS`, then
reads this table by `principal_id`. One identity namespace rather than two. Scaffold subjects are
uppercase by convention, which the existing fixtures `ADMIN`, `USER1` and `USER2` already are.

### 3.3 Key derivation — measured on the target database, not assumed

**This ADB has no PBKDF2 primitive.** `DBMS_CRYPTO` on Oracle AI Database 26ai (23.26.3.2.0)
exposes `HASH`, `HASH_LEN`, `MAC`, `KMACXOF`, `RANDOMBYTES`, `RANDOMINTEGER`, `RANDOMNUMBER`,
`SIGN`, `VERIFY`, the cipher calls and the ECDH pair. There is no key-derivation function.
Verified 2026-08-26 against `road_cal_dev`, run `20260826_221152_probe_crypto`.

PBKDF2-HMAC-SHA256 is therefore built from `DBMS_CRYPTO.MAC` and `UTL_RAW.BIT_XOR` — about twenty
lines, since a 32-byte derived key is one SHA-256 block and the block index is always 1. Verified
against the RFC 6070 SHA-256 vector and timed on the same database
(run `20260826_221310_probe_pbkdf2`):

| Iterations | Cost |
|---|---|
| 1,000 | 10 ms |
| **10,000** | **80 ms** |
| 50,000 | 410 ms |

**Use 10,000.** 80 ms is imperceptible on a login, and there is no case for keeping single-round
SHA-256 at that price. Salt is 16 bytes from `DBMS_CRYPTO.RANDOMBYTES`, per principal.

This removes one of the two reasons the scaffold is marked development-only. The other — the
application schema is its own identity provider — is structural. `authentication-spec-v1.md` §11.5
still applies and the profile stays marked dev-only.

### 3.4 Setting a password without leaking it

**`logs/` is tracked in git, and `--log-level debug` echoes every statement into it.**

Stated precisely, because an earlier draft of this section overstated it and the overstatement was
caught during phase 2: `bin/run-sql.sh` does *not* write the script body to its log. It records the
INFO headers, a `SCRIPT_SHA256`, the extracted INTENT block and SQLcl's output, with `set echo off`.
A literal in the SQL is not normally logged at all.

`--log-level debug` sets `set echo on`, and then every executed statement is echoed into a log under
`logs/`, which is tracked. So a plaintext password in generated SQL would be committed the first
time somebody debugged the thing that writes it — which is precisely when they would. A latent trap,
not a certainty, and a bad one, because it fires when attention is on the failure rather than on
what is landing in the repository.

**The 2026-08-18 history rewrite was not caused by this.** That password was in *source*: a
committed fallback in `bin/get-test-token.sh`, and salt/hash constants in
`jwt_scaffold_auth_api.pkb`. Different mechanism, same lesson — a credential that has to live
somewhere in the tree ends up in the tree's history. This patch removes the reason for it to live
there at all.

**So the plaintext never reaches the database.** `bin/set-principal-password.sh` derives salt and
digest locally using python3's `hashlib.pbkdf2_hmac` — standard library, no new dependency — and the
generated SQL carries hex only:

```
bin/set-principal-password.sh --env dev --subject ADMIN
  → prompts via `read -rs`; never an argument, because arguments reach `ps` and shell history
  → derives salt + digest locally
  → runs a MERGE carrying raw hex only
  → writes its generated SQL outside the repository
```

Two PBKDF2 implementations now exist — python's for setting, PL/SQL's for verifying — and they must
agree exactly. **A test asserts a fixed vector against the PL/SQL side**, so drift is caught by the
suite rather than by a login that quietly stops working.

---

## 4. Scope parity between profiles

### 4.1 The problem the switch creates

Under `external_oidc`, Auth0 issues each user a scope filtered by their roles: an administrator's
token carries `road.admin.rw`, an ordinary user's does not.

Under the scaffold, `jwt_scaffold_config.scope_name` is **one fixed list issued to every user**. The
package comment says so: every signed-in caller reaches `/admin/*` at the ORDS layer and is then
denied — or not — by `require_permission`. `spec-patch-06` §8.4 records this as a known limitation,
deferred until an issuer existed that could mint per-principal scopes.

**The switch turns that from known into unacceptable.** If development issues every user every scope
and production does not, the profiles are not interchangeable, §12's "missing required scope → 401"
row can never pass under the scaffold, and an authorisation defect that production rejects at ORDS
reaches PL/SQL in development — which is where it is tested. That is the opposite of what a
development profile is for.

The scaffold now resolves login to a principal, so the blocker §8.4 named is gone.

### 4.2 The resolution needs no mapping table

ORDS privilege names and database permission names are deliberately different namespaces —
`todo.rw` gates a URL pattern, `todo.create` gates an operation. Mapping between them looked like it
needed a new table. **It does not.**

`USER_ORDS_PRIVILEGES.NAME` already holds the schema's privilege names — verified 2026-08-26, run
`20260826_222034_probe_privs`, which returned road-cal's four alongside ORDS's own
`oracle.dbtools.*` and `oracle.soda.*` built-ins. road-kit's are `road.admin.rw`, `session.me.read`
and `todo.rw`.

So: **seed the ORDS privilege names as rows in `ROAD_PERMISSIONS`** and attach them to roles like
any other permission. The scaffold then mints

> the principal's effective permissions, intersected with `USER_ORDS_PRIVILEGES.NAME`,
> excluding names beginning `oracle.`

Four consequences, all good:

- **The mapping lives in role composition** — where every other authorisation decision lives,
  administered through the same admin API, subject to the same reserved-permission assertions.
- **It self-maintains.** A new ORDS privilege becomes mintable by being granted. No code change.
- **It matches what Auth0 does.** In the console a human ticks permissions named after ORDS
  privileges onto a role. Here the same names are attached to a role in the database. Same model,
  different administration surface — which is the parity §2.4 requires.
- **It respects Rule 1.** The mechanism is framework. Seeding `todo.rw` as a permission is demo
  application data and belongs in `97_demo.sql`, which `00_full.sql` does not invoke. The demo app
  does not cause a framework change; it exercises one.

`jwt_scaffold_config.scope_name` becomes the **fallback** for a principal holding no such
permissions, and should be `NULL` rather than a privilege list — **not** an empty string. `NULL` is
the correct token claim for a principal entitled to nothing, and it is also the only value Oracle
can actually store: `''` is `NULL` for `VARCHAR2`, so a column left `NOT NULL` refuses it outright
(`ORA-01407`, found deploying phase 4). The column had to become nullable; see
`db/tables/jwt_scaffold_config.create.sql`.

### 4.3 Consequence worth stating plainly

This closes `spec-patch-06` §8.4. The ORDS privilege gate stops being routing and becomes
authorisation, under both profiles. It also restores the conformance case that had no affordable
answer under Auth0 — an under-scoped token is now produced by granting a principal fewer
permissions, rather than by buying a second Auth0 application.

---

## 5. What must be identical across profiles

| Concern | Requirement |
|---|---|
| Transport | `Authorization: Bearer <token>` |
| Claims | `sub`, `iss`, `aud`, `exp`, `iat`, `scope` — same names, same meanings |
| `sub` | The value matched against `ROAD_PRINCIPALS.subject` |
| Scope semantics | Contains the ORDS privilege name protecting the resource |
| No token / malformed / expired / wrong issuer / wrong audience / missing scope | **401**, at ORDS, before any PL/SQL runs |
| Authenticated principal lacking a permission | **403**, from `require_permission` |
| `/session/me/` | Identical payload |
| Login | **Differs** — a form under the scaffold, a redirect under `external_oidc`. `authentication-spec-v1.md` §4.5 already permits this and requires the *result* to match |

---

## 6. Proving both positions

`authentication-spec-v1.md` §12's table must pass **under both profiles**, and the suite must run
against either without being edited — the profile is an input, not a variant of the tests.

road-blogger made §12 runnable; that harness is the shape to port. Two rows deserve attention:

- **Missing required scope → 401.** Impossible under the scaffold before §4.2, expensive under
  Auth0. Now: a principal granted fewer permissions.
- **Authenticated principal lacking a permission → 403.** The row that distinguishes the two layers,
  and the one a profile switch is most likely to break.

**What road-kit needs to prove `external_oidc`.** Auth0 console objects: an API, two roles, and a
browser client. The tenant is at its 10-application cap, so the browser client is the **shared SPA
application road-cal was also going to reuse** — making road-kit the third product on it. road-cal's
superseded `auth0-manual-setup.md` §0 is the analysis of what sharing costs and why it is
acceptable; it applies here unchanged. Adding road-kit's callback URL is an append, not a replace.

Under `external_oidc` the suite spends the 1,000-token monthly allowance, so it fetches **one token
per run**, not per assertion — road-blogger's `run-endpoint-tests.sh` line 123 is the shape. Under
the scaffold there is no such limit, which is the whole reason development uses it.

---

## 7. Build sequence

Ordering only; detail belongs in a build plan.

1. **PBKDF2 in PL/SQL**, with the RFC vector as a test. Standalone and provable before anything
   depends on it.
2. **`jwt_scaffold_credentials`** and `bin/set-principal-password.sh`, plus the fixed-vector test
   pinning the two implementations together.
3. **Rewrite `check_credentials`** to read the table. Delete the six constants and
   `rotate-scaffold-credential.sh`. Set passwords for the existing dev principals.
4. **Per-principal scope** (§4): seed privilege names as permissions, attach to roles, derive the
   scope in `issue_token`, empty the fallback.
5. **The switch** (§2): `AUTH_PROFILE`, two template bodies, conditional deploy.
6. **Conformance under both** (§6), including a full drop-and-rebuild in each position. road-kit's
   rebuild-from-empty found ordering defects nothing else would have; do it again here.
7. **Adoption.** road-cal copies the shared surface — see its adoption note. road-blogger already
   runs `external_oidc` and takes the switch, not the scaffold.

---

## 8. Open questions

1. **~~Where does `AUTH_PROFILE` live for a per-environment override?~~ Answered, phase 5,
   2026-08-26: an environment variable, no default.** Matches `ROAD_ORDS_HOST` exactly, which
   `bin/render-auth-config.sh` already required this way and for the identical reason — that
   script's own comment on `ROAD_ORDS_HOST` says a plausible-but-wrong value is how a defect
   survives unnoticed. Silently defaulting `AUTH_PROFILE` to the scaffold would be a worse version
   of the same mistake: a forgotten setting would deploy the *development* identity provider to an
   environment meant to run production's. `road.config` was the wrong place regardless — it is
   committed and shared across environments, and dev differing from prod is the entire point.
2. **`road_config.auto_provision_principals` ships `'Y'`.** Under the scaffold it is now unreachable
   through login: no credential row, no token. It stays reachable under `external_oidc`, where
   road-cal's superseded Auth0 analysis showed it enrols any authenticated stranger behind a shared
   issuer. Its correct value is probably profile-dependent, which would make it a third thing that
   branches — and §2.2 currently claims there are two.
3. **The parity check covers two repositories, and three now share this surface.**
   `check-road-kit-parity.sh` compares road-kit and road-cal only; road-blogger holds copies of the
   same framework files and is checked by nobody. Its own header records that what the check cannot
   see is the thing to remember about it — `road_audit_api` went missing for exactly this reason.
4. **The parity header now describes the wrong policy.** It says every change reaches the peer "by
   copying, and vice versa". The mechanism is symmetric and should stay so, but the policy is no
   longer: framework changes originate here. Update the wording without making the script
   directional.
