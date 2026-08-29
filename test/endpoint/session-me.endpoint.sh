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
# Asserts that session.me.read is PRESENT in the scope, not that it is the whole of it. The
# assertion used to be a prefix match against a fixed, single-privilege scope read from
# JWT_SCAFFOLD_CONFIG.SCOPE_NAME. Since build plan 09 phase 4 the scope is derived per principal,
# so ADMIN legitimately carries every ORDS privilege it holds -- road.admin.rw as well -- in
# alphabetical order, and a prefix match can only pass for a principal entitled to exactly one
# thing. Testing for presence is also the property that actually matters: the caller can reach
# this endpoint.
assert_body_contains "session/me scope carries session.me.read" "${TOKEN_BODY}" "session.me.read"

FORBIDDEN_RESPONSE_FILE="$(mktemp)"
FORBIDDEN_STATUS="$(curl -s -w "%{http_code}" \
  -H "Authorization: Bearer ${WRONG_SCOPE_TOKEN}" \
  -o "${FORBIDDEN_RESPONSE_FILE}" \
  "${ORDS_BASE_URL}/session/me/")"
FORBIDDEN_BODY="$(cat "${FORBIDDEN_RESPONSE_FILE}")"
rm "${FORBIDDEN_RESPONSE_FILE}"

assert_http "GET /session/me/ with wrong scope returns 401" 401 "${FORBIDDEN_STATUS}" "${FORBIDDEN_BODY}"
