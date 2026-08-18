#!/usr/bin/env bash
set -euo pipefail

# Ensure this environment's JWT scaffold has its OWN RSA signing key.
#
# The key is generated locally with openssl, piped straight into SQLcl, and stored only in
# JWT_SCAFFOLD_CONFIG. It is never written to a file and never enters git. This replaces the
# previous arrangement where one key was committed to the template and shared verbatim by every
# app scaffolded from it. See planning/spec-patch-04-auth-config-derivation.md section 5.4.
#
# Idempotent: does nothing when the environment already has its own key, so it is safe to run on
# every deploy. Two cases force regeneration - no key at all, and the known template key.
#
# ENCODING, established empirically (do not "fix" this):
#   DBMS_CRYPTO.SIGN with KEY_TYPE_RSA wants the base64 TEXT of a PKCS#1 DER key, passed through
#   utl_i18n.string_to_raw. Passing properly decoded binary DER fails with ORA-28817. OpenSSL 3.x
#   emits PKCS#8 by default, so -traditional is required on BOTH genrsa and rsa.

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROAD_CONFIG="${PROJECT_ROOT}/road.config"
CONNECTIONS_CONF="${PROJECT_ROOT}/config/connections.conf"

# kid shipped in the template historically. Any environment still carrying it is using the shared,
# publicly-readable key and must be rotated, not left alone.
TEMPLATE_KID="road-dev-key-001"

usage() {
  cat >&2 <<'EOF'
Usage: bin/ensure-auth-key.sh --env <dev|test|prod> [--rotate]

  --rotate  Replace an existing key. Invalidates every outstanding token immediately.

Generates a per-environment RSA signing key if one is missing (or is the shared template key)
and stores it only in JWT_SCAFFOLD_CONFIG. Safe to run on every deploy.
EOF
}

ENV_NAME=""
ROTATE="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      ENV_NAME="$2"
      shift 2
      ;;
    --rotate)
      ROTATE="true"
      shift
      ;;
    *)
      usage
      exit 2
      ;;
  esac
done

if [[ -z "${ENV_NAME}" ]]; then
  usage
  exit 2
fi

case "${ENV_NAME}" in
  dev|test|prod) ;;
  *)
    echo "[ERROR] Unknown environment: ${ENV_NAME}" >&2
    exit 2
    ;;
esac

if [[ "${ENV_NAME}" == "prod" && "${ALLOW_PROD_SQL:-}" != "yes" ]]; then
  echo "[ERROR] Production key management requires ALLOW_PROD_SQL=yes" >&2
  exit 2
fi

for required in "${ROAD_CONFIG}" "${CONNECTIONS_CONF}"; do
  if [[ ! -f "${required}" ]]; then
    echo "[ERROR] Missing required file: ${required}" >&2
    exit 2
  fi
done

# shellcheck disable=SC1090
source "${ROAD_CONFIG}"

if [[ -z "${APP_NAME:-}" ]]; then
  echo "[ERROR] road.config must define APP_NAME" >&2
  exit 2
fi

if ! command -v openssl >/dev/null 2>&1; then
  echo "[ERROR] openssl not found on PATH - required to generate the RSA keypair" >&2
  echo "[ERROR] Oracle cannot do this: DBMS_CRYPTO signs and verifies RSA but cannot generate keys" >&2
  exit 127
fi

DB_CONNECTION="$(awk -F= -v env_name="${ENV_NAME}" '
  /^[[:space:]]*($|#)/ { next }
  {
    key = $1
    value = substr($0, index($0, "=") + 1)
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", key)
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
    if (key == env_name) { print value; exit }
  }
' "${CONNECTIONS_CONF}")"

if [[ -z "${DB_CONNECTION}" ]]; then
  echo "[ERROR] No SQLcl connection mapped for '${ENV_NAME}' in config/connections.conf" >&2
  exit 2
fi

run_sql() {
  sql -name "${DB_CONNECTION}" 2>&1
}

# --- What is already there? -------------------------------------------------------------------

CURRENT_STATE="$(run_sql <<'EOF' | sed -n '/STATE_BEGIN/,/STATE_END/p' | sed '1d;$d' | tr -d '\r'
whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback
set heading off feedback off pagesize 0 verify off echo off termout on linesize 32767
set serveroutput on size unlimited
declare
  l_kid     varchar2(255);
  l_has_key varchar2(5);
begin
  begin
    select nvl(kid, '-'),
           case when private_key_b64 is null then 'false' else 'true' end
      into l_kid, l_has_key
      from jwt_scaffold_config
     where config_id = 1;
  exception
    when no_data_found then
      l_kid := '-';
      l_has_key := 'norow';
  end;
  dbms_output.put_line('STATE_BEGIN');
  dbms_output.put_line(l_has_key);
  dbms_output.put_line(l_kid);
  dbms_output.put_line('STATE_END');
end;
/
exit success
EOF
)"

HAS_KEY="$(printf '%s\n' "${CURRENT_STATE}" | sed -n '1p')"
CURRENT_KID="$(printf '%s\n' "${CURRENT_STATE}" | sed -n '2p')"

if [[ -z "${HAS_KEY}" ]]; then
  echo "[ERROR] Could not read JWT_SCAFFOLD_CONFIG via connection ${DB_CONNECTION}" >&2
  echo "[ERROR] Deploy the schema first: bin/run-sql.sh --env ${ENV_NAME} --script deploy/create/00_full.sql" >&2
  exit 1
