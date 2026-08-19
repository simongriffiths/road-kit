#!/usr/bin/env bash
set -euo pipefail

# GET /api/v1/admin/principals/ -- the directory the roles screen browses
# (ui-authorisation-design-v1.md section 5).
#
# The PL/SQL suite already covers the filtering, clamping and paging logic against the package
# directly. What only an HTTP test can prove is the layer between: that the handler establishes
# session context, that ORDS binds the four query parameters at all, and that "query" survives the
# reserved-"q" collision documented on the module.

source bin/assert-http.sh

PRINCIPALS_URL="${ORDS_BASE_URL}/admin/principals/"

get_with() {
  # Echoes "<status>|<body>" for a GET with the given Authorization header value.
  local url="$1" auth="${2-}"
  local body_file status
  body_file="$(mktemp)"
  if [[ -n "${auth}" ]]; then
    status="$(curl -s -o "${body_file}" -w '%{http_code}' -H "Authorization: ${auth}" "${url}")"
  else
    status="$(curl -s -o "${body_file}" -w '%{http_code}' "${url}")"
  fi
  printf '%s|%s' "${status}" "$(cat "${body_file}")"
  rm -f "${body_file}"
}

check() {
  local description="$1" expected="$2" url="$3" auth="${4-}"
  local result status body
  result="$(get_with "${url}" "${auth}")"
  status="${result%%|*}"
  body="${result#*|}"
  assert_http "${description}" "${expected}" "${status}" "${body}"
  LAST_BODY="${body}"
}

echo "[INFO] admin-principals: GET /admin/principals/"

check "GET /admin/principals/ without token returns 401" 401 "${PRINCIPALS_URL}"

check "GET /admin/principals/ with an admin token returns 200" 200 \
  "${PRINCIPALS_URL}" "Bearer ${TEST_TOKEN}"

# The OrdsCollection wrapper the React conventions already type against
# (ords-api-design-standards-v1.md section 6.1). Asserting the envelope keys rather than a row
# count, because the row count depends on how many principals the environment has accumulated.
assert_body_contains "collection carries items" "${LAST_BODY}" '"items"'
assert_body_contains "collection carries hasMore" "${LAST_BODY}" '"hasMore"'
assert_body_contains "collection carries offset" "${LAST_BODY}" '"offset"'
assert_body_contains "principal rows carry their roles" "${LAST_BODY}" '"roles"'
# The bootstrap principal is seeded by 95_data.sql and is therefore present in every environment.
assert_body_contains "the bootstrap principal is listed" "${LAST_BODY}" '"subject":"ADMIN"'

# Paging. limit=1 must be honoured rather than ignored -- an unbound :limit would silently return
# the default page and this assertion is what catches it.
check "limit is bound and honoured" 200 "${PRINCIPALS_URL}?limit=1&offset=0" "Bearer ${TEST_TOKEN}"
assert_body_contains "limit=1 is echoed back" "${LAST_BODY}" '"limit":1'
assert_body_contains "limit=1 returns one row" "${LAST_BODY}" '"count":1'

# Clamping, over HTTP rather than only in PL/SQL: an unclamped limit is a denial-of-service
# parameter and the clamp has to survive the string-to-number conversion in the handler.
check "an oversized limit is clamped" 200 "${PRINCIPALS_URL}?limit=9999" "Bearer ${TEST_TOKEN}"
assert_body_contains "limit clamped to 100" "${LAST_BODY}" '"limit":100'

# A non-numeric limit is a 400 -- and it is ORDS's 400, raised before any PL/SQL runs. Confirmed
# 2026-08-19 by probing dev: the body carries ORDS's own envelope
# ("code":"BadRequest", "type":"tag:oracle.com,2020:error/BadRequest"), not error_api's
# {"error","message"} shape. ORDS reserves limit and offset for pagination and validates them as
# numeric itself, the same way it reserves "q".
#
# The handler's DEFAULT NULL ON CONVERSION ERROR therefore cannot fire for these two parameters. It
# stays because it is the correct thing for a bind ORDS does not pre-validate, but nothing reaching
# these two ever tests it -- which is precisely why this assertion pins the ORDS behaviour instead.
check "a non-numeric limit is rejected by ORDS before the handler" 400 \
  "${PRINCIPALS_URL}?limit=abc" "Bearer ${TEST_TOKEN}"
assert_body_contains "the 400 is ORDS's, not the application's" "${LAST_BODY}" 'BadRequest'

check "a non-numeric offset is rejected the same way" 400 \
  "${PRINCIPALS_URL}?offset=abc" "Bearer ${TEST_TOKEN}"

# "query", not "q". ORDS reserves q globally and answers a non-JSON value with a platform 400, so
# this assertion is the guard against someone "fixing" the parameter name back to the one the
# design doc originally specified.
check "query filters, and the parameter name survives" 200 \
  "${PRINCIPALS_URL}?query=ADMIN" "Bearer ${TEST_TOKEN}"
assert_body_contains "query matched the bootstrap principal" "${LAST_BODY}" '"subject":"ADMIN"'

check "a query matching nothing returns an empty page" 200 \
  "${PRINCIPALS_URL}?query=zzz-no-such-principal-zzz" "Bearer ${TEST_TOKEN}"
assert_body_contains "empty page reports count 0" "${LAST_BODY}" '"count":0'
assert_body_contains "empty page reports hasMore false" "${LAST_BODY}" '"hasMore":false'

# An unrecognised status is refused rather than ignored. Ignoring it would return the unfiltered
# list while the caller believed it had filtered.
check "an unrecognised status is a 400" 400 \
  "${PRINCIPALS_URL}?status=BANNED" "Bearer ${TEST_TOKEN}"

check "a recognised status is accepted" 200 \
  "${PRINCIPALS_URL}?status=ACTIVE" "Bearer ${TEST_TOKEN}"

# The permission gate, from the other side. CONFORMANCE_USER is a real, ACTIVE principal holding
# only the default role -- so a 403 here proves road.role.grant is what admits the caller, not
# merely having a valid token. Same fixture and same reasoning as auth-conformance's row 8.
if [[ -n "${CONFORMANCE_USER_TOKEN:-}" ]]; then
  check "a principal without road.role.grant is denied" 403 \
    "${PRINCIPALS_URL}" "Bearer ${CONFORMANCE_USER_TOKEN}"
  assert_body_contains "denial carries the FORBIDDEN error code" "${LAST_BODY}" '"error":"FORBIDDEN"'
else
  echo "[FAIL] CONFORMANCE_USER_TOKEN not set - the permission gate cannot be verified" >&2
  exit 1
fi

echo "[INFO] admin-principals.endpoint.sh complete"
