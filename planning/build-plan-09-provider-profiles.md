# Build Plan 09 — Provider Profiles and Principal Credentials

**Design:** `planning/spec-patch-09-provider-profiles-and-credentials.md`. Read it first; this file
sequences the work and records what each phase actually cost.

**Status: phases 1-3 complete. Phases 4-7 not started.**

---

## Phase 1 — PBKDF2 in PL/SQL — **COMPLETE 2026-08-26**

Deployed to `road_kit_dev` and green.

| Check | Result |
|---|---|
| `JWT_SCAFFOLD_CRYPTO` spec + body | VALID |
| `JWT_SCAFFOLD_CRYPTO_TEST` spec + body | VALID |
| `USER_ERRORS` for either package | none |
| **`jwt_scaffold_crypto_test.run_all`** | **10 passed, 0 failed** |
| Default cost, measured through the shipped package | **80 ms at 10,000 iterations** |
| Create-chain references all resolve | ✅ |

Runs `20260826_225726_deploy_crypto` and `20260826_225756_time_default`.

**Four published PBKDF2-HMAC-SHA256 vectors pass**, at c=1, c=2, c=4096 (32 bytes) and c=4096
(40 bytes). RFC 6070's own vectors are SHA-1 and do not apply; these are the SHA-256 equivalents of
the same four cases.

**The 40-byte vector is the one that earns its place.** The credential store only ever asks for 32
bytes — exactly one SHA-256 block, where the block index is always 1 — so a single-block
implementation passes every 32-byte vector and is indistinguishable from a correct one. It was the
shape the design probe used, and it would have shipped undetected. Only a derived key longer than
the hash width proves the block index is fed in at all. Full RFC 2898 §5.2 block iteration is
implemented for that reason, not for a requirement.

**Also asserted, because they are properties the credential store depends on rather than properties
of the algorithm:** the same inputs give the same digest; two principals choosing the same password
with different salts do not collide; the iteration count changes the output; null password, null
salt, zero iterations, zero `dk_len` and zero-length salt each raise `-20001` rather than deriving
something; `random_salt` returns the requested width and does not repeat.

`test_default_cost_not_weakened` is not a test of the algorithm. It fails if
`c_default_iterations` drops below 10,000, so lowering the cost requires editing an assertion and
not just a constant.

**Two things found doing it, both now in comments where they will be read:**

- **An empty password reaches `DBMS_CRYPTO.MAC` as a NULL key**, because
  `UTL_I18N.STRING_TO_RAW('')` is NULL — Oracle cannot represent a zero-length RAW. The resulting
  `ORA-28239` is an error about key management raised several frames from the actual cause. Guarded
  explicitly.
- **`deploy/drop/70_package_bodies.sql` does not need an entry.** It drops only the patch-06/07
  bodies; everything else, `jwt_scaffold_auth_api` included, is removed by dropping the package in
  `60_package_specs.sql`. Adding body drops here would look tidier and would be inconsistent with
  how the sibling scaffold package is treated.

**Not done, deliberately:** a full `00_full` drop-and-rebuild. The create and drop chains are wired
and every reference resolves, but proving the ordering end to end is phase 6's job, and tearing down
`road_kit_dev` to prove a leaf package is the wrong trade this early.

**Not added to `bin/check-road-kit-parity.sh`.** These four files are framework surface and road-cal
will hold them, but it does not yet — the divergence is deliberate and current, which is the
condition the script's header describes for files it does not list. **Add all four to the array in
the same commit as road-cal's adoption**, per the rule in that header, and not before.

---

## Phase 2 — `jwt_scaffold_credentials` and the password-setting script — **COMPLETE 2026-08-26**

Deployed to `road_kit_dev` and green. Design: spec patch §3.1, §3.2, §3.4.

