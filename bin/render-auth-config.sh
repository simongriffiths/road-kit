#!/usr/bin/env bash
set -euo pipefail

# Render deploy/create/80_standalone.sql.tmpl into 80_standalone.generated.sql, substituting the
# environment-derived auth scaffold values.
#
# Only jwk_url depends on which ADB the app is deployed to. Issuer is a logical URN built from
# APP_NAME and the environment name, so moving an app between instances does not change it. See
# planning/spec-patch-04-auth-config-derivation.md section 5.1.

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROAD_CONFIG="${PROJECT_ROOT}/road.config"
TEMPLATE="${PROJECT_ROOT}/deploy/create/80_standalone.sql.tmpl"
OUTPUT="${PROJECT_ROOT}/deploy/create/80_standalone.generated.sql"

usage() {
  cat >&2 <<'EOF'
Usage: bin/render-auth-config.sh --env <dev|test|prod>

Requires ROAD_ORDS_HOST to be set, for example:
  export ROAD_ORDS_HOST=https://example-db.adb.<region>.oraclecloudapps.com
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

if [[ ! -f "${TEMPLATE}" ]]; then
  echo "[ERROR] Missing template: ${TEMPLATE}" >&2
  exit 2
fi

# shellcheck disable=SC1090
source "${ROAD_CONFIG}"

if [[ -z "${APP_NAME:-}" || -z "${API_BASE_PATH:-}" ]]; then
  echo "[ERROR] road.config must define APP_NAME and API_BASE_PATH" >&2
  exit 2
fi

# Deliberately no default. A plausible-but-wrong host is exactly how the original defect survived
# from this template's original prototyping instance into a built app without anyone noticing.
if [[ -z "${ROAD_ORDS_HOST:-}" ]]; then
  echo "[ERROR] ROAD_ORDS_HOST must be set, for example https://example.adb.region.oraclecloudapps.com" >&2
  echo "[ERROR] This is the only host-dependent value in the auth config - there is no default" >&2
  exit 2
fi

HOST_BASE="${ROAD_ORDS_HOST%/}"

ISSUER="urn:road:${APP_NAME}:${ENV_NAME}"
JWK_URL="${HOST_BASE}/ords/${API_BASE_PATH}/jwt-auth/.well-known/jwks.json"

sql_escape() {
  printf "%s" "$1" | sed "s/'/''/g"
}

ISSUER_SQL="$(sql_escape "${ISSUER}")"
JWK_URL_SQL="$(sql_escape "${JWK_URL}")"
API_BASE_PATH_SQL="$(sql_escape "${API_BASE_PATH}")"

CONTENT="$(cat "${TEMPLATE}")"
CONTENT="${CONTENT//@@ROAD_ISSUER@@/${ISSUER_SQL}}"
CONTENT="${CONTENT//@@ROAD_JWK_URL@@/${JWK_URL_SQL}}"
CONTENT="${CONTENT//@@ROAD_API_BASE_PATH@@/${API_BASE_PATH_SQL}}"

if [[ "${CONTENT}" == *"@@ROAD_"* ]]; then
  echo "[ERROR] Unsubstituted placeholder remains in rendered output:" >&2
  printf '%s\n' "${CONTENT}" | grep -o '@@ROAD_[A-Z_]*@@' | sort -u >&2
  exit 1
fi

printf '%s\n' "${CONTENT}" > "${OUTPUT}"

echo "[INFO] ENV=${ENV_NAME}"
echo "[INFO] ISSUER=${ISSUER}"
echo "[INFO] JWK_URL=${JWK_URL}"
echo "[INFO] RENDERED=${OUTPUT#"${PROJECT_ROOT}/"}"
