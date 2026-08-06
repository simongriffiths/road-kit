#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=bin/db-history-common.sh
source "${PROJECT_ROOT}/bin/db-history-common.sh"

usage() {
  cat >&2 <<'EOF'
Usage: bin/db-history-show.sh <run_id>
EOF
}

[[ $# -eq 1 ]] || { usage; exit 2; }

db_history_require_db

RUN_ID_SQL="$(db_history_quote "$1")"
MATCH_COUNT="$(sqlite3 "${DB_HISTORY_FILE}" "select count(*) from runs where run_id = ${RUN_ID_SQL};")"

if [[ "${MATCH_COUNT}" = "0" ]]; then
  PREFIX_SQL="$(db_history_quote "$1%")"
  MATCH_COUNT="$(sqlite3 "${DB_HISTORY_FILE}" "select count(*) from runs where run_id like ${PREFIX_SQL};")"
  if [[ "${MATCH_COUNT}" = "1" ]]; then
    RUN_ID_SQL="(select run_id from runs where run_id like ${PREFIX_SQL} limit 1)"
  else
    echo "[ERROR] Run not found or prefix is ambiguous: $1" >&2
    exit 1
  fi
fi

sqlite3 -line "${DB_HISTORY_FILE}" <<SQL
select
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
from runs
where run_id = ${RUN_ID_SQL};
SQL
