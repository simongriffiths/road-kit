# Build Plan 09 — Provider Profiles and Principal Credentials

**Design:** `planning/spec-patch-09-provider-profiles-and-credentials.md`. Read it first; this file
sequences the work and records what each phase actually cost.

**Status: phase 1 complete. Phases 2-7 not started.**

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

## Phase 2 — `jwt_scaffold_credentials` and the password-setting script

Design: spec patch §3.1, §3.2, §3.4.

1. The table, keyed on `principal_id`, `on delete cascade` from `road_principals`. Add to
   `10_tables.sql` and the drop chain.
2. `bin/set-principal-password.sh` — derives salt and digest with python3's `hashlib.pbkdf2_hmac`,
   prompts via `read -rs`, writes generated SQL outside the repository, sends hex only.
3. **The cross-implementation test.** Two PBKDF2 implementations now exist and must agree. Pin them
   with a fixed `(password, salt, iterations)` triple whose expected digest is asserted in PL/SQL,
   and have the shell script verify the same triple.

**Verify:** a password set by the script verifies through `jwt_scaffold_crypto` in the database, and
the plaintext appears in no log under `logs/`.

---

## Phase 3 — `check_credentials` reads the table

Delete the six constants from `jwt_scaffold_auth_api`'s body and the `if/elsif` chain. Resolve
`(issuer from the JWT profile, subject = upper(trim(username)))` to a principal, then verify against
`jwt_scaffold_credentials` using that row's own `iterations` and `algorithm`. Delete
`bin/rotate-scaffold-credential.sh`. Set passwords for the existing dev principals.

**Verify:** login succeeds for a principal with a credential row, fails for one without, and fails
for a wrong password. No password material remains in any package body.

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