fi

if [[ "${HAS_KEY}" == "norow" ]]; then
  echo "[ERROR] No JWT_SCAFFOLD_CONFIG row - render and deploy the auth config first:" >&2
  echo "[ERROR]   bin/render-auth-config.sh --env ${ENV_NAME}" >&2
  echo "[ERROR]   bin/run-sql.sh --env ${ENV_NAME} --script deploy/create/80_standalone.generated.sql" >&2
  exit 1
fi

REASON=""
if [[ "${HAS_KEY}" == "false" ]]; then
  REASON="no key present"
elif [[ "${CURRENT_KID}" == "${TEMPLATE_KID}" ]]; then
  REASON="environment is using the shared template key (${TEMPLATE_KID}), which is public"
elif [[ "${ROTATE}" == "true" ]]; then
  REASON="--rotate requested"
fi

if [[ -z "${REASON}" ]]; then
  echo "[INFO] ENV=${ENV_NAME}"
  echo "[INFO] Key already present and app-specific (kid=${CURRENT_KID}) - nothing to do"
  exit 0
fi

echo "[INFO] ENV=${ENV_NAME}"
echo "[INFO] Generating a new signing key: ${REASON}"

# --- Generate, entirely in memory -------------------------------------------------------------

PRIVATE_PEM="$(openssl genrsa -traditional 2048 2>/dev/null)"
PRIVATE_KEY_B64="$(printf '%s\n' "${PRIVATE_PEM}" | openssl rsa -traditional -outform DER 2>/dev/null | base64 | tr -d '\n')"
MODULUS_HEX="$(printf '%s\n' "${PRIVATE_PEM}" | openssl rsa -noout -modulus 2>/dev/null | sed 's/^Modulus=//')"
EXPONENT_DEC="$(printf '%s\n' "${PRIVATE_PEM}" | openssl rsa -noout -text 2>/dev/null | sed -n 's/.*publicExponent: \([0-9]*\) .*/\1/p')"

if [[ -z "${PRIVATE_KEY_B64}" || -z "${MODULUS_HEX}" || -z "${EXPONENT_DEC}" ]]; then
  echo "[ERROR] Key generation failed - openssl produced incomplete output" >&2
  exit 1
fi

# JWKS needs unpadded base64url of the raw big-endian modulus and exponent bytes.
JWK_PARTS="$(python3 - "${MODULUS_HEX}" "${EXPONENT_DEC}" <<'PY'
import base64, sys

def b64url(raw: bytes) -> str:
    return base64.urlsafe_b64encode(raw).decode().rstrip('=')

modulus = bytes.fromhex(sys.argv[1])
exponent_int = int(sys.argv[2])
exponent = exponent_int.to_bytes((exponent_int.bit_length() + 7) // 8, 'big')
print(b64url(modulus))
print(b64url(exponent))
PY
)"

PUBLIC_N="$(printf '%s\n' "${JWK_PARTS}" | sed -n '1p')"
PUBLIC_E="$(printf '%s\n' "${JWK_PARTS}" | sed -n '2p')"

# kid must change whenever the key changes: ORDS caches JWKS, and reusing a kid across a rotation
# invites validation against a cached stale key.
KEY_FINGERPRINT="$(printf '%s' "${PRIVATE_KEY_B64}" | shasum -a 256 | awk '{print substr($1, 1, 12)}')"
NEW_KID="${APP_NAME}-${ENV_NAME}-${KEY_FINGERPRINT}"

sql_escape() {
  printf "%s" "$1" | sed "s/'/''/g"
}

# --- Store, and only ever in the database ------------------------------------------------------

UPDATE_OUTPUT="$(run_sql <<EOF
whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback
set heading off feedback off pagesize 0 verify off echo off termout on linesize 32767
set serveroutput on size unlimited
declare
  l_rows number;
begin
  update jwt_scaffold_config
     set private_key_b64 = '$(sql_escape "${PRIVATE_KEY_B64}")',
         public_n        = '$(sql_escape "${PUBLIC_N}")',
         public_e        = '$(sql_escape "${PUBLIC_E}")',
         kid             = '$(sql_escape "${NEW_KID}")',
         updated_at      = systimestamp
   where config_id = 1;
  l_rows := sql%rowcount;
  if l_rows <> 1 then
    rollback;
    raise_application_error(-20001, 'Expected to update exactly 1 config row, updated ' || l_rows);
  end if;
  commit;
  dbms_output.put_line('KEY_STORED');
end;
/
exit success
EOF
)"

if ! printf '%s' "${UPDATE_OUTPUT}" | grep -q "KEY_STORED"; then
  echo "[ERROR] Failed to store the generated key" >&2
  printf '%s\n' "${UPDATE_OUTPUT}" >&2
  exit 1
fi

echo "[INFO] New kid: ${NEW_KID}"
echo "[INFO] Key stored in JWT_SCAFFOLD_CONFIG only - not written to disk"
echo "[INFO] Re-register the JWT profile and confirm ORDS has refreshed its cached JWKS:"
echo "[INFO]   bin/run-sql.sh --env ${ENV_NAME} --script deploy/create/80_standalone.generated.sql"
echo "[INFO]   bin/run-endpoint-tests.sh --env ${ENV_NAME}"
