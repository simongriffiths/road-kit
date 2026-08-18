#!/usr/bin/env bash
set -euo pipefail

# Verifies the auth scaffold's configuration BEFORE anything that depends on a working token.
#
# ORDS fetches the JWKS document over the network to get the public key that verifies token
# signatures. If jwk_url points somewhere that does not serve this app's JWKS, every protected
# endpoint returns a generic 401 that is indistinguishable from a bad token. This ran red for
# days in an app built from this template: the only signal was that 401, ten steps removed
# from the cause.
#
# CONFIGURED_JWK_URL is read from JWT_SCAFFOLD_CONFIG by bin/run-endpoint-tests.sh - it is the
# value ORDS will actually use. Do NOT rebuild this URL from ROAD_ORDS_HOST: that reconstructs
# the conventional path and compares it to itself, which passes against a live misconfiguration.
# (Tried during development; it passed while the config pointed at a dead host.)
#
# See planning/spec-patch-04-auth-config-derivation.md section 5.2.

source bin/assert-http.sh

JWKS_URL="${CONFIGURED_JWK_URL}"

echo "[TEST] Configured jwk_url points at the host under test"
case "${JWKS_URL}" in
  "${AUTH_BASE_URL}"/*)
    echo "[PASS] jwk_url is on ${AUTH_BASE_URL}"
    ;;
  *)
    echo "[FAIL] Configured jwk_url is on a different host than the app under test" >&2
    echo "[FAIL]   configured: ${JWKS_URL}" >&2
    echo "[FAIL]   app under test: ${AUTH_BASE_URL}" >&2
    echo "[FAIL] Re-run bin/render-auth-config.sh --env <env> and redeploy 80_standalone.generated.sql" >&2
    exit 1
    ;;
esac

JWKS_RESPONSE_FILE="$(mktemp)"
JWKS_STATUS="$(curl -s -w "%{http_code}" -o "${JWKS_RESPONSE_FILE}" "${JWKS_URL}")"
JWKS_BODY="$(cat "${JWKS_RESPONSE_FILE}")"
rm "${JWKS_RESPONSE_FILE}"

assert_http "JWKS document is reachable at the configured jwk_url" 200 "${JWKS_STATUS}" "${JWKS_BODY}"
assert_body_contains "JWKS document carries a keys array" "${JWKS_BODY}" "\"keys\""

# The signing key must be the published key. A JWKS that resolves but advertises a different kid
# fails validation just as completely as one that 404s - and is even harder to spot by eye.
TOKEN_KID="$(python3 - "${TEST_TOKEN}" <<'PY'
import base64, json, sys

header_segment = sys.argv[1].split('.')[0]
padded = header_segment + '=' * (-len(header_segment) % 4)
print(json.loads(base64.urlsafe_b64decode(padded)).get('kid', ''))
PY
)"

if [ -z "${TOKEN_KID}" ]; then
  echo "[FAIL] Minted token carries no kid in its JWT header" >&2
  exit 1
fi

echo "[TEST] Minted token's kid is published in the JWKS document"
if printf '%s' "${JWKS_BODY}" | grep -q "\"kid\":\"${TOKEN_KID}\""; then
  echo "[PASS] kid ${TOKEN_KID} present in JWKS"
else
  echo "[FAIL] Token signed with kid ${TOKEN_KID}, not published at ${JWKS_URL}" >&2
  echo "[FAIL] JWKS: ${JWKS_BODY}" >&2
  exit 1
fi

# Guards the section 4.2 convention: issuer is a logical URN, never a hostname. If this fails
# after a host move, the issuer was wrongly bound to the deployment host.
TOKEN_ISS="$(python3 - "${TEST_TOKEN}" <<'PY'
import base64, json, sys

payload_segment = sys.argv[1].split('.')[1]
padded = payload_segment + '=' * (-len(payload_segment) % 4)
print(json.loads(base64.urlsafe_b64decode(padded)).get('iss', ''))
PY
)"

EXPECTED_ISS="urn:road:${APP_NAME}:${ROAD_ENV_NAME}"

echo "[TEST] Configured issuer matches the logical URN convention"
if [ "${CONFIGURED_ISSUER}" = "${EXPECTED_ISS}" ]; then
  echo "[PASS] configured issuer is ${CONFIGURED_ISSUER}"
else
  echo "[FAIL] Expected configured issuer ${EXPECTED_ISS}, got ${CONFIGURED_ISSUER}" >&2
  exit 1
fi

echo "[TEST] Token issuer is the logical URN for this app and environment"
if [ "${TOKEN_ISS}" = "${EXPECTED_ISS}" ]; then
  echo "[PASS] iss is ${TOKEN_ISS}"
else
  echo "[FAIL] Expected iss ${EXPECTED_ISS}, got ${TOKEN_ISS}" >&2
  exit 1
fi

echo "[INFO] auth-config.endpoint.sh complete"