| Check | Result |
|---|---|
| `JWT_SCAFFOLD_CREDENTIALS` + `..._UPDATED_AT_TRG` | created |
| Constraints: PK, FK cascade, iterations floor, algorithm whitelist | all present |
| `bin/set-principal-password.sh --self-test` | PASS, matches `jwt_scaffold_crypto_test.c_v1_c1` |
| Password set for `ADMIN` | row written, 16-byte salt, 32-byte digest, 10,000 iterations |
| `road_principals.credentials_changed_at` | SET |
| **Stored digest recomputed outside the DB from the password that produced it** | **matches** |
| **Plaintext present anywhere under `logs/` or `.codex/`** | **none** |
| Re-set the same principal | still exactly 1 row, digest changed — MERGE takes the matched branch |
| Unknown subject | `ORA-20001` naming the subject and issuer, exit 33 |
| Mismatched / empty password, iterations below floor, missing args | each refused before any database call |

Runs `20260826_230727` (set) and the readback and row-count runs following it.

**The leak check is the phase's real assertion.** A random password was generated, piped in, and
then searched for across `logs/` and `.codex/` — both tracked in git. It appears in neither. Worth
re-running whenever this script changes, because nothing else in the suite would notice its loss.

**Doing that check corrected the design's own rationale.** §3.4 claimed `run-sql.sh` "logs the
script it runs". It does not: it logs INFO headers, a `SCRIPT_SHA256`, the INTENT block and SQLcl's
output, with `set echo off`. The generated SQL body appears nowhere in the log — grepping the set
run for `hextoraw` returns zero lines. The real hazard is `--log-level debug`, which sets
`set echo on` and echoes every statement into a tracked log; a plaintext literal would be committed
the first time anyone debugged this script. Narrower than claimed, still worth designing against,
and §3.4 now says so accurately.

**A related claim was also wrong and is corrected in §3.4.** The 2026-08-18 history rewrite was
caused by credentials in *source* — a committed fallback in `bin/get-test-token.sh` and salt/hash
constants in `jwt_scaffold_auth_api.pkb` — not by anything in `logs/`.

**One caution the scan taught:** a three-character search string matches SHA-256 hex by chance.
`bbb` "hit" two logs, both inside `SCRIPT_SHA256` values. Use a high-entropy password for the check,
as the run did, and read the hits rather than trusting the exit code.

**Verification had to happen outside the database, which is the point.** The obvious check — ask
PL/SQL to derive from the password and compare — would send the plaintext to SQLcl and into a
tracked log, defeating the design. So the salt, digest and iteration count are read back as hex and
recomputed in python instead. Agreement between the two PBKDF2 implementations is established
separately, by both sides matching the same published vector: `--self-test` here,
`test_rfc_vector_one_iteration` there.

**`credentials_changed_at` was already there.** `road_principals` has carried the column since
patch 06 and nothing had ever written it; `road_admin_api.pks` line 69 calls it "credential-store
surface, not role administration". This is the credential store, so it writes it.

**The dev `ADMIN` principal now has a credential whose plaintext is not recorded anywhere** — it was
generated randomly to keep it out of this transcript. The row is inert until phase 3 rewires
`check_credentials`; login still uses the compiled-in constants. Phase 3 should set a fresh password
it knows.

---

## Phase 3 — the login path reads the table — **COMPLETE 2026-08-26**

Deployed to `road_kit_dev` and green.

| Suite | Result |
|---|---|
| **`jwt_scaffold_auth_api_test`** (new) | **10 passed, 0 failed** |
| `jwt_scaffold_crypto_test` | 10 passed, 0 failed |
| `error_api_test` | 7 passed, 0 failed |
| `road_ctx_pkg_test` | 13 tests passed |
| `road_admin_api_test` | 22 passed, 0 failed |
| `road_audit_api_test` | 4 passed, 0 failed |
| Invalid objects in the schema | none |
| Test fixtures surviving rollback | none |

Run `20260826_231731_phase3_verify` and the deploy immediately before it.

**The six constants are gone**, along with the `if/elsif` chain that used them.
`check_credentials` is replaced by `resolve_principal`, which returns a `principal_id` rather than a
boolean — the caller needs the identity, not just the verdict, because the token's `sub` must come
from `ROAD_PRINCIPALS` and because phase 4 derives the scope from that principal.

