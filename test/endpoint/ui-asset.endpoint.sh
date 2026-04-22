#!/usr/bin/env bash
set -euo pipefail

source bin/assert-http.sh

RESPONSE_FILE="$(mktemp)"
STATUS="$(curl -s -w "%{http_code}" -o "${RESPONSE_FILE}" "${UI_ROOT_URL}/index.html")"
BODY="$(cat "${RESPONSE_FILE}")"
rm "${RESPONSE_FILE}"

assert_http "GET /ui/<app>/index.html returns 200" 200 "${STATUS}" "${BODY}"

ASSET_PATH="$(printf "%s" "${BODY}" | sed -n 's/.*src="\([^"]*\/assets\/[^"]*\.js\)".*/\1/p' | head -n 1)"
if [[ -z "${ASSET_PATH}" ]]; then
  echo "[FAIL] Could not find JS asset path in index.html" >&2
  echo "[FAIL] Response: ${BODY}" >&2
  exit 1
fi

ASSET_RESPONSE_FILE="$(mktemp)"
ASSET_STATUS="$(curl -s -w "%{http_code}" -o "${ASSET_RESPONSE_FILE}" "${ROAD_ORDS_HOST%/}${ASSET_PATH}")"
ASSET_BODY="$(cat "${ASSET_RESPONSE_FILE}")"
rm "${ASSET_RESPONSE_FILE}"

assert_http "GET bundled JS asset returns 200" 200 "${ASSET_STATUS}" "${ASSET_BODY}"
assert_body_contains "Bundled JS asset references deployed UI path" "${ASSET_BODY}" "/ords/${UI_BASE_PATH}/ui/${APP_NAME}"
