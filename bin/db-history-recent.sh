#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=bin/db-history-common.sh
source "${PROJECT_ROOT}/bin/db-history-common.sh"

db_history_require_db

ENV_FILTER="${1:-}"
LIMIT_ARG="${2:-20}"

if [[ "${ENV_FILTER}" =~ ^[0-9]+$ ]]; then
  LIMIT_ARG="${ENV_FILTER}"
  ENV_FILTER=""
fi

LIMIT="$(db_history_limit "${LIMIT_ARG}")"

if [[ -n "${ENV_FILTER}" ]]; then
  ENV_SQL="$(db_history_quote "${ENV_FILTER}")"
  WHERE_SQL="where env = ${ENV_SQL}"
else
  WHERE_SQL=""
fi

sqlite3 -header -column "${DB_HISTORY_FILE}" <<SQL
select
    run_ts as timestamp,
    env,
    status,
    script,
    git_commit
from runs
${WHERE_SQL}
order by run_ts desc
limit ${LIMIT};
SQL
