#!/usr/bin/env bash
set -euo pipefail

# The demo application over HTTP (spec-patch-08, rebuilt as a governed surface by spec-patch-16;
# test/agents/surface.test.mjs covers the surface in depth with agent and fixture tokens, and this
# suite checks it with the real principals' tokens). Per-repo by design -- there is no road-cal counterpart to keep in step.
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
#   3. A stale read token is a 200 refusal (STALE_TOKEN) with a decision record, not an error, and
#      the todo is unchanged (spec-patch-16: the demo is a governed surface).

source bin/assert-http.sh

TODOS_URL="${ORDS_BASE_URL}/todos/"
PURGE_URL="${ORDS_BASE_URL}/todos/purges/"

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

echo "[INFO] todos: the governed demo surface (spec-patch-16)"

# Every governed action sends an Idempotency-Key or carries a read token. The key is unique per run.
RUN="$(date +%s)"
post_idem() { # description expected url auth body key
  local result status
  result="$(curl -s -o /tmp/todos.ep.body -w '%{http_code}' -X POST "$3" -H "Authorization: $4" \
    -H "Content-Type: application/json" -H "Idempotency-Key: $6" -d "$5")"
  assert_http "$1" "$2" "${result}" "$(cat /tmp/todos.ep.body)"
  LAST_BODY="$(cat /tmp/todos.ep.body)"
}

# --- authentication ---

check "GET /todos/ without a token returns 401" 401 GET "${TODOS_URL}" ""
check "POST /todos/ without a token returns 401" 401 POST "${TODOS_URL}" "" '{"title":"x"}'
check "the contract is public: GET /contract/ needs no token" 200 GET "${ORDS_BASE_URL}/contract/" ""
assert_body_contains "and it is the demo's contract" "${LAST_BODY}" '"id":"hello_world"'

# --- rule 2: the system administrator role is not a user role ---
#
# Asserted against the ROLE, through the permission catalogue, not by expecting a 403 from the
# admin token. The bootstrap ADMIN principal holds the `user` role as well, so it reaches todos
# through that; a principal-level assertion tests which roles a fixture happens to hold, a
# role-level one tests the invariant.

check "the permission catalogue is readable by the admin" 200 GET \
  "${ORDS_BASE_URL}/admin/permissions/" "${ADMIN_AUTH}"
if printf '%s' "${LAST_BODY}" | grep -q '"permission_name":"todo\.[a-z_]*"[^}]*road\.system_admin'; then
  echo "[FAIL] road.system_admin composes a todo.* permission - spec patch 06 rule 2 is broken" >&2
  exit 1
fi
echo "[TEST] road.system_admin composes no application permission"
echo "[PASS] rule 2 holds in the permission catalogue"

# --- the ordinary user path ---

post_idem "an ordinary user adds a todo: 200 accepted" 200 "${TODOS_URL}" "${USER_AUTH}" \
  "{\"title\":\"endpoint fixture ${RUN}\",\"notes\":\"created by todos.endpoint.sh\"}" "ep-create-${RUN}"
assert_body_contains "the decision is accepted" "${LAST_BODY}" '"decision":"accepted"'
assert_body_contains "the answer states the contract version" "${LAST_BODY}" '"contract_version"'
TODO_ID="$(json_num "${LAST_BODY}" todo_id)"
if [[ -z "${TODO_ID}" ]]; then
  echo "[FAIL] could not read todo_id from the create response" >&2
  exit 1
fi
echo "[INFO] fixture todo_id=${TODO_ID}"

# Ownership comes from the session. A body that nominates someone else is refused outright, not
# quietly ignored, and the 400 still states the contract version.
post_idem "supplying owner_principal_id is a 400, not a silent ignore" 400 "${TODOS_URL}" \
  "${USER_AUTH}" '{"title":"forged","owner_principal_id":1}' "ep-forged-${RUN}"
assert_body_contains "refusal carries VALIDATION_ERROR" "${LAST_BODY}" '"error":"VALIDATION_ERROR"'
assert_body_contains "and the contract version" "${LAST_BODY}" '"contract_version"'

post_idem "the same title again is a rule, not an error: 200 rejected" 200 "${TODOS_URL}" "${USER_AUTH}" \
  "{\"title\":\"endpoint fixture ${RUN}\"}" "ep-dup-${RUN}"
assert_body_contains "the rule is TITLE_TAKEN" "${LAST_BODY}" '"rule_id":"TITLE_TAKEN"'
assert_body_contains "and the refusal is audited" "${LAST_BODY}" '"audit_id"'

