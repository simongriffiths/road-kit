#!/usr/bin/env bash
set -euo pipefail

# Configure tool locations relative to the project root.
SQLCL_BIN="${SQLCL_BIN:-sql}"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Print the accepted command-line contract.
usage() {
  cat >&2 <<'EOF'
Usage: bin/run-sql.sh --env <dev|test|prod> --script <file.sql> [--log-level normal|debug]
EOF
}

ENV_NAME=""
SCRIPT_ARG=""
LOG_LEVEL="normal"

# Parse required environment and script arguments.
while [[ $# -gt 0 ]]; do
  case "$1" in
    --env)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      ENV_NAME="$2"
      shift 2
      ;;
    --script)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      SCRIPT_ARG="$2"
      shift 2
      ;;
    --log-level)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      LOG_LEVEL="$2"
      shift 2
      ;;
    *)
      usage
      exit 2
      ;;
  esac
done

# Reject incomplete or invalid invocation parameters early.
if [[ -z "${ENV_NAME}" || -z "${SCRIPT_ARG}" ]]; then
  usage
  exit 2
fi

if [[ "${LOG_LEVEL}" != "normal" && "${LOG_LEVEL}" != "debug" ]]; then
  echo "[ERROR] Invalid log level: ${LOG_LEVEL}" >&2
  usage
  exit 2
fi

# Map the logical environment to its saved SQLcl connection.
case "${ENV_NAME}" in
  dev)
    CONNECTION="app_dev"
    ;;
  test)
    CONNECTION="app_test"
    ;;
  prod)
    CONNECTION="app_prod"
    ;;
  *)
    echo "[ERROR] Unknown environment: ${ENV_NAME}" >&2
    usage
    exit 2
    ;;
esac

# Resolve the script path so callers can use absolute or project-relative paths.
if [[ "${SCRIPT_ARG}" = /* ]]; then
  SCRIPT_PATH="${SCRIPT_ARG}"
else
  SCRIPT_PATH="${PROJECT_ROOT}/${SCRIPT_ARG}"
fi

# Fail before execution if the target script or SQLcl binary is missing.
if [[ ! -f "${SCRIPT_PATH}" ]]; then
  echo "[ERROR] SQL script not found: ${SCRIPT_ARG}" >&2
  exit 2
fi

if ! command -v "${SQLCL_BIN}" >/dev/null 2>&1; then
  echo "[ERROR] SQLcl binary not found on PATH: ${SQLCL_BIN}" >&2
  exit 127
fi

# Build a collision-free log file name using the resolved script name.
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
SCRIPT_NAME="$(basename "${SCRIPT_PATH}")"
SCRIPT_STEM="${SCRIPT_NAME%.sql}"
LOG_DIR="${PROJECT_ROOT}/logs/${ENV_NAME}/runs"
LOG_FILE="${LOG_DIR}/${TIMESTAMP}_${SCRIPT_STEM}_$$.log"

if ! mkdir -p "${LOG_DIR}"; then
  echo "[ERROR] Failed to create log directory: ${LOG_DIR}" >&2
  exit 2
fi

# In debug mode mirror SQLcl output to the console; otherwise log only.
if [[ "${LOG_LEVEL}" = "debug" ]]; then
  ECHO_SETTING="set echo on"
  TEE_STDOUT="/dev/fd/1"
else
  ECHO_SETTING="set echo off"
  TEE_STDOUT="/dev/null"
fi

# Write a stable log header before invoking SQLcl.
cat >"${LOG_FILE}" <<EOF
[INFO] START
[INFO] ENV=${ENV_NAME}
[INFO] CONNECTION=${CONNECTION}
[INFO] SCRIPT=${SCRIPT_ARG}
[INFO] LOG_LEVEL=${LOG_LEVEL}
[INFO] TIMESTAMP=${TIMESTAMP}
EOF

echo "[INFO] START"
echo "[INFO] ENV=${ENV_NAME}"
echo "[INFO] CONNECTION=${CONNECTION}"
echo "[INFO] SCRIPT=${SCRIPT_ARG}"
echo "[INFO] LOG_FILE=${LOG_FILE}"
echo "[INFO] LOG_LEVEL=${LOG_LEVEL}"

# Run the target script inside a controlled SQLcl session and capture all output.
"${SQLCL_BIN}" -name "${CONNECTION}" 2>&1 <<EOF | tee -a "${LOG_FILE}" >"${TEE_STDOUT}"
whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback
set feedback on
set timing on
set serveroutput on size unlimited
set define off
set sqlblanklines on
${ECHO_SETTING}
@${SCRIPT_PATH}
exit success
EOF
SQLCL_EXIT=$?

# Treat known SQLcl connection failures as hard failures even if SQLcl returns zero.
if [[ "${SQLCL_EXIT}" -eq 0 ]] && grep -Eq '(^SP2-|^Unknown connection\b)' "${LOG_FILE}"; then
  SQLCL_EXIT=1
fi

# Append the final execution status to the log and console summary.
cat >>"${LOG_FILE}" <<EOF
[INFO] SQLCL_EXIT=${SQLCL_EXIT}
[INFO] END
EOF

if [[ "${SQLCL_EXIT}" -eq 0 ]]; then
  echo "[INFO] SUCCESS"
else
  echo "[ERROR] FAILURE"
fi
echo "[INFO] SQLCL_EXIT=${SQLCL_EXIT}"

exit "${SQLCL_EXIT}"
