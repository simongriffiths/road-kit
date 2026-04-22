#!/usr/bin/env bash
set -euo pipefail

source bin/assert-http.sh

NO_TOKEN_RESPONSE_FILE="$(mktemp)"
NO_TOKEN_STATUS="$(curl -s -w "%{http_code}" -o "${NO_TOKEN_RESPONSE_FILE}" "${ORDS_BASE_URL}/session/me/")"
NO_TOKEN_BODY="$(cat "${NO_TOKEN_RESPONSE_FILE}")"
rm "${NO_TOKEN_RESPONSE_FILE}"

assert_http "GET /session/me/ without token returns 401" 401 "${NO_TOKEN_STATUS}" "${NO_TOKEN_BODY}"

TOKEN_RESPONSE_FILE="$(mktemp)"
TOKEN_STATUS="$(curl -s -w "%{http_code}" \
  -H "Authorization: Bearer ${TEST_TOKEN}" \
  -o "${TOKEN_RESPONSE_FILE}" \
  "${ORDS_BASE_URL}/session/me/")"
TOKEN_BODY="$(cat "${TOKEN_RESPONSE_FILE}")"
rm "${TOKEN_RESPONSE_FILE}"

assert_http "GET /session/me/ with token returns 200" 200 "${TOKEN_STATUS}" "${TOKEN_BODY}"
assert_body_contains "session/me returns ADMIN principal" "${TOKEN_BODY}" "\"principal\":\"ADMIN\""
assert_body_contains "session/me returns configured scope" "${TOKEN_BODY}" "\"scope\":\"session.me.read\""
