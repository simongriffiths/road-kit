#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=bin/db-history-common.sh
source "${PROJECT_ROOT}/bin/db-history-common.sh"

db_history_require_db

TERM="${1:-}"

if [[ -n "${TERM}" ]]; then
  TERM_SQL="$(db_history_like "${TERM}")"
  WHERE_SQL="where status = 'FAILURE'
and (
    script like ${TERM_SQL}
    or script_path like ${TERM_SQL}
    or intent like ${TERM_SQL}
    or summary like ${TERM_SQL}
)"
else
  WHERE_SQL="where status = 'FAILURE'"
fi

sqlite3 -header -column "${DB_HISTORY_FILE}" <<SQL
select
    run_ts as timestamp,
    env,
    status,
    script,
    git_commit,
    log_file
from runs
${WHERE_SQL}
order by run_ts desc
limit 30;
SQL
