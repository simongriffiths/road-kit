#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROAD_CONFIG="${PROJECT_ROOT}/road.config"
GET_TEST_TOKEN_SCRIPT="${PROJECT_ROOT}/bin/get-test-token.sh"

usage() {
  cat >&2 <<'EOF'
Usage: bin/run-endpoint-tests.sh --env <dev|test|prod>
EOF
}

ENV_NAME=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      ENV_NAME="$2"
      shift 2
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
  dev|test|prod)
    ;;
  *)
    echo "[ERROR] Unknown environment: ${ENV_NAME}" >&2
    usage
    exit 2
    ;;
esac

if [[ ! -f "${ROAD_CONFIG}" ]]; then
  echo "[ERROR] Missing road.config at ${ROAD_CONFIG}" >&2
  exit 2
fi

# shellcheck disable=SC1090
source "${ROAD_CONFIG}"

if [[ -z "${APP_NAME:-}" || -z "${UI_BASE_PATH:-}" || -z "${API_BASE_PATH:-}" ]]; then
  echo "[ERROR] road.config must define APP_NAME, UI_BASE_PATH, and API_BASE_PATH" >&2
  exit 2
fi

if [[ -z "${ROAD_ORDS_HOST:-}" ]]; then
  echo "[ERROR] ROAD_ORDS_HOST must be set, for example https://example.adb.region.oraclecloudapps.com" >&2
  exit 2
fi

# Preflighted here rather than discovered at the token mint below, because get-test-token.sh
# deliberately carries no default password.
if [[ -z "${ROAD_TEST_PASSWORD:-}" ]]; then
  echo "[ERROR] ROAD_TEST_PASSWORD must be set" >&2
  exit 2
fi

HOST_BASE="${ROAD_ORDS_HOST%/}"

# Read the jwk_url the database is ACTUALLY configured with, rather than reconstructing the
# conventional one from ROAD_ORDS_HOST. Those two agreeing is the whole point of the check in
# test/endpoint/auth-config.endpoint.sh - reconstructing it here would compare the value to
# itself and pass against any misconfiguration.
resolve_connection() {
  awk -F= -v env_name="$1" '
    /^[[:space:]]*($|#)/ { next }
    {
      key = $1
      value = substr($0, index($0, "=") + 1)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", key)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      if (key == env_name) { print value; exit }
    }
  ' "${PROJECT_ROOT}/config/connections.conf"
}

DB_CONNECTION="$(resolve_connection "${ENV_NAME}")"

if [[ -z "${DB_CONNECTION}" ]]; then
  echo "[ERROR] No SQLcl connection mapped for environment '${ENV_NAME}' in config/connections.conf" >&2
  exit 2
fi

CONFIG_OUTPUT="$(sql -name "${DB_CONNECTION}" <<'EOF'
whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback
set heading off feedback off pagesize 0 verify off echo off termout on linesize 32767
set serveroutput on size unlimited
begin
  for r in (select jwk_url, kid, issuer from jwt_scaffold_config where config_id = 1) loop
    dbms_output.put_line('CONFIG_BEGIN');
    dbms_output.put_line(r.jwk_url);
    dbms_output.put_line(r.kid);
    dbms_output.put_line(r.issuer);
    dbms_output.put_line('CONFIG_END');
  end loop;
end;
/
exit success
EOF
)"

CONFIG_VALUES="$(printf '%s\n' "${CONFIG_OUTPUT}" | sed -n '/CONFIG_BEGIN/,/CONFIG_END/p' | sed '1d;$d' | tr -d '\r')"

export CONFIGURED_JWK_URL="$(printf '%s\n' "${CONFIG_VALUES}" | sed -n '1p')"
export CONFIGURED_KID="$(printf '%s\n' "${CONFIG_VALUES}" | sed -n '2p')"
export CONFIGURED_ISSUER="$(printf '%s\n' "${CONFIG_VALUES}" | sed -n '3p')"

if [[ -z "${CONFIGURED_JWK_URL}" ]]; then
  echo "[ERROR] Could not read jwk_url from JWT_SCAFFOLD_CONFIG via connection ${DB_CONNECTION}" >&2
  exit 2
fi

export ORDS_BASE_URL="${HOST_BASE}/ords/${API_BASE_PATH}/api/v1"
export AUTH_BASE_URL="${HOST_BASE}/ords/${API_BASE_PATH}"
export UI_ROOT_URL="${HOST_BASE}/ords/${UI_BASE_PATH}/ui/${APP_NAME}"
export APP_NAME
export UI_BASE_PATH
export ROAD_ENV_NAME="${ENV_NAME}"
# Assign first, export second, and check both. "export VAR=$(cmd)" does NOT abort under set -e --
# export always succeeds, so a failing command substitution silently yields an empty string. That
# is not hypothetical: WRONG_SCOPE_TOKEN was empty on every run for weeks because the token script
# could not resolve its connection, and every "wrong-scope returns 401" assertion was really
# sending an empty bearer token. It passed, for entirely the wrong reason.
TEST_TOKEN="$("${GET_TEST_TOKEN_SCRIPT}" --env "${ENV_NAME}")"
WRONG_SCOPE_TOKEN="$("${GET_TEST_TOKEN_SCRIPT}" --env "${ENV_NAME}" --scope "wrong.scope")"

if [[ -z "${TEST_TOKEN}" ]]; then
  echo "[ERROR] Could not mint TEST_TOKEN - refusing to run a suite that would pass vacuously" >&2
  exit 2
fi
if [[ -z "${WRONG_SCOPE_TOKEN}" ]]; then
  echo "[ERROR] Could not mint WRONG_SCOPE_TOKEN - refusing to run a suite that would pass vacuously" >&2
  exit 2
fi

export TEST_TOKEN
export WRONG_SCOPE_TOKEN

TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
LOG_DIR="${PROJECT_ROOT}/logs/${ENV_NAME}/runs"
LOG_FILE="${LOG_DIR}/${TIMESTAMP}_endpoint_tests_$$.log"

mkdir -p "${LOG_DIR}"

echo "[INFO] ENV=${ENV_NAME}"
echo "[INFO] HOST_BASE=${HOST_BASE}"
echo "[INFO] ORDS_BASE_URL=${ORDS_BASE_URL}"
echo "[INFO] UI_ROOT_URL=${UI_ROOT_URL}"
echo "[INFO] LOG_FILE=${LOG_FILE}"
echo "[INFO] CONFIGURED_JWK_URL=${CONFIGURED_JWK_URL}"
echo "[INFO] CONFIGURED_ISSUER=${CONFIGURED_ISSUER}"
echo "[INFO] TEST_TOKEN_READY=true"
echo "[INFO] WRONG_SCOPE_TOKEN_READY=true"

bash "${PROJECT_ROOT}/test/endpoint/00_endpoint.sh" 2>&1 | tee "${LOG_FILE}"
