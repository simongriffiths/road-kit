#!/usr/bin/env bash
set -euo pipefail

assert_http() {
  local description="$1"
  local expected="$2"
  local actual="$3"
  local body="$4"

  echo "[TEST] ${description}"
  if [ "${actual}" -eq "${expected}" ]; then
    echo "[PASS] HTTP ${actual}"
  else
    echo "[FAIL] Expected HTTP ${expected}, got HTTP ${actual}" >&2
    echo "[FAIL] Response: ${body}" >&2
    exit 1
  fi
}

assert_body_contains() {
  local description="$1"
  local body="$2"
  local expected_fragment="$3"

  echo "[TEST] ${description}"
  if [[ "${body}" == *"${expected_fragment}"* ]]; then
    echo "[PASS] Body contains expected fragment"
  else
    echo "[FAIL] Response body did not contain expected fragment" >&2
    echo "[FAIL] Expected fragment: ${expected_fragment}" >&2
    echo "[FAIL] Response: ${body}" >&2
    exit 1
  fi
}
