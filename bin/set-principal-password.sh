#!/usr/bin/env bash
set -euo pipefail

# Sets a principal's scaffold password (spec-patch-09 section 3.4).
#
# THE PLAINTEXT NEVER REACHES THE DATABASE, AND THAT IS THE WHOLE POINT OF THIS SCRIPT.
#
# The hazard is narrower than it first looks, and worth stating precisely. bin/run-sql.sh does NOT
# write the script body to its log: it records the INFO headers, a SCRIPT_SHA256, the extracted
# INTENT block, and SQLcl's output, with `set echo off`. So a literal in the SQL is not normally
# logged at all.
#
# But `--log-level debug` sets `set echo on`, and then SQLcl echoes every statement it executes
# into a log under logs/ -- which is tracked in git. A plaintext password in the generated SQL would
# therefore be committed the first time anyone debugged this script, which is exactly when someone
# would. That is a latent trap rather than a certainty, and it is a bad one: it fires under the
# conditions where people are least watching what lands in the repository.
#
# So the key derivation happens HERE, in python3's hashlib.pbkdf2_hmac (standard library, no
# dependency to install), and the generated SQL carries nothing but hex. The password is never an
# argument either -- arguments are visible in `ps` and land in shell history -- it is read from the
# terminal with `read -rs`, twice, and confirmed.
#
# The generated SQL is written outside the repository and removed on exit.
#
# TWO IMPLEMENTATIONS OF PBKDF2 NOW EXIST: this one, and JWT_SCAFFOLD_CRYPTO in the database. They
# must agree exactly or a password set here cannot be verified at login. `--self-test` pins both to
# the same published vector; run it after changing either side.

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Must match jwt_scaffold_crypto.c_default_iterations and c_algorithm.
DEFAULT_ITERATIONS=10000
ALGORITHM="PBKDF2-HMAC-SHA256"

# P="password", S="salt", c=1, dkLen=32. The same constant as jwt_scaffold_crypto_test.c_v1_c1,
# and independently confirmed against the database on 2026-08-26 before either implementation
# existed. Agreement with a common external reference is what makes the two sides agree.
SELF_TEST_VECTOR="120FB6CFFCF8B32C43E7225256C4F837A86548C92CCC35480805987CB70BE17B"

usage() {
  cat >&2 <<'EOF'
Usage: bin/set-principal-password.sh --env <dev|test|prod> --subject <SUBJECT>
                                     [--iterations <n>]
       bin/set-principal-password.sh --self-test

  --subject     The principal's ROAD_PRINCIPALS.SUBJECT, which is also the scaffold username.
                Matched case-insensitively and stored uppercase, as the scaffold mints it.
  --iterations  Defaults to 10000. Lower values are rejected by the table's own constraint below
                1000 and are a bad idea above it.
  --self-test   Verify this script's PBKDF2 against the published vector and exit. Touches no
                database.

The password is prompted for. It is never an argument, never echoed, and never sent to the
database -- only the derived salt and digest are.
EOF
}

