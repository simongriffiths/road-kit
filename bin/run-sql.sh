#!/usr/bin/env bash
set -euo pipefail

# Configure tool locations relative to the project root.
SQLCL_BIN="${SQLCL_BIN:-sql}"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DB_HISTORY_COMMON="${PROJECT_ROOT}/bin/db-history-common.sh"
SQL_RUNNER_CONFIG="${SQL_RUNNER_CONFIG:-${PROJECT_ROOT}/config/connections.conf}"

if [[ -f "${DB_HISTORY_COMMON}" ]]; then
  # shellcheck source=bin/db-history-common.sh
  source "${DB_HISTORY_COMMON}"
fi

# Print the accepted command-line contract.
usage() {
  cat >&2 <<'EOF'
Usage: bin/run-sql.sh --env <name> --script <file.sql> [--log-level normal|debug]

Connection names are loaded from config/connections.conf by default.
Override with SQL_RUNNER_CONFIG=/path/to/connections.conf.
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

load_connection() {
  local env_name="$1"
  local config_file="$2"

  if [[ ! -f "${config_file}" ]]; then
    return 3
  fi

  awk -F= -v env_name="${env_name}" '
    /^[[:space:]]*($|#)/ {
      next
    }
    {
      key = $1
      value = substr($0, index($0, "=") + 1)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", key)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      if (key == env_name) {
        print value
        found = 1
        exit
      }
    }
    END {
      if (!found) {
        exit 1
      }
    }
  ' "${config_file}"
}

set +e
CONNECTION="$(load_connection "${ENV_NAME}" "${SQL_RUNNER_CONFIG}")"
LOAD_CONNECTION_EXIT=$?
set -e

if [[ "${LOAD_CONNECTION_EXIT}" -ne 0 ]]; then
  if [[ "${LOAD_CONNECTION_EXIT}" -eq 3 ]]; then
    echo "[ERROR] SQL runner config not found: ${SQL_RUNNER_CONFIG}" >&2
    echo "[ERROR] Copy config/connections.conf.example to config/connections.conf and edit it" >&2
  else
    echo "[ERROR] Unknown environment: ${ENV_NAME}" >&2
    echo "[ERROR] Add '${ENV_NAME}=<sqlcl-saved-connection>' to ${SQL_RUNNER_CONFIG}" >&2
  fi
  usage
  exit 2
fi

if [[ -z "${CONNECTION}" ]]; then
  echo "[ERROR] Empty SQLcl connection for environment: ${ENV_NAME}" >&2
  exit 2
fi

if [[ "${ENV_NAME}" = "prod" && "${ALLOW_PROD_SQL:-}" != "yes" ]]; then
  echo "[ERROR] Production SQL execution requires ALLOW_PROD_SQL=yes" >&2
  exit 2
fi

