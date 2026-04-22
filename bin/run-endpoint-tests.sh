#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROAD_CONFIG="${PROJECT_ROOT}/road.config"

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

HOST_BASE="${ROAD_ORDS_HOST%/}"
export ORDS_BASE_URL="${HOST_BASE}/ords/${API_BASE_PATH}/api/v1"
export UI_ROOT_URL="${HOST_BASE}/ords/${UI_BASE_PATH}/ui/${APP_NAME}"
export APP_NAME
export UI_BASE_PATH

TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
LOG_DIR="${PROJECT_ROOT}/logs/${ENV_NAME}/runs"
LOG_FILE="${LOG_DIR}/${TIMESTAMP}_endpoint_tests_$$.log"

mkdir -p "${LOG_DIR}"

echo "[INFO] ENV=${ENV_NAME}"
echo "[INFO] HOST_BASE=${HOST_BASE}"
echo "[INFO] ORDS_BASE_URL=${ORDS_BASE_URL}"
echo "[INFO] UI_ROOT_URL=${UI_ROOT_URL}"
echo "[INFO] LOG_FILE=${LOG_FILE}"

bash "${PROJECT_ROOT}/test/endpoint/00_endpoint.sh" 2>&1 | tee "${LOG_FILE}"
