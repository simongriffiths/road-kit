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
