#!/usr/bin/env bash
set -euo pipefail

source bin/assert-http.sh

RESPONSE_FILE="$(mktemp)"
STATUS="$(curl -s -w "%{http_code}" -o "${RESPONSE_FILE}" "${UI_ROOT_URL}/dashboard")"
BODY="$(cat "${RESPONSE_FILE}")"
rm "${RESPONSE_FILE}"

assert_http "GET SPA fallback route returns 200" 200 "${STATUS}" "${BODY}"
assert_body_contains "SPA fallback returns index.html shell" "${BODY}" "<div id=\"root\"></div>"