ENV_NAME=""
SUBJECT=""
ITERATIONS="${DEFAULT_ITERATIONS}"
SELF_TEST=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env)        [[ $# -ge 2 ]] || { usage; exit 2; }; ENV_NAME="$2"; shift 2 ;;
    --subject)    [[ $# -ge 2 ]] || { usage; exit 2; }; SUBJECT="$2"; shift 2 ;;
    --iterations) [[ $# -ge 2 ]] || { usage; exit 2; }; ITERATIONS="$2"; shift 2 ;;
    --self-test)  SELF_TEST=1; shift ;;
    -h|--help)    usage; exit 0 ;;
    *)            usage; exit 2 ;;
  esac
done

command -v python3 >/dev/null 2>&1 || {
  echo "[ERROR] python3 not found on PATH; it derives the key so the plaintext never reaches SQLcl" >&2
  exit 1
}

if [[ "${SELF_TEST}" -eq 1 ]]; then
  ACTUAL="$(python3 -c "
import hashlib
print(hashlib.pbkdf2_hmac('sha256', b'password', b'salt', 1, 32).hex().upper())
")"
  if [[ "${ACTUAL}" == "${SELF_TEST_VECTOR}" ]]; then
    echo "[INFO] PBKDF2 self-test PASSED (matches jwt_scaffold_crypto_test.c_v1_c1)"
    exit 0
  fi
  echo "[ERROR] PBKDF2 self-test FAILED" >&2
  echo "[ERROR]   expected ${SELF_TEST_VECTOR}" >&2
  echo "[ERROR]   got      ${ACTUAL}" >&2
  exit 1
fi

[[ -n "${ENV_NAME}" ]] || { echo "[ERROR] --env is required" >&2; usage; exit 2; }
[[ -n "${SUBJECT}"  ]] || { echo "[ERROR] --subject is required" >&2; usage; exit 2; }

if ! [[ "${ITERATIONS}" =~ ^[0-9]+$ ]] || [[ "${ITERATIONS}" -lt 1000 ]]; then
  echo "[ERROR] --iterations must be an integer of at least 1000" >&2
  exit 2
fi

SUBJECT_UPPER="$(printf '%s' "${SUBJECT}" | tr '[:lower:]' '[:upper:]')"
if [[ "${SUBJECT_UPPER}" == *"'"* ]]; then
  echo "[ERROR] subject may not contain a single quote" >&2
  exit 2
fi

# read -rs: no echo, and -r so a backslash is a character rather than an escape.
printf 'Password for %s: ' "${SUBJECT_UPPER}" >&2
IFS= read -rs PASSWORD
printf '\n' >&2
printf 'Confirm: ' >&2
IFS= read -rs PASSWORD_CONFIRM
printf '\n' >&2

if [[ -z "${PASSWORD}" ]]; then
  echo "[ERROR] password must not be empty" >&2
  exit 2
fi
if [[ "${PASSWORD}" != "${PASSWORD_CONFIRM}" ]]; then
  echo "[ERROR] passwords do not match" >&2
  exit 2
fi

# Derive here. The password is passed to python on stdin, not as an argument, for the same reason
# it is not a script argument: argv is world-readable via ps.
DERIVED="$(printf '%s' "${PASSWORD}" | python3 -c "
import hashlib, os, sys
password = sys.stdin.buffer.read()
salt = os.urandom(16)
digest = hashlib.pbkdf2_hmac('sha256', password, salt, ${ITERATIONS}, 32)
print(salt.hex().upper())
print(digest.hex().upper())
")"
unset PASSWORD PASSWORD_CONFIRM

SALT_HEX="$(printf '%s' "${DERIVED}" | sed -n '1p')"
HASH_HEX="$(printf '%s' "${DERIVED}" | sed -n '2p')"

if [[ ${#SALT_HEX} -ne 32 || ${#HASH_HEX} -ne 64 ]]; then
  echo "[ERROR] key derivation produced unexpected widths (salt ${#SALT_HEX}, hash ${#HASH_HEX})" >&2
  exit 1
fi

# Outside the repository, so a generated file can never be committed by accident. It carries only
# hex, but the habit is worth more than the exception.
GENERATED_SQL="$(mktemp -t set-principal-password)"
trap 'rm -f "${GENERATED_SQL}"' EXIT

cat > "${GENERATED_SQL}" <<SQL
-- INTENT:
-- Purpose: Set the scaffold password for principal ${SUBJECT_UPPER}.
-- Approach: Resolve the principal by (issuer from the schema JWT profile, subject), then MERGE
--   JWT_SCAFFOLD_CREDENTIALS with a salt and digest derived OUTSIDE the database.
-- Reason: spec-patch-09 section 3.4 -- logs/ is tracked in git and run-sql.sh logs this script, so
--   the plaintext must never appear here. Only hex does.
-- Expected objects: JWT_SCAFFOLD_CREDENTIALS (one row), ROAD_PRINCIPALS.CREDENTIALS_CHANGED_AT
-- Risk: Low. One row, replacing any previous credential for this principal.
-- Prior history checked: generated by bin/set-principal-password.sh.
-- END INTENT

set serveroutput on size unlimited

declare
  l_issuer       varchar2(512 char);
  l_principal_id road_principals.principal_id%type;
  l_profiles     number;
begin
  -- The issuer is read from the JWT profile rather than configured, exactly as 95_data.sql seeds
  -- the bootstrap administrator, so a credential is always attached to the principal that the
  -- currently-registered issuer will actually present.
  select count(*) into l_profiles from user_ords_jwt_profile;
  if l_profiles != 1 then
    raise_application_error(-20001,
      'Expected exactly one ORDS JWT profile, found ' || l_profiles);
  end if;

  select issuer into l_issuer from user_ords_jwt_profile;

  begin
    select principal_id
      into l_principal_id
      from road_principals
     where issuer = l_issuer
       and subject = '${SUBJECT_UPPER}';
  exception
    when no_data_found then
      raise_application_error(-20001,
        'No principal with subject ${SUBJECT_UPPER} for issuer ' || l_issuer
        || ' - create the principal before setting a password');
  end;

  merge into jwt_scaffold_credentials target
  using (
    select l_principal_id                         as principal_id,
           hextoraw('${SALT_HEX}')                as salt,
           hextoraw('${HASH_HEX}')                as password_hash,
           ${ITERATIONS}                          as iterations,
           '${ALGORITHM}'                         as algorithm
      from dual
  ) source
  on (target.principal_id = source.principal_id)
  when matched then
    update set salt          = source.salt,
               password_hash = source.password_hash,
               iterations    = source.iterations,
               algorithm     = source.algorithm
  when not matched then
    insert (principal_id, salt, password_hash, iterations, algorithm)
    values (source.principal_id, source.salt, source.password_hash,
            source.iterations, source.algorithm);

  update road_principals
     set credentials_changed_at = systimestamp
   where principal_id = l_principal_id;

  commit;

  dbms_output.put_line('[INFO] Password set for principal ' || l_principal_id
                       || ' (${SUBJECT_UPPER}), ${ITERATIONS} iterations');
end;
/
SQL

echo "[INFO] Setting password for ${SUBJECT_UPPER} in env ${ENV_NAME} (${ITERATIONS} iterations)" >&2
"${PROJECT_ROOT}/bin/run-sql.sh" --env "${ENV_NAME}" --script "${GENERATED_SQL}"
