#!/usr/bin/env bash

DB_HISTORY_BIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${DB_HISTORY_BIN_DIR}/.." && pwd)"
DB_HISTORY_FILE="${DB_HISTORY_FILE:-${PROJECT_ROOT}/.codex/db-history.sqlite}"

db_history_require_sqlite() {
  if ! command -v sqlite3 >/dev/null 2>&1; then
    echo "[ERROR] sqlite3 is required for database history queries" >&2
    exit 127
  fi
}

db_history_require_db() {
  db_history_require_sqlite
  if [[ ! -f "${DB_HISTORY_FILE}" ]]; then
    echo "[ERROR] History store not found: ${DB_HISTORY_FILE}" >&2
    echo "[ERROR] Run bin/db-history-init.sh --rebuild to index existing logs" >&2
    exit 2
  fi
}

db_history_limit() {
  local limit="${1:-20}"
  if [[ ! "${limit}" =~ ^[0-9]+$ ]] || [[ "${limit}" -lt 1 ]]; then
    echo "[ERROR] Limit must be a positive integer: ${limit}" >&2
    exit 2
  fi
  printf '%s' "${limit}"
}

db_history_quote() {
  local value="${1-}"
  value="$(printf '%s' "${value}" | sed "s/'/''/g")"
  printf "'%s'" "${value}"
}

db_history_like() {
  local value="${1-}"
  value="$(printf '%s' "${value}" | sed "s/'/''/g")"
  printf "'%%%s%%'" "${value}"
}

db_history_hash_file() {
  local file="$1"
  if [[ ! -f "${file}" ]]; then
    printf ''
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "${file}" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "${file}" | awk '{print $1}'
  else
    printf ''
  fi
}

db_history_fts_available() {
  [[ -f "${DB_HISTORY_FILE}" ]] || return 1
  sqlite3 "${DB_HISTORY_FILE}" "select 1 from sqlite_master where type = 'table' and name = 'runs_fts';" 2>/dev/null | grep -q 1
}

db_history_normalize_fts_query() {
  printf '%s' "$*" |
    tr -cs '[:alnum:]_' ' ' |
    awk '{
      for (i = 1; i <= NF; i++) {
        if (i > 1) {
          printf " OR "
        }
        printf "%s", $i
      }
    }'
}

db_history_store_run() {
  local run_id="$1"
  local run_ts="$2"
  local env="$3"
  local connection="$4"
  local script="$5"
  local script_path="$6"
  local script_sha256="$7"
  local git_commit="$8"
  local git_dirty="$9"
  local status="${10}"
  local sqlcl_exit="${11}"
  local intent="${12}"
  local summary="${13}"
  local log_file="${14}"
  local log_sha256="${15}"

  local sqlcl_exit_sql="null"
  if [[ "${sqlcl_exit}" =~ ^-?[0-9]+$ ]]; then
    sqlcl_exit_sql="${sqlcl_exit}"
  fi

  local run_id_sql run_ts_sql env_sql connection_sql script_sql script_path_sql
  local script_sha256_sql git_commit_sql git_dirty_sql status_sql intent_sql
  local summary_sql log_file_sql log_sha256_sql

  run_id_sql="$(db_history_quote "${run_id}")"
  run_ts_sql="$(db_history_quote "${run_ts}")"
  env_sql="$(db_history_quote "${env}")"
  connection_sql="$(db_history_quote "${connection}")"
  script_sql="$(db_history_quote "${script}")"
  script_path_sql="$(db_history_quote "${script_path}")"
  script_sha256_sql="$(db_history_quote "${script_sha256}")"
  git_commit_sql="$(db_history_quote "${git_commit}")"
  git_dirty_sql="$(db_history_quote "${git_dirty}")"
  status_sql="$(db_history_quote "${status}")"
  intent_sql="$(db_history_quote "${intent}")"
  summary_sql="$(db_history_quote "${summary}")"
  log_file_sql="$(db_history_quote "${log_file}")"
  log_sha256_sql="$(db_history_quote "${log_sha256}")"

  sqlite3 "${DB_HISTORY_FILE}" <<SQL
.bail on
insert into runs (
    run_id,
    run_ts,
    env,
    connection,
    script,
    script_path,
    script_sha256,
    git_commit,
    git_dirty,
    status,
    sqlcl_exit,
    intent,
    summary,
    log_file,
    log_sha256
) values (
    ${run_id_sql},
    ${run_ts_sql},
    ${env_sql},
    ${connection_sql},
    ${script_sql},
    ${script_path_sql},
    ${script_sha256_sql},
    ${git_commit_sql},
    ${git_dirty_sql},
    ${status_sql},
    ${sqlcl_exit_sql},
    ${intent_sql},
    ${summary_sql},
    ${log_file_sql},
    ${log_sha256_sql}
)
on conflict(run_id) do update set
    run_ts = excluded.run_ts,
    env = excluded.env,
    connection = excluded.connection,
    script = excluded.script,
    script_path = excluded.script_path,
    script_sha256 = excluded.script_sha256,
    git_commit = excluded.git_commit,
    git_dirty = excluded.git_dirty,
    status = excluded.status,
    sqlcl_exit = excluded.sqlcl_exit,
    intent = excluded.intent,
    summary = excluded.summary,
    log_file = excluded.log_file,
    log_sha256 = excluded.log_sha256;
SQL

  if db_history_fts_available; then
    sqlite3 "${DB_HISTORY_FILE}" <<SQL
.bail on
delete from runs_fts
where rowid = (
    select rowid
    from runs
    where run_id = ${run_id_sql}
);

insert into runs_fts (
    rowid,
    run_id,
    script,
    script_path,
    intent,
    summary
)
select
    rowid,
    run_id,
    script,
    script_path,
    intent,
    summary
from runs
where run_id = ${run_id_sql};
SQL
  fi
}
