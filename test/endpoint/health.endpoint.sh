#!/usr/bin/env bash
set -euo pipefail

RESPONSE_FILE="$(mktemp)"
STATUS="$(curl -s -w "%{http_code}" -o "${RESPONSE_FILE}" "${ORDS_BASE_URL}/health/")"
BODY="$(cat "${RESPONSE_FILE}")"
rm "${RESPONSE_FILE}"

assert_http "GET /health/ returns 200" 200 "${STATUS}" "${BODY}"
