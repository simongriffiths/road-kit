#!/usr/bin/env bash
set -euo pipefail

# The demo application over HTTP (planning/spec-patch-08-road-kit-demo-app.md section 6, in
# road-cal). Per-repo by design -- there is no road-cal counterpart to keep in step.
#
# The PL/SQL suite (demo_todo_api_test) already covers ownership isolation, the read_token
# staleness path and the status rules against the package directly. What only an HTTP test can
# prove is the layer between: that every handler establishes session context, that path and query
# parameters bind correctly, and that the permission model holds end to end for a real token.
#
# Three assertions here carry the patch:
#   1. road.system_admin composes NO application permission. Rule 2 of spec patch 06, verified
#      over the wire through the permission catalogue rather than assumed. Everyone expects the
#      opposite.
#   2. Nobody can purge. todo.purge is reserved and seeded only onto todo_admin, which no test
#      principal holds, so "the permission nobody holds by default" is a fact this suite checks
#      rather than a claim the spec makes.
#   3. A stale read_token comes back 409, not 200.

source bin/assert-http.sh

TODOS_URL="${ORDS_BASE_URL}/todos/"
PURGE_URL="${ORDS_BASE_URL}/todos/purge/"

if [[ -z "${CONFORMANCE_USER_TOKEN:-}" ]]; then
  echo "[FAIL] CONFORMANCE_USER_TOKEN not set - the demo application cannot be verified" >&2
  exit 1
fi
USER_AUTH="Bearer ${CONFORMANCE_USER_TOKEN}"
ADMIN_AUTH="Bearer ${TEST_TOKEN}"

req() {
  local method="$1" url="$2" auth="$3" data="${4-}"
  local body_file status
  body_file="$(mktemp)"
  if [[ -n "${data}" ]]; then
    status="$(curl -s -o "${body_file}" -w '%{http_code}' -X "${method}" "${url}" \
      -H "Authorization: ${auth}" -H "Content-Type: application/json" -d "${data}")"
  elif [[ -n "${auth}" ]]; then
    status="$(curl -s -o "${body_file}" -w '%{http_code}' -X "${method}" "${url}" \
      -H "Authorization: ${auth}")"
  else
    status="$(curl -s -o "${body_file}" -w '%{http_code}' -X "${method}" "${url}")"
  fi
  printf '%s|%s' "${status}" "$(cat "${body_file}")"
  rm -f "${body_file}"
}

check() {
  local description="$1" expected="$2" method="$3" url="$4" auth="$5" data="${6-}"
  local result status body
  result="$(req "${method}" "${url}" "${auth}" "${data}")"
  status="${result%%|*}"; body="${result#*|}"
  assert_http "${description}" "${expected}" "${status}" "${body}"
  LAST_BODY="${body}"
}

json_field() {
  # Minimal extractor -- no jq dependency, matching the rest of this suite.
  printf '%s' "$1" | sed -n "s/.*\"$2\":\"\([^\"]*\)\".*/\1/p" | head -1
}
json_num() {
  printf '%s' "$1" | sed -n "s/.*\"$2\":\([0-9]*\).*/\1/p" | head -1
}

echo "[INFO] todos: the demo application (spec patch 08)"

# --- authentication ---

check "GET /todos/ without a token returns 401" 401 GET "${TODOS_URL}" ""
check "POST /todos/ without a token returns 401" 401 POST "${TODOS_URL}" "" '{"title":"x"}'

# --- rule 2: the system administrator role is not a user role ---
#
# Asserted against the ROLE, through the permission catalogue, not by expecting a 403 from the
# admin token.
#
# An earlier draft did the latter -- "road.system_admin cannot list todos", expecting 403 -- and it
# failed with a 200. Not a model defect: road.system_admin composes no todo.* permission, exactly
# as rule 2 requires. The bootstrap ADMIN principal simply holds the `user` role AS WELL, so it
# reaches todos through that. A principal-level assertion tests which roles a fixture happens to
# hold; a role-level one tests the invariant. Only the second is worth having.

check "the permission catalogue is readable by the admin" 200 GET \
  "${ORDS_BASE_URL}/admin/permissions/" "${ADMIN_AUTH}"
# json_arrayagg orders role holders alphabetically, so a todo.* permission held by
# road.system_admin would appear as that role name inside the same object. Assert the absence.
if printf '%s' "${LAST_BODY}" | grep -q '"permission_name":"todo\.[a-z_]*"[^}]*road\.system_admin'; then
  echo "[FAIL] road.system_admin composes a todo.* permission - spec patch 06 rule 2 is broken" >&2
  exit 1
fi
echo "[TEST] road.system_admin composes no application permission"
echo "[PASS] rule 2 holds in the permission catalogue"

# --- the ordinary user path ---

check "an ordinary user creates a todo" 201 POST "${TODOS_URL}" "${USER_AUTH}" \
  '{"title":"endpoint fixture","notes":"created by todos.endpoint.sh"}'
