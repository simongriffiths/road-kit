#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=bin/db-history-common.sh
source "${PROJECT_ROOT}/bin/db-history-common.sh"

usage() {
  cat >&2 <<'EOF'
Usage: bin/db-history-init.sh [--schema-only|--rebuild]
EOF
}

REBUILD=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --schema-only)
      REBUILD=false
      shift
      ;;
    --rebuild)
      REBUILD=true
      shift
      ;;
    *)
      usage
      exit 2
      ;;
  esac
done

db_history_require_sqlite
mkdir -p "$(dirname "${DB_HISTORY_FILE}")"

sqlite3 "${DB_HISTORY_FILE}" <<'SQL'
.bail on
create table if not exists runs (
    run_id        text primary key,
    run_ts        text not null,
    env           text not null,
    connection    text,
    script        text not null,
    script_path   text not null,
    script_sha256 text,
    git_commit    text,
    git_dirty     text,
    status        text not null,
    sqlcl_exit    integer,
    intent        text,
    summary       text,
    log_file      text not null,
    log_sha256    text
);

create index if not exists runs_idx_ts
on runs(run_ts);

create index if not exists runs_idx_env_status
on runs(env,status);

create index if not exists runs_idx_script
on runs(script);

create index if not exists runs_idx_git
on runs(git_commit);
SQL

if ! sqlite3 "${DB_HISTORY_FILE}" <<'SQL' >/dev/null 2>&1
create virtual table if not exists runs_fts
using fts5(
    run_id,
    script,
    script_path,
    intent,
    summary
);
SQL
then
  echo "[WARN] SQLite FTS5 is unavailable; history search will use LIKE fallback" >&2
fi

if [[ "${REBUILD}" != "true" ]]; then
  exit 0
fi

first_log_value() {
  local key="$1"
  local file="$2"
  awk -v key="${key}" '
    index($0, "[INFO] " key "=") == 1 {
      sub("^\\[INFO\\] " key "=", "")
      print
      exit
    }
    index($0, key "=") == 1 {
      sub("^" key "=", "")
      print
      exit
    }
  ' "${file}"
}

extract_log_intent() {
  local file="$1"
  awk '
    /^\[INTENT\]$/ {
      inside = 1
      next
    }
    /^\[END INTENT\]$/ {
      exit
    }
    inside {
      print
    }
  ' "${file}"
}

compact_stream() {
  tr '\n' ' ' | sed 's/[[:space:]][[:space:]]*/ /g' | cut -c1-240
}

action_excerpt() {
  local file="$1"
  awk '
    /^\[ACTION\]$/ {
      inside = 1
      next
    }
    /^\[OUTCOME\]$/ {
      exit
    }
    inside && NF {
      print
      count++
      if (count == 3) {
        exit
      }
    }
  ' "${file}" | compact_stream
}

key_errors() {
  local file="$1"
  grep -E '(^ORA-[0-9]+|^PLS-[0-9]+|^SP2-|^Unknown connection\b)' "${file}" 2>/dev/null |
    head -5 |
    compact_stream || true
}

derive_env_from_path() {
  local file="$1"
  local rel="${file#${PROJECT_ROOT}/logs/}"
  printf '%s' "${rel%%/*}"
}

derive_ts_from_path() {
  local file="$1"
  local base
  base="$(basename "${file}" .log)"
  if [[ "${base}" =~ ^([0-9]{8}_[0-9]{6}) ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
  else
    date -r "${file}" +%Y%m%d_%H%M%S 2>/dev/null || printf 'unknown'
  fi
}

import_log() {
  local log_file="$1"
  local run_id run_ts env connection script script_path script_sha256
  local git_commit git_dirty status sqlcl_exit intent summary log_sha256
  local errors excerpt

  run_id="$(first_log_value RUN_ID "${log_file}")"
  if [[ -z "${run_id}" ]]; then
    run_id="$(basename "${log_file}" .log)"
  fi

  run_ts="$(first_log_value TIMESTAMP "${log_file}")"
  if [[ -z "${run_ts}" ]]; then
    run_ts="$(derive_ts_from_path "${log_file}")"
  fi

  env="$(first_log_value ENV "${log_file}")"
  if [[ -z "${env}" ]]; then
    env="$(derive_env_from_path "${log_file}")"
  fi

  connection="$(first_log_value CONNECTION "${log_file}")"
  script="$(first_log_value SCRIPT "${log_file}")"
  if [[ -z "${script}" ]]; then
    script="$(basename "${log_file}" .log)"
  fi

  script_path="$(first_log_value SCRIPT_PATH "${log_file}")"
  if [[ -z "${script_path}" ]]; then
    if [[ "${script}" = /* ]]; then
      script_path="${script}"
    else
      script_path="${PROJECT_ROOT}/${script}"
    fi
  fi

  script_sha256="$(first_log_value SCRIPT_SHA256 "${log_file}")"
  if [[ -z "${script_sha256}" ]]; then
    script_sha256="$(db_history_hash_file "${script_path}")"
  fi

  git_commit="$(first_log_value GIT_COMMIT "${log_file}")"
  git_dirty="$(first_log_value GIT_DIRTY "${log_file}")"
  sqlcl_exit="$(first_log_value SQLCL_EXIT "${log_file}")"
  status="$(first_log_value STATUS "${log_file}")"
  errors="$(key_errors "${log_file}")"

  if [[ -z "${status}" ]]; then
    if [[ "${sqlcl_exit}" = "0" ]]; then
      status="SUCCESS"
    elif [[ -n "${sqlcl_exit}" || -n "${errors}" ]]; then
      status="FAILURE"
    else
      status="UNKNOWN"
    fi
  fi

  intent="$(extract_log_intent "${log_file}")"
  excerpt="$(action_excerpt "${log_file}")"
  log_sha256="$(db_history_hash_file "${log_file}")"

  summary="${script} ${status} on ${env}"
  if [[ -n "${git_commit}" ]]; then
    summary="${summary} at ${git_commit}"
  fi
  summary="${summary}."
  if [[ -n "${errors}" ]]; then
    summary="${summary} Errors: ${errors}"
  fi
  if [[ -n "${excerpt}" ]]; then
    summary="${summary} Excerpt: ${excerpt}"
  fi

  db_history_store_run \
    "${run_id}" \
    "${run_ts}" \
    "${env}" \
    "${connection}" \
    "${script}" \
    "${script_path}" \
    "${script_sha256}" \
    "${git_commit}" \
    "${git_dirty}" \
    "${status}" \
    "${sqlcl_exit}" \
    "${intent}" \
    "${summary}" \
    "${log_file}" \
    "${log_sha256}"
}

sqlite3 "${DB_HISTORY_FILE}" 'delete from runs;'
if db_history_fts_available; then
  sqlite3 "${DB_HISTORY_FILE}" 'delete from runs_fts;'
fi

COUNT=0
if [[ -d "${PROJECT_ROOT}/logs" ]]; then
  while IFS= read -r -d '' LOG_FILE; do
    import_log "${LOG_FILE}"
    COUNT=$((COUNT + 1))
  done < <(find "${PROJECT_ROOT}/logs" -path '*/runs/*.log' -type f -print0)
fi

echo "[INFO] Indexed ${COUNT} log file(s) into ${DB_HISTORY_FILE}"