# Resolve the script path so callers can use absolute or project-relative paths.
if [[ "${SCRIPT_ARG}" = /* ]]; then
  SCRIPT_PATH="${SCRIPT_ARG}"
else
  SCRIPT_PATH="${PROJECT_ROOT}/${SCRIPT_ARG}"
fi

is_sql_runner_source_repo() {
  [[ -f "${PROJECT_ROOT}/skills/sql-runner/SKILL.md" ]] || return 1
  git -C "${PROJECT_ROOT}" remote get-url origin 2>/dev/null |
    grep -Eq '(^|[:/])simongriffiths/sql-runner(\.git)?$'
}

is_source_repo_example_script() {
  case "${SCRIPT_PATH}" in
    "${PROJECT_ROOT}/examples/"*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

if is_sql_runner_source_repo && ! is_source_repo_example_script && [[ "${SQL_RUNNER_ALLOW_SOURCE_REPO_RUN:-}" != "yes" ]]; then
  echo "[ERROR] Refusing to run project SQL from the sql-runner source repository" >&2
  echo "[ERROR] Install sql-runner into the target project and run that project's bin/run-sql.sh" >&2
  echo "[ERROR] Override only for intentional source-repo maintenance with SQL_RUNNER_ALLOW_SOURCE_REPO_RUN=yes" >&2
  exit 2
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

script_sha256() {
  if [[ -n "${SCRIPT_SHA256:-}" ]]; then
    printf '%s\n' "${SCRIPT_SHA256}"
  elif declare -F db_history_hash_file >/dev/null 2>&1; then
    db_history_hash_file "${SCRIPT_PATH}"
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "${SCRIPT_PATH}" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "${SCRIPT_PATH}" | awk '{print $1}'
  else
    printf 'unavailable\n'
  fi
}

extract_intent() {
  awk '
    /^[[:space:]]*--[[:space:]]*INTENT:[[:space:]]*$/ {
      inside = 1
      next
    }
    /^[[:space:]]*--[[:space:]]*END[[:space:]]+INTENT[[:space:]]*$/ {
      exit
    }
    inside {
      line = $0
      sub(/^[[:space:]]*--[[:space:]]?/, "", line)
      print line
    }
  ' "${SCRIPT_PATH}"
}

git_commit() {
  if git -C "${PROJECT_ROOT}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git -C "${PROJECT_ROOT}" rev-parse --short HEAD 2>/dev/null || printf 'unknown\n'
  else
    printf 'unknown\n'
  fi
}

git_dirty() {
  if git -C "${PROJECT_ROOT}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    if [[ -n "$(git -C "${PROJECT_ROOT}" status --porcelain 2>/dev/null)" ]]; then
      printf 'true\n'
    else
      printf 'false\n'
    fi
  else
    printf 'unknown\n'
  fi
}

# Build a collision-free log file name using the resolved script name.
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
SCRIPT_NAME="$(basename "${SCRIPT_PATH}")"
SCRIPT_STEM="${SCRIPT_NAME%.sql}"
RUN_ID="${TIMESTAMP}_${SCRIPT_STEM}_$$"
LOG_DIR="${PROJECT_ROOT}/logs/${ENV_NAME}/runs"
LOG_FILE="${LOG_DIR}/${RUN_ID}.log"
SCRIPT_SHA256="$(script_sha256)"
GIT_COMMIT="$(git_commit)"
GIT_DIRTY="$(git_dirty)"
INTENT_TEXT="$(extract_intent)"

if ! mkdir -p "${LOG_DIR}"; then
  echo "[ERROR] Failed to create log directory: ${LOG_DIR}" >&2
  exit 2
fi

# In debug mode mirror SQLcl output to the console; otherwise log only.
if [[ "${LOG_LEVEL}" = "debug" ]]; then
  ECHO_SETTING="set echo on"
  TEE_ARGS=("-a" "${LOG_FILE}")
else
  ECHO_SETTING="set echo off"
  TEE_ARGS=("-a" "${LOG_FILE}")
fi

# Write a stable log header before invoking SQLcl.
cat >"${LOG_FILE}" <<EOF
[INFO] START

[INFO] RUN_ID=${RUN_ID}
[INFO] ENV=${ENV_NAME}
[INFO] CONNECTION=${CONNECTION}
[INFO] SCRIPT=${SCRIPT_ARG}
[INFO] SCRIPT_PATH=${SCRIPT_PATH}
[INFO] SCRIPT_SHA256=${SCRIPT_SHA256}
[INFO] GIT_COMMIT=${GIT_COMMIT}
[INFO] GIT_DIRTY=${GIT_DIRTY}
[INFO] LOG_LEVEL=${LOG_LEVEL}
[INFO] TIMESTAMP=${TIMESTAMP}
[INFO] LOG_FILE=${LOG_FILE}

[INTENT]
${INTENT_TEXT}
[END INTENT]

[ACTION]
EOF

echo "[INFO] START"
echo "[INFO] RUN_ID=${RUN_ID}"
echo "[INFO] ENV=${ENV_NAME}"
echo "[INFO] CONNECTION=${CONNECTION}"
echo "[INFO] SCRIPT=${SCRIPT_ARG}"
echo "[INFO] LOG_FILE=${LOG_FILE}"
echo "[INFO] LOG_LEVEL=${LOG_LEVEL}"

# Run the target script inside a controlled SQLcl session and capture all output.
set +e
if [[ "${LOG_LEVEL}" = "debug" ]]; then
  "${SQLCL_BIN}" -name "${CONNECTION}" 2>&1 <<EOF | tee "${TEE_ARGS[@]}"
whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback
set feedback on
set timing on
set serveroutput on size unlimited
set define off
set sqlblanklines on
${ECHO_SETTING}
@${SCRIPT_PATH}
prompt [INFO] USER_ERRORS_CHECK
select
    name,
    type,
    line,
    position,
    text
from user_errors
order by
    name,
    type,
    sequence;
exit success
EOF
  SQLCL_EXIT=$?
else
  "${SQLCL_BIN}" -name "${CONNECTION}" 2>&1 <<EOF | tee "${TEE_ARGS[@]}" >/dev/null
whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback
set feedback on
set timing on
set serveroutput on size unlimited
set define off
set sqlblanklines on
${ECHO_SETTING}
@${SCRIPT_PATH}
prompt [INFO] USER_ERRORS_CHECK
select
    name,
    type,
    line,
    position,
    text
from user_errors
order by
    name,
    type,
    sequence;
exit success
EOF
  SQLCL_EXIT=$?
fi
set -e

# Treat known SQLcl connection failures as hard failures even if SQLcl returns zero.
if [[ "${SQLCL_EXIT}" -eq 0 ]] && grep -Eq '(^SP2-|^Unknown connection\b)' "${LOG_FILE}"; then
  SQLCL_EXIT=1
fi

# Append the final execution status to the log and console summary.
if [[ "${SQLCL_EXIT}" -eq 0 ]]; then
  STATUS="SUCCESS"
else
  STATUS="FAILURE"
fi

cat >>"${LOG_FILE}" <<EOF
[OUTCOME]
STATUS=${STATUS}
SQLCL_EXIT=${SQLCL_EXIT}

[INFO] SQLCL_EXIT=${SQLCL_EXIT}
[INFO] END
EOF

if [[ "${STATUS}" = "SUCCESS" ]]; then
  echo "[INFO] SUCCESS"
else
  echo "[ERROR] FAILURE"
fi
echo "[INFO] SQLCL_EXIT=${SQLCL_EXIT}"

if declare -F db_history_store_run >/dev/null 2>&1 && command -v sqlite3 >/dev/null 2>&1; then
  if "${PROJECT_ROOT}/bin/db-history-init.sh" --schema-only >/dev/null 2>&1; then
    LOG_SHA256="$(db_history_hash_file "${LOG_FILE}")"
    KEY_ERRORS="$(grep -E '(^ORA-[0-9]+|^PLS-[0-9]+|^SP2-|^Unknown connection\b)' "${LOG_FILE}" 2>/dev/null | head -5 | tr '\n' ' ' || true)"
    ACTION_EXCERPT="$(
      awk '
        /^\[ACTION\]$/ { inside = 1; next }
        /^\[OUTCOME\]$/ { exit }
        inside && NF {
          print
          count++
          if (count == 3) {
            exit
          }
        }
      ' "${LOG_FILE}" | tr '\n' ' ' | cut -c1-240
    )"
    SUMMARY="${SCRIPT_ARG} ${STATUS} on ${ENV_NAME} at ${GIT_COMMIT}."
    if [[ -n "${KEY_ERRORS}" ]]; then
      SUMMARY="${SUMMARY} Errors: ${KEY_ERRORS}"
    fi
    if [[ -n "${ACTION_EXCERPT}" ]]; then
      SUMMARY="${SUMMARY} Excerpt: ${ACTION_EXCERPT}"
    fi
    if ! db_history_store_run \
      "${RUN_ID}" \
      "${TIMESTAMP}" \
      "${ENV_NAME}" \
      "${CONNECTION}" \
      "${SCRIPT_ARG}" \
      "${SCRIPT_PATH}" \
      "${SCRIPT_SHA256}" \
      "${GIT_COMMIT}" \
      "${GIT_DIRTY}" \
      "${STATUS}" \
      "${SQLCL_EXIT}" \
      "${INTENT_TEXT}" \
      "${SUMMARY}" \
      "${LOG_FILE}" \
      "${LOG_SHA256}"; then
      echo "[WARN] Failed to store database run history in SQLite" >&2
    fi
  else
    echo "[WARN] Failed to initialise database run history store" >&2
  fi
else
  echo "[WARN] sqlite3 unavailable; database run history was not indexed" >&2
fi

exit "${SQLCL_EXIT}"