assert_body_contains "the created todo carries a status" "${LAST_BODY}" '"status":"OPEN"'
TODO_ID="$(json_num "${LAST_BODY}" todo_id)"
if [[ -z "${TODO_ID}" ]]; then
  echo "[FAIL] could not read todo_id from the create response" >&2
  exit 1
fi
echo "[INFO] fixture todo_id=${TODO_ID}"

# Ownership comes from the session. A body that nominates someone else is refused outright, not
# quietly ignored -- a caller probing for the hole should be told no.
check "supplying owner_principal_id is a 400, not a silent ignore" 400 POST "${TODOS_URL}" \
  "${USER_AUTH}" '{"title":"forged","owner_principal_id":1}'
assert_body_contains "refusal carries VALIDATION_ERROR" "${LAST_BODY}" '"error":"VALIDATION_ERROR"'

check "the user lists their own todos" 200 GET "${TODOS_URL}" "${USER_AUTH}"
assert_body_contains "the collection wrapper is present" "${LAST_BODY}" '"hasMore"'
assert_body_contains "a read_token is issued" "${LAST_BODY}" '"read_token"'

check "the user reads one todo" 200 GET "${TODOS_URL}${TODO_ID}/" "${USER_AUTH}"
assert_body_contains "the single read carries a read_token" "${LAST_BODY}" '"read_token"'
READ_TOKEN="$(json_field "${LAST_BODY}" read_token)"

# --- concurrency ---

check "a fresh read_token updates" 200 PATCH "${TODOS_URL}${TODO_ID}/" "${USER_AUTH}" \
  "{\"read_token\":\"${READ_TOKEN}\",\"title\":\"updated by endpoint test\"}"
assert_body_contains "the update landed" "${LAST_BODY}" '"title":"updated by endpoint test"'

# The same token again. The row moved when the PATCH above succeeded, so this one is stale.
check "the same read_token a second time is 409, not 200" 409 PATCH "${TODOS_URL}${TODO_ID}/" \
  "${USER_AUTH}" "{\"read_token\":\"${READ_TOKEN}\",\"title\":\"should not land\"}"
assert_body_contains "staleness carries CONFLICT" "${LAST_BODY}" '"error":"CONFLICT"'
# The wording is fixed and must read as a request to re-evaluate, never as an instruction to retry
# (spec-patch-02-mcp.md section 5). An agent told to retry will retry, and the second write is the
# one that destroys the change it could not see.
assert_body_contains "the conflict message asks the caller to re-evaluate" "${LAST_BODY}" \
  'decide whether the change is still appropriate'

check "an update with no read_token is 400" 400 PATCH "${TODOS_URL}${TODO_ID}/" "${USER_AUTH}" \
  '{"title":"no token"}'

check "another principal's todo is 404, not 403" 404 GET "${TODOS_URL}999999999/" "${USER_AUTH}"
assert_body_contains "the miss carries NOT_FOUND" "${LAST_BODY}" '"error":"NOT_FOUND"'

# --- status rules ---

check "reading back for a fresh token" 200 GET "${TODOS_URL}${TODO_ID}/" "${USER_AUTH}"
READ_TOKEN="$(json_field "${LAST_BODY}" read_token)"

check "PATCH cannot set DELETED" 400 PATCH "${TODOS_URL}${TODO_ID}/" "${USER_AUTH}" \
  "{\"read_token\":\"${READ_TOKEN}\",\"status\":\"DELETED\"}"

check "PATCH can set DONE" 200 PATCH "${TODOS_URL}${TODO_ID}/" "${USER_AUTH}" \
  "{\"read_token\":\"${READ_TOKEN}\",\"status\":\"DONE\"}"
assert_body_contains "status is DONE" "${LAST_BODY}" '"status":"DONE"'

# --- the reserved permission nobody holds ---
#
# todo.purge is seeded onto todo_admin alone, and no test principal holds that role. Both tokens
# are therefore refused. This is what "the permission nobody holds by default" means in practice,
# and it is the reason the demo application exists at all.

check "an ordinary user cannot purge" 403 POST "${PURGE_URL}" "${USER_AUTH}" \
  '{"before":"2999-01-01T00:00:00.000+00:00"}'
assert_body_contains "purge denial carries FORBIDDEN" "${LAST_BODY}" '"error":"FORBIDDEN"'

check "not even road.system_admin can purge" 403 POST "${PURGE_URL}" "${ADMIN_AUTH}" \
  '{"before":"2999-01-01T00:00:00.000+00:00"}'
assert_body_contains "purge denial carries FORBIDDEN for the admin too" "${LAST_BODY}" \
  '"error":"FORBIDDEN"'

# --- cleanup: soft delete the fixture ---

check "reading back for a delete token" 200 GET "${TODOS_URL}${TODO_ID}/" "${USER_AUTH}"
READ_TOKEN="$(json_field "${LAST_BODY}" read_token)"

check "the user deletes their todo" 200 DELETE \
  "${TODOS_URL}${TODO_ID}/?read_token=${READ_TOKEN}" "${USER_AUTH}"
assert_body_contains "deleted is true" "${LAST_BODY}" '"deleted":true'

echo "[INFO] todos.endpoint.sh complete"