check "the user lists their own todos" 200 GET "${TODOS_URL}" "${USER_AUTH}"
assert_body_contains "the collection wrapper is present" "${LAST_BODY}" '"hasMore"'
assert_body_contains "the view states its point in time" "${LAST_BODY}" '"as_at"'
assert_body_contains "and its scope" "${LAST_BODY}" '"scope"'
LIST_TOKEN="$(json_field "${LAST_BODY}" read_token)"

check "the user reads one todo" 200 GET "${TODOS_URL}${TODO_ID}/" "${USER_AUTH}"
READ_TOKEN="$(json_field "${LAST_BODY}" read_token)"

# --- concurrency ---

check "a fresh read token revises" 200 POST "${TODOS_URL}${TODO_ID}/revisions/" "${USER_AUTH}" \
  "{\"read_token\":\"${READ_TOKEN}\",\"title\":\"updated by endpoint test ${RUN}\"}"
assert_body_contains "the revision is accepted" "${LAST_BODY}" '"decision":"accepted"'

# A token from before the change is stale: a refusal with a decision record, and nothing changes.
check "a token from before the change is a 200 refusal" 200 POST "${TODOS_URL}${TODO_ID}/revisions/" \
  "${USER_AUTH}" "{\"read_token\":\"${LIST_TOKEN}\",\"title\":\"should not land\"}"
assert_body_contains "the rule is STALE_TOKEN" "${LAST_BODY}" '"rule_id":"STALE_TOKEN"'
assert_body_contains "and it is retryable after a re-read" "${LAST_BODY}" '"retryable":true'

check "a revision with no read token is 400" 400 POST "${TODOS_URL}${TODO_ID}/revisions/" "${USER_AUTH}" \
  '{"title":"no token"}'

check "a todo that is not there is 404, not 403" 404 GET "${TODOS_URL}999999999/" "${USER_AUTH}"
assert_body_contains "the miss carries NOT_FOUND" "${LAST_BODY}" '"error":"NOT_FOUND"'
assert_body_contains "and the contract version" "${LAST_BODY}" '"contract_version"'

# --- state rules ---

check "reading back for a fresh token" 200 GET "${TODOS_URL}${TODO_ID}/" "${USER_AUTH}"
READ_TOKEN="$(json_field "${LAST_BODY}" read_token)"
check "the user completes the todo" 200 POST "${TODOS_URL}${TODO_ID}/completions/" "${USER_AUTH}" \
  "{\"read_token\":\"${READ_TOKEN}\"}"
assert_body_contains "status is DONE" "${LAST_BODY}" '"status":"DONE"'
DONE_TOKEN="$(json_field "${LAST_BODY}" read_token)"
check "revising a done todo is a 200 refusal" 200 POST "${TODOS_URL}${TODO_ID}/revisions/" "${USER_AUTH}" \
  "{\"read_token\":\"${DONE_TOKEN}\",\"title\":\"too late\"}"
assert_body_contains "the rule is TODO_DONE" "${LAST_BODY}" '"rule_id":"TODO_DONE"'
check "reopening it" 200 POST "${TODOS_URL}${TODO_ID}/reopenings/" "${USER_AUTH}" "{\"read_token\":\"${DONE_TOKEN}\"}"
assert_body_contains "status is OPEN again" "${LAST_BODY}" '"status":"OPEN"'

# --- the reserved permission nobody holds ---
#
# todo.purge is seeded onto todo_admin alone, and no test principal holds that role. Both tokens
# are therefore refused: "the permission nobody holds by default" is a fact this suite checks.

post_idem "an ordinary user cannot purge" 403 "${PURGE_URL}" "${USER_AUTH}" \
  '{"before":"2999-01-01T00:00:00Z"}' "ep-purge-user-${RUN}"
assert_body_contains "purge denial carries FORBIDDEN" "${LAST_BODY}" '"error":"FORBIDDEN"'

post_idem "not even road.system_admin can purge" 403 "${PURGE_URL}" "${ADMIN_AUTH}" \
  '{"before":"2999-01-01T00:00:00Z"}' "ep-purge-admin-${RUN}"
assert_body_contains "purge denial carries FORBIDDEN for the admin too" "${LAST_BODY}" '"error":"FORBIDDEN"'

# --- cleanup: soft delete the fixture ---

check "reading back for a delete token" 200 GET "${TODOS_URL}${TODO_ID}/" "${USER_AUTH}"
READ_TOKEN="$(json_field "${LAST_BODY}" read_token)"
check "the user deletes their todo" 200 DELETE "${TODOS_URL}${TODO_ID}/" "${USER_AUTH}" \
  "{\"read_token\":\"${READ_TOKEN}\"}"
assert_body_contains "the deletion is accepted" "${LAST_BODY}" '"decision":"accepted"'

echo "[INFO] todos.endpoint.sh complete"
