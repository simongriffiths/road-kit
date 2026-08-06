#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=bin/db-history-common.sh
source "${PROJECT_ROOT}/bin/db-history-common.sh"

usage() {
  cat >&2 <<'EOF'
Usage: bin/db-history-commit.sh <commit-prefix> [limit]
EOF
}

[[ $# -ge 1 && $# -le 2 ]] || { usage; exit 2; }

db_history_require_db

COMMIT_PREFIX="$1"
LIMIT="$(db_history_limit "${2:-20}")"
COMMIT_SQL="$(db_history_like "${COMMIT_PREFIX}")"

sqlite3 -header -column "${DB_HISTORY_FILE}" <<SQL
select
    run_ts as timestamp,
    env,
    status,
    script,
    git_commit,
    log_file
from runs
where git_commit like ${COMMIT_SQL}
order by run_ts desc
limit ${LIMIT};
SQL
