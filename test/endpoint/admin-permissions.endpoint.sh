#!/usr/bin/env bash
set -euo pipefail

# GET /api/v1/admin/permissions/, POST/DELETE /api/v1/admin/roles/:role_name/permissions/[:permission_name/]
# -- spec-patch-07's composition endpoints (planning/spec-patch-07-role-composition.md section 7).
#
# The PL/SQL suite already covers the refusal logic, idempotency and the composition guard
# assertions against the package directly. What only an HTTP test can prove is the layer between:
# that the handlers establish session context, that role_name/permission_name bind correctly from
# path and body, and -- the point of spec section 5.5 -- that ORA-08601 never has a live path to
# reach the caller as a 500 rather than the intended 403.

# ADAPTED FROM road-cal, and deliberately NOT byte-identical to it (build-plan-08 section 7 Q2,
# decided 2026-08-19: the endpoint test files stay per-repo). road-cal's fixture names events.purge
# and calendar_admin; road-kit's names todo.purge and todo_admin, from the demo application. The
# assertions are the same assertions -- what differs is which application supplies the reserved
# permission that does not start with road., which is the whole point of spec patch 08.

source bin/assert-http.sh

PERMISSIONS_URL="${ORDS_BASE_URL}/admin/permissions/"
ROLES_URL="${ORDS_BASE_URL}/admin/roles"

