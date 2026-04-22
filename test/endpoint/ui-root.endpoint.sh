#!/usr/bin/env bash
set -euo pipefail

source bin/assert-http.sh

RESPONSE_FILE="$(mktemp)"
STATUS="$(curl -s -w "%{http_code}" -o "${RESPONSE_FILE}" "${UI_ROOT_URL}/")"
BODY="$(cat "${RESPONSE_FILE}")"
rm "${RESPONSE_FILE}"

assert_http "GET /ui/<app>/ returns 200" 200 "${STATUS}" "${BODY}"
assert_body_contains "UI root returns HTML shell" "${BODY}" "<div id=\"root\"></div>"
