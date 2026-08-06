#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=bin/db-history-common.sh
source "${PROJECT_ROOT}/bin/db-history-common.sh"

usage() {
  cat >&2 <<'EOF'
Usage: bin/db-history-script.sh <term> [limit]
EOF
}

[[ $# -ge 1 && $# -le 2 ]] || { usage; exit 2; }

db_history_require_db

TERM="$1"
LIMIT="$(db_history_limit "${2:-20}")"
TERM_SQL="$(db_history_like "${TERM}")"

sqlite3 -header -column "${DB_HISTORY_FILE}" <<SQL
select
    run_ts as timestamp,
    env,
    status,
    script,
    git_commit,
    log_file
from runs
where script like ${TERM_SQL}
   or script_path like ${TERM_SQL}
   or intent like ${TERM_SQL}
   or summary like ${TERM_SQL}
order by run_ts desc
limit ${LIMIT};
SQL