get_with() {
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

post_with() {
  local url="$1" data="$2" auth="${3-}"
  local body_file status
  body_file="$(mktemp)"
  if [[ -n "${auth}" ]]; then
    status="$(curl -s -o "${body_file}" -w '%{http_code}' -X POST "${url}" \
      -H "Authorization: ${auth}" -H "Content-Type: application/json" -d "${data}")"
  else
    status="$(curl -s -o "${body_file}" -w '%{http_code}' -X POST "${url}" \
      -H "Content-Type: application/json" -d "${data}")"
  fi
  printf '%s|%s' "${status}" "$(cat "${body_file}")"
  rm -f "${body_file}"
}

delete_with() {
  local url="$1" auth="${2-}"
  local body_file status
  body_file="$(mktemp)"
  if [[ -n "${auth}" ]]; then
    status="$(curl -s -o "${body_file}" -w '%{http_code}' -X DELETE "${url}" -H "Authorization: ${auth}")"
  else
    status="$(curl -s -o "${body_file}" -w '%{http_code}' -X DELETE "${url}")"
  fi
  printf '%s|%s' "${status}" "$(cat "${body_file}")"
  rm -f "${body_file}"
}

check_get() {
  local description="$1" expected="$2" url="$3" auth="${4-}"
  local result status body
  result="$(get_with "${url}" "${auth}")"
  status="${result%%|*}"; body="${result#*|}"
  assert_http "${description}" "${expected}" "${status}" "${body}"
  LAST_BODY="${body}"
}

check_post() {
  local description="$1" expected="$2" url="$3" data="$4" auth="${5-}"
  local result status body
  result="$(post_with "${url}" "${data}" "${auth}")"
  status="${result%%|*}"; body="${result#*|}"
  assert_http "${description}" "${expected}" "${status}" "${body}"
  LAST_BODY="${body}"
}

check_delete() {
  local description="$1" expected="$2" url="$3" auth="${4-}"
  local result status body
  result="$(delete_with "${url}" "${auth}")"
  status="${result%%|*}"; body="${result#*|}"
  assert_http "${description}" "${expected}" "${status}" "${body}"
  LAST_BODY="${body}"
}

echo "[INFO] admin-permissions: GET /admin/permissions/, POST/DELETE /admin/roles/:role_name/permissions/"

# --- GET /admin/permissions/ ---

check_get "GET /admin/permissions/ without token returns 401" 401 "${PERMISSIONS_URL}"

check_get "GET /admin/permissions/ with an admin token returns 200" 200 \
  "${PERMISSIONS_URL}" "Bearer ${TEST_TOKEN}"
assert_body_contains "catalogue carries permissions" "${LAST_BODY}" '"permissions"'
# todo.purge is seeded reserved (spec-patch-07 section 3.1) and does not start with road. --
# pinning that the catalogue reports the flag rather than a name-derived guess.
assert_body_contains "todo.purge is reported reserved" "${LAST_BODY}" '"permission_name":"todo.purge","description"'
assert_body_contains "the reserved flag is Y" "${LAST_BODY}" '"is_reserved":"Y"'
assert_body_contains "todo_admin is listed as a todo.purge holder" "${LAST_BODY}" '"todo_admin"'

if [[ -n "${CONFORMANCE_USER_TOKEN:-}" ]]; then
  check_get "a principal without road.role.compose is denied the catalogue" 403 \
    "${PERMISSIONS_URL}" "Bearer ${CONFORMANCE_USER_TOKEN}"
  assert_body_contains "denial carries the FORBIDDEN error code" "${LAST_BODY}" '"error":"FORBIDDEN"'
else
  echo "[FAIL] CONFORMANCE_USER_TOKEN not set - the permission gate cannot be verified" >&2
  exit 1
fi

# --- POST /admin/roles/:role_name/permissions/ and DELETE .../:permission_name/ ---
#
# todo_admin/todo.get: an unreserved role paired with an unreserved permission it does not already
# hold -- todo_admin holds only todo.list_all and todo.purge -- so the round trip below both proves
# the mutators work AND leaves the seed exactly as it found it. There is no delete-role endpoint
# (spec-patch-07 section 9), so reusing real seed data rather than defining a throwaway role is
# what keeps this test self-cleaning.
ATTACH_URL="${ROLES_URL}/todo_admin/permissions/"
DETACH_URL="${ROLES_URL}/todo_admin/permissions/todo.get/"

check_post "POST attach without a token returns 401" 401 \
  "${ATTACH_URL}" '{"permission_name":"todo.get"}'

check_post "an admin token attaches todo.get to todo_admin" 200 \
  "${ATTACH_URL}" '{"permission_name":"todo.get"}' "Bearer ${TEST_TOKEN}"
assert_body_contains "attached is true" "${LAST_BODY}" '"attached":true'

check_post "attaching the same permission again is idempotent, not an error" 200 \
  "${ATTACH_URL}" '{"permission_name":"todo.get"}' "Bearer ${TEST_TOKEN}"
assert_body_contains "second attach is a no-op" "${LAST_BODY}" '"attached":false'

check_delete "DELETE detach without a token returns 401" 401 "${DETACH_URL}"

check_delete "an admin token detaches todo.get from todo_admin" 200 \
  "${DETACH_URL}" "Bearer ${TEST_TOKEN}"
assert_body_contains "detached is true" "${LAST_BODY}" '"detached":true'

check_delete "detaching again is idempotent, not an error" 200 \
  "${DETACH_URL}" "Bearer ${TEST_TOKEN}"
assert_body_contains "second detach is a no-op" "${LAST_BODY}" '"detached":false'

# The escalation refusal, over HTTP. todo.purge is reserved -- todo_admin already legally holds it
# (deploy-attached), which is exactly why this pair proves the guard reads the flag: a session
# attach must still be refused regardless of what a deploy already granted.
check_post "attaching a reserved permission is refused with 403, not 500" 403 \
  "${ATTACH_URL}" '{"permission_name":"todo.purge"}' "Bearer ${TEST_TOKEN}"
assert_body_contains "reserved-permission denial carries FORBIDDEN" "${LAST_BODY}" '"error":"FORBIDDEN"'

# The reserved-ROLE refusal, over HTTP. road.user_admin does not hold todo.get, so a 200 here would
# mean a real (if harmless) row was written -- the assertion below is meaningful either way.
check_post "attaching to a reserved role is refused with 403" 403 \
  "${ROLES_URL}/road.user_admin/permissions/" '{"permission_name":"todo.get"}' "Bearer ${TEST_TOKEN}"
assert_body_contains "reserved-role denial carries FORBIDDEN" "${LAST_BODY}" '"error":"FORBIDDEN"'

if [[ -n "${CONFORMANCE_USER_TOKEN:-}" ]]; then
  check_post "a principal without road.role.compose cannot attach" 403 \
    "${ATTACH_URL}" '{"permission_name":"todo.get"}' "Bearer ${CONFORMANCE_USER_TOKEN}"
  check_delete "a principal without road.role.compose cannot detach" 403 \
    "${DETACH_URL}" "Bearer ${CONFORMANCE_USER_TOKEN}"
else
  echo "[FAIL] CONFORMANCE_USER_TOKEN not set - the permission gate cannot be verified" >&2
  exit 1
fi

echo "[INFO] admin-permissions.endpoint.sh complete"
