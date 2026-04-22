#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROAD_CONFIG="${PROJECT_ROOT}/road.config"

usage() {
  cat >&2 <<'EOF'
Usage: bin/get-test-token.sh --env <dev|test|prod>
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

if [[ -z "${ROAD_ORDS_HOST:-}" ]]; then
  echo "[ERROR] ROAD_ORDS_HOST must be set" >&2
  exit 2
fi

TEST_USERNAME="${ROAD_TEST_USERNAME:-ADMIN}"
TEST_PASSWORD="${ROAD_TEST_PASSWORD:-***REMOVED-CREDENTIAL***}"
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
