#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROAD_CONFIG="${PROJECT_ROOT}/road.config"

usage() {
  cat >&2 <<'EOF'
Usage: bin/get-test-token.sh --env <dev|test|prod> [--username <name>] [--password <value>]
                            [--scope <scope>] [--issuer <iss>] [--audience <aud>] [--ttl <minutes>]

--scope, --issuer, --audience and --ttl mint directly through SQLcl rather than logging in, and
exist so the conformance suite can build the negative cases in authentication-spec-v1.md section 12.
A negative --ttl produces an already-expired token.
EOF
}

ENV_NAME=""
REQUESTED_SCOPE=""
REQUESTED_USERNAME=""
REQUESTED_PASSWORD=""
REQUESTED_ISSUER=""
REQUESTED_AUDIENCE=""
REQUESTED_TTL=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      ENV_NAME="$2"
      shift 2
      ;;
    --username)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      REQUESTED_USERNAME="$2"
      shift 2
      ;;
    --password)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      REQUESTED_PASSWORD="$2"
      shift 2
      ;;
    --scope)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      REQUESTED_SCOPE="$2"
      shift 2
      ;;
    --issuer)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      REQUESTED_ISSUER="$2"
      shift 2
      ;;
    --audience)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      REQUESTED_AUDIENCE="$2"
      shift 2
      ;;
    --ttl)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      REQUESTED_TTL="$2"
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

if [[ ! -f "${ROAD_CONFIG}" ]]; then
  echo "[ERROR] Missing road.config at ${ROAD_CONFIG}" >&2
  exit 2
fi

# shellcheck disable=SC1090
source "${ROAD_CONFIG}"

if [[ -z "${API_BASE_PATH:-}" ]]; then
  echo "[ERROR] road.config must define API_BASE_PATH" >&2
  exit 2
fi

# Resolve the SQLcl connection the same way bin/run-sql.sh does, from config/connections.conf.
# This was previously a hardcoded map to app_dev / app_test / app_prod, which are the example
# names and do not exist -- so every --scope invocation failed. It failed invisibly, because
# "export VAR=$(...)" does not abort under set -e: the caller got an empty token and carried on.
SQL_RUNNER_CONFIG="${SQL_RUNNER_CONFIG:-${PROJECT_ROOT}/config/connections.conf}"

if [[ ! -f "${SQL_RUNNER_CONFIG}" ]]; then
  echo "[ERROR] SQL runner config not found: ${SQL_RUNNER_CONFIG}" >&2
  exit 2
fi

