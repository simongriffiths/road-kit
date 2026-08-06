#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=bin/db-history-common.sh
source "${PROJECT_ROOT}/bin/db-history-common.sh"

usage() {
  cat >&2 <<'EOF'
Usage: bin/db-history-similar.sh <description>
EOF
}

[[ $# -ge 1 ]] || { usage; exit 2; }

db_history_require_db

TERM="$*"

if db_history_fts_available; then
  FTS_QUERY="$(db_history_normalize_fts_query "${TERM}")"
  if [[ -n "${FTS_QUERY}" ]]; then
    FTS_SQL="$(db_history_quote "${FTS_QUERY}")"
    sqlite3 -header -column "${DB_HISTORY_FILE}" <<SQL
select
    r.run_ts as timestamp,
    r.env,
    r.status,
    r.script,
    r.git_commit,
    substr(coalesce(nullif(r.intent, ''), r.summary), 1, 180) as intent_excerpt,
    r.log_file
from runs_fts f
join runs r on r.run_id = f.run_id
where runs_fts match ${FTS_SQL}
order by bm25(runs_fts)
limit 10;
SQL
    exit 0
  fi
fi

TERM_SQL="$(db_history_like "${TERM}")"
sqlite3 -header -column "${DB_HISTORY_FILE}" <<SQL
select
    run_ts as timestamp,
    env,
    status,
    script,
    git_commit,
    substr(coalesce(nullif(intent, ''), summary), 1, 180) as intent_excerpt,
    log_file
from runs
where intent like ${TERM_SQL}
   or summary like ${TERM_SQL}
   or script like ${TERM_SQL}
   or script_path like ${TERM_SQL}
order by run_ts desc
limit 10;
SQL
