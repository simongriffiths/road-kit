#!/usr/bin/env bash
set -euo pipefail

# The authentication-spec-v1.md section 12 required-test table, made executable.
#
# That table has existed as prose since the spec was written and has never been run. Spec patch 06
# is explicit that this is how the gap survived: "Conformance rules written as prose in a spec are
# decorative; the same rules as a runnable suite are a forcing function." Every assertion below
# names the row it implements, so a reader can check the spec against the suite line by line.
#
# The negative cases use bin/get-test-token.sh's claim overrides. They cannot be produced by editing
# a good token, because any edit invalidates the signature -- the request would then be rejected for
# a bad signature and the test would silently stop covering the claim it names.

source bin/assert-http.sh

PROTECTED_URL="${ORDS_BASE_URL}/session/me/"
ADMIN_URL="${ORDS_BASE_URL}/admin/roles/"

status_of() {
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
  result="$(status_of "${url}" "${auth}")"
  status="${result%%|*}"
  body="${result#*|}"
  assert_http "${description}" "${expected}" "${status}" "${body}"
}

echo "[INFO] auth-conformance: authentication-spec-v1.md section 12"

# Row 1: Protected endpoint without token -> 401
check "s12: protected endpoint without token" 401 "${PROTECTED_URL}"

# Row 2/3: Login happy path and protected endpoint with a valid token -> 200
# (TEST_TOKEN is minted through the login endpoint by bin/run-endpoint-tests.sh, so a 200 here
#  exercises both rows: the token could not exist if login had failed.)
check "s12: protected endpoint with valid token" 200 "${PROTECTED_URL}" "Bearer ${TEST_TOKEN}"

# Row 4: Invalid token -> 401. Two shapes, because they fail at different layers: a structurally
# broken string, and a well-formed token whose signature does not verify.
check "s12: malformed token" 401 "${PROTECTED_URL}" "Bearer not-a-jwt"

TAMPERED="${TEST_TOKEN%.*}.AAAAinvalidsignatureAAAA"
check "s12: valid structure, bad signature" 401 "${PROTECTED_URL}" "Bearer ${TAMPERED}"

# Row 5: Expired token -> 401. Correctly signed by this app's key, simply past its exp.
EXPIRED_TOKEN="$("${PROJECT_ROOT:-.}/bin/get-test-token.sh" --env "${ROAD_ENV_NAME}" --ttl -10)"
if [[ -z "${EXPIRED_TOKEN}" ]]; then
  echo "[FAIL] Could not mint an expired token" >&2
  exit 1
fi
check "s12: expired token" 401 "${PROTECTED_URL}" "Bearer ${EXPIRED_TOKEN}"

# Row 6: Wrong issuer or audience -> 401. Both signed with the right key, so only the claim differs.
WRONG_ISSUER_TOKEN="$("${PROJECT_ROOT:-.}/bin/get-test-token.sh" --env "${ROAD_ENV_NAME}" --issuer 'urn:road:not-this-app')"
check "s12: wrong issuer" 401 "${PROTECTED_URL}" "Bearer ${WRONG_ISSUER_TOKEN}"

WRONG_AUDIENCE_TOKEN="$("${PROJECT_ROOT:-.}/bin/get-test-token.sh" --env "${ROAD_ENV_NAME}" --audience 'not-this-audience')"
check "s12: wrong audience" 401 "${PROTECTED_URL}" "Bearer ${WRONG_AUDIENCE_TOKEN}"

# Row 7: Missing required scope -> 401 in the v1 ORDS-first profile.
check "s12: missing required scope" 401 "${PROTECTED_URL}" "Bearer ${WRONG_SCOPE_TOKEN}"

# Row 8 (added by spec patch 06 section 6.4): an AUTHENTICATED principal lacking a required
# permission -> 403. This is the row that distinguishes the two failure modes. Everything above is
# ORDS rejecting the caller before any PL/SQL runs; here the token is valid, the scope is present,
# ORDS has admitted the request, and the application denies it.
#
# CONFORMANCE_USER is a principal that exists and is ACTIVE but holds no administrative permission.
if [[ -n "${CONFORMANCE_USER_TOKEN:-}" ]]; then
  RESULT="$(status_of "${ADMIN_URL}" "Bearer ${CONFORMANCE_USER_TOKEN}")"
  STATUS="${RESULT%%|*}"
  BODY="${RESULT#*|}"
  assert_http "s12: authenticated principal without permission" 403 "${STATUS}" "${BODY}"
  assert_body_contains "s12: 403 carries the FORBIDDEN error code" "${BODY}" '"error":"FORBIDDEN"'
  assert_body_contains "s12: 403 names the missing permission" "${BODY}" 'Permission required:'

  # And the same principal must NOT be 401 on a route it is entitled to -- otherwise the 403 above
  # could be masking a broken session rather than a genuine denial.
  check "s12: same principal is admitted where entitled" 200 "${PROTECTED_URL}" "Bearer ${CONFORMANCE_USER_TOKEN}"
else
  echo "[FAIL] CONFORMANCE_USER_TOKEN not set - the 403 row cannot be verified" >&2
  exit 1
fi

echo "[INFO] auth-conformance.endpoint.sh complete"
