#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROAD_CONFIG="${PROJECT_ROOT}/road.config"
APP_DIR="${PROJECT_ROOT}/hello_world"

usage() {
  cat >&2 <<'EOF'
Usage: bin/run-browser-smoke.sh --env <dev|test|prod>
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

if [[ ! -f "${APP_DIR}/package.json" ]]; then
  echo "[ERROR] Missing frontend package at ${APP_DIR}" >&2
  exit 2
fi

# shellcheck disable=SC1090
source "${ROAD_CONFIG}"

if [[ -z "${APP_NAME:-}" || -z "${UI_BASE_PATH:-}" ]]; then
  echo "[ERROR] road.config must define APP_NAME and UI_BASE_PATH" >&2
  exit 2
fi

if [[ -z "${ROAD_ORDS_HOST:-}" ]]; then
  echo "[ERROR] ROAD_ORDS_HOST must be set" >&2
  exit 2
fi

if ! command -v npx >/dev/null 2>&1; then
  echo "[ERROR] npx not found on PATH" >&2
  exit 127
fi

export ROAD_APP_URL="${ROAD_ORDS_HOST%/}/ords/${UI_BASE_PATH}/ui/${APP_NAME}/"
export ROAD_TEST_USERNAME="${ROAD_TEST_USERNAME:-ADMIN}"
export ROAD_TEST_PASSWORD="${ROAD_TEST_PASSWORD:-***REMOVED-CREDENTIAL***}"
export PLAYWRIGHT_BROWSERS_PATH="${PROJECT_ROOT}/.playwright-browsers"

TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
LOG_DIR="${PROJECT_ROOT}/logs/${ENV_NAME}/runs"
LOG_FILE="${LOG_DIR}/${TIMESTAMP}_browser_smoke_$$.log"

mkdir -p "${LOG_DIR}"

echo "[INFO] ENV=${ENV_NAME}"
echo "[INFO] ROAD_APP_URL=${ROAD_APP_URL}"
echo "[INFO] ROAD_TEST_USERNAME=${ROAD_TEST_USERNAME}"
echo "[INFO] LOG_FILE=${LOG_FILE}"

(
  cd "${APP_DIR}"
  npx playwright test e2e/login.smoke.spec.ts --config playwright.config.ts
) 2>&1 | tee "${LOG_FILE}"
