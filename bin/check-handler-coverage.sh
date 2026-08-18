#!/usr/bin/env bash
set -euo pipefail

# Static check: every ORDS handler on a protected module must establish session context.
#
# This exists because the pre-hook is opt-in. ORDS exposes no schema-callable pre-dispatch
# registration API, so road_ctx_pkg.begin_request is called at the top of each handler by hand -- and
# a handler that omits it runs on whatever the pooled connection was last left holding
# (spec-patch-06 section 6.3). Reviewer discipline is not a mitigation; this is.
#
# Crude by design. It compares two counts per module file rather than parsing PL/SQL, and the build
# plan is explicit that crude is enough: the equivalent check would have caught the Quorate bug where
# 13_public_endpoints.sql has three handlers, zero pre-hook calls, and queries VPD-protected tables.
#
# Fails closed: a module that is not on the public allowlist must be covered. A new module added
# later is therefore required to be covered unless somebody deliberately exempts it here.

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODULES_DIR="${PROJECT_ROOT}/api/modules"

# Modules that are legitimately unauthenticated. Each needs a reason, because an entry here is the
# one way a handler escapes the check.
#   health -- liveness probe, must answer before anyone can log in
#   auth   -- the login and JWKS endpoints themselves; requiring a session to get a session is circular
#   ui     -- static SPA assets, protected by nothing because the bundle is public anyway
PUBLIC_MODULES=("health" "auth" "ui")

usage() {
  cat >&2 <<'EOF'
Usage: bin/check-handler-coverage.sh [--quiet]

Exits 0 when every handler on a protected module calls road_ctx_pkg.begin_request,
1 when any handler is uncovered, and 2 on a usage or environment error.
EOF
}

QUIET="no"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --quiet) QUIET="yes"; shift ;;
    *) usage; exit 2 ;;
  esac
done

if [[ ! -d "${MODULES_DIR}" ]]; then
  echo "[ERROR] Module directory not found: ${MODULES_DIR}" >&2
  exit 2
fi

is_public() {
  local name="$1" p
  for p in "${PUBLIC_MODULES[@]}"; do
    [[ "${name}" = "${p}" ]] && return 0
  done
  return 1
}

TOTAL_HANDLERS=0
TOTAL_COVERED=0
TOTAL_EXEMPT=0
GAPS=0

[[ "${QUIET}" = "yes" ]] || echo "[INFO] Checking handler coverage in ${MODULES_DIR}"

for module_file in "${MODULES_DIR}"/*/module.create.sql; do
  [[ -e "${module_file}" ]] || continue
  module_name="$(basename "$(dirname "${module_file}")")"

  handlers="$(grep -c 'ords\.define_handler' "${module_file}" || true)"
  established="$(grep -c 'road_ctx_pkg\.begin_request' "${module_file}" || true)"

  if is_public "${module_name}"; then
    TOTAL_EXEMPT=$(( TOTAL_EXEMPT + handlers ))
    [[ "${QUIET}" = "yes" ]] || \
      printf '[INFO] %-10s %2s handler(s)  PUBLIC (allowlisted)\n' "${module_name}" "${handlers}"
    continue
  fi

  TOTAL_HANDLERS=$(( TOTAL_HANDLERS + handlers ))
  TOTAL_COVERED=$(( TOTAL_COVERED + established ))

  if [[ "${established}" -lt "${handlers}" ]]; then
    missing=$(( handlers - established ))
    GAPS=$(( GAPS + missing ))
    echo "[FAIL] ${module_name}: ${handlers} handler(s), ${established} begin_request call(s) - ${missing} uncovered" >&2
  else
    [[ "${QUIET}" = "yes" ]] || \
      printf '[PASS] %-10s %2s handler(s)  %2s begin_request\n' \
        "${module_name}" "${handlers}" "${established}"
  fi
done

echo "[INFO] Protected handlers: ${TOTAL_HANDLERS}, covered: ${TOTAL_COVERED}, public exempt: ${TOTAL_EXEMPT}"

if [[ "${GAPS}" -gt 0 ]]; then
  echo "[FAIL] ${GAPS} handler(s) on protected modules do not establish session context" >&2
  echo "[FAIL] Each must call: if not road_ctx_pkg.begin_request(:current_user) then ... 401 ... end if;" >&2
  exit 1
fi

echo "[PASS] Every handler on a protected module establishes session context"