CONNECTION="$(awk -F= -v env_name="${ENV_NAME}" '
  /^[[:space:]]*($|#)/ { next }
  {
    key = $1
    value = substr($0, index($0, "=") + 1)
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", key)
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
    if (key == env_name) { print value; exit }
  }
' "${SQL_RUNNER_CONFIG}")"

if [[ -z "${CONNECTION}" ]]; then
  echo "[ERROR] Unknown environment: ${ENV_NAME}" >&2
  echo "[ERROR] Add '"'"'${ENV_NAME}=<sqlcl-saved-connection>'"'"' to ${SQL_RUNNER_CONFIG}" >&2
  usage
  exit 2
fi

TEST_USERNAME="${REQUESTED_USERNAME:-${ROAD_TEST_USERNAME:-ADMIN}}"
TEST_PASSWORD="${REQUESTED_PASSWORD:-${ROAD_TEST_PASSWORD:-}}"

sql_literal() {
  printf "%s" "$1" | sed "s/'/''/g"
}

# Any claim override takes the direct-mint path: logging in cannot produce a token whose issuer,
# audience or expiry differs from the configured one.
if [[ -n "${REQUESTED_SCOPE}${REQUESTED_ISSUER}${REQUESTED_AUDIENCE}${REQUESTED_TTL}" ]]; then
  if ! command -v sql >/dev/null 2>&1; then
    echo "[ERROR] SQLcl binary not found on PATH: sql" >&2
    exit 127
  fi

  # Null rather than an empty string, so each unset override falls back to JWT_SCAFFOLD_CONFIG.
  sql_arg() { if [[ -z "$1" ]]; then printf 'null'; else printf "'%s'" "$(sql_literal "$1")"; fi; }
  SCOPE_ARG="$(sql_arg "${REQUESTED_SCOPE}")"
  ISSUER_ARG="$(sql_arg "${REQUESTED_ISSUER}")"
  AUDIENCE_ARG="$(sql_arg "${REQUESTED_AUDIENCE}")"
  if [[ -z "${REQUESTED_TTL}" ]]; then TTL_ARG="null"; else TTL_ARG="${REQUESTED_TTL}"; fi

  TOKEN_OUTPUT="$(sql -name "${CONNECTION}" <<EOF
whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback
set heading off
set feedback off
set pagesize 0
set verify off
set echo off
set termout on
set serveroutput on size unlimited
set linesize 32767
set long 1000000
declare
  l_token clob;
begin
  l_token := jwt_scaffold_auth_api.issue_token(
    p_username    => '$(sql_literal "${TEST_USERNAME}")',
    p_scope       => ${SCOPE_ARG},
    p_issuer      => ${ISSUER_ARG},
    p_audience    => ${AUDIENCE_ARG},
    p_ttl_minutes => ${TTL_ARG}
  );
  dbms_output.put_line('TOKEN_BEGIN');
  dbms_output.put_line(dbms_lob.substr(l_token, 32767, 1));
  dbms_output.put_line('TOKEN_END');
end;
/
exit success
EOF
)"

  TOKEN="$(printf '%s\n' "${TOKEN_OUTPUT}" | sed -n '/TOKEN_BEGIN/,/TOKEN_END/p' | sed '1d;$d' | tr -d '\r')"

  if [[ -z "${TOKEN}" ]]; then
    echo "[ERROR] SQL token mint did not return a token" >&2
    exit 1
  fi

  printf '%s\n' "${TOKEN}"
  exit 0
fi

if [[ -z "${TEST_PASSWORD}" ]]; then
  echo "[ERROR] No password supplied. Pass --password, or set ROAD_TEST_PASSWORD." >&2
  echo "[ERROR] There is deliberately no default: a committed credential is a live credential." >&2
  exit 2
fi

if [[ -z "${ROAD_ORDS_HOST:-}" ]]; then
  echo "[ERROR] ROAD_ORDS_HOST must be set" >&2
  exit 2
fi

LOGIN_URL="${ROAD_ORDS_HOST%/}/ords/${API_BASE_PATH}/jwt-auth/login"

RESPONSE_FILE="$(mktemp)"
cleanup() {
  rm -f "${RESPONSE_FILE}"
}
trap cleanup EXIT

STATUS="$(curl -s -w "%{http_code}" \
  -H "Content-Type: application/json" \
  -o "${RESPONSE_FILE}" \
  -d "{\"username\":\"${TEST_USERNAME}\",\"password\":\"${TEST_PASSWORD}\"}" \
  "${LOGIN_URL}")"

BODY="$(cat "${RESPONSE_FILE}")"

if [[ "${STATUS}" != "200" ]]; then
  echo "[ERROR] Token request failed with HTTP ${STATUS}" >&2
  echo "[ERROR] Response: ${BODY}" >&2
  exit 1
fi

TOKEN="$(python3 - <<'PY' "${RESPONSE_FILE}"
import json
import sys

with open(sys.argv[1], 'r', encoding='utf-8') as f:
    data = json.load(f)

print(data.get('access_token', ''))
PY
)"

if [[ -z "${TOKEN}" ]]; then
  echo "[ERROR] Login response did not contain access_token" >&2
  echo "[ERROR] Response: ${BODY}" >&2
  exit 1
fi

printf '%s\n' "${TOKEN}"