**`test_no_credential_constants_remain` is the regression guard.** It queries `USER_SOURCE` for long
`hextoraw` literals and for the old constant names. Reintroducing a hardcoded digest fails the suite
rather than quietly working.

**Three things this made possible that the constants could not express:**

- **A principal with no password.** Normal for anyone created through the admin screens, and normal
  under `external_oidc`. The old code had no way to represent it.
- **`SUSPENDED` and `RETIRED` are now enforced.** `ROAD_PRINCIPALS.STATUS` has carried those values
  since patch 06 with nothing checking them. A correct password no longer admits a suspended
  principal.
- **Per-row iteration counts verify.** A credential written at 2,500 iterations verifies at 2,500
  while the default is 10,000, which is what makes raising the cost safe for existing rows.

**Every failure returns the same thing.** Unknown subject, no credential, suspended, wrong password
and wrong algorithm are indistinguishable to the caller — `resolve_principal` returns NULL and the
endpoint returns one `invalid_credentials`. The login endpoint must not become an oracle for which
usernames exist.

**`password_digest` was deleted too.** It was the old single-round SHA-256 helper, unreferenced once
the constants went, and a weak primitive sitting beside a strong one is an invitation.

**Two compile errors worth knowing, both in the test package, both fixed:**

- **PLS-00231** — a package-private function may not be called inside a SQL statement.
  `current_issuer` had to be assigned to a local before the `INSERT` could use it.
- **PLS-00684** — `JSON_OBJECT ... RETURNING CLOB` is not a valid PL/SQL expression. It needs
  `SELECT ... INTO`.

**`bin/rotate-scaffold-credential.sh` is deleted, and removed from the parity array.** road-cal still
holds the file until it adopts, so that is a deliberate current divergence — which is what an
unlisted file means. A comment in the array says so and says not to re-add the line.

**Not done: setting passwords for the dev principals.** `ADMIN` holds the random credential phase 2
wrote, whose plaintext is recorded nowhere; `USER1` has none. Choosing real dev passwords is Simon's,
not something to generate and print into a transcript:

```bash
bin/set-principal-password.sh --env dev --subject ADMIN
bin/set-principal-password.sh --env dev --subject USER1
```

The suites do not need them — every test builds and rolls back its own fixture.

---

## Phase 4 — Per-principal scope

Design: spec patch §4. Seed the ORDS privilege names as permissions, attach them to roles, and
derive the scope in `issue_token` from the principal's effective permissions intersected with
`USER_ORDS_PRIVILEGES.NAME`, excluding `oracle.%`. Empty the `scope_name` fallback.

`todo.rw` belongs to the demo application and its seed belongs in `97_demo.sql`, which `00_full.sql`
does not invoke — Rule 1.

**Verify:** an administrator's token carries `road.admin.rw` and an ordinary principal's does not.
This is the phase that closes spec-patch-06 §8.4.

---

## Phase 5 — The switch

Design: spec patch §2. `AUTH_PROFILE`, two template bodies in `render-auth-config.sh`, conditional
inclusion of the scaffold objects in `00_full.sql`.

Open question 1 in the patch — where the value lives for a per-environment override — has to be
answered before this phase, not during it.

---

## Phase 6 — Conformance under both profiles

Design: spec patch §6. `authentication-spec-v1.md` §12's table, passing under each profile, with the
profile as an input rather than a variant of the tests. Includes the full drop-and-rebuild phase 1
deferred, in each position of the switch.

Proving `external_oidc` needs Auth0 console objects and reuses the shared SPA application; the
analysis is in road-cal's superseded `auth0-manual-setup.md` §0.

---

## Phase 7 — Adoption

road-cal copies the shared surface — see its `spec-patch-09-adoption-note.md` — and adds its own
four privilege names as permissions. road-blogger already runs `external_oidc` and takes the switch,
not the scaffold. Add the phase-1 files to the parity array in the same commit.
