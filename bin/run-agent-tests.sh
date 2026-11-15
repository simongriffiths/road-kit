#!/usr/bin/env bash
set -euo pipefail
# Agents, API keys and road-cli over HTTP (spec-patch-15). Adds a fixture person, mints short-lived
# person tokens straight from the database (bin/get-test-token.sh with --scope, so no password is
# needed), runs test/agents/agents.test.mjs and test/agents/road-cli.test.mjs, then removes every
# agent, key and fixture the run made, whatever the result. Tokens and keys are never printed.
#
#   bin/run-agent-tests.sh --env dev
#
# Needs the demo (deploy/create/97_demo.sql), which switches self-serve agents on with todo_agent.

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${PROJECT_ROOT}"
ENV_NAME="${2:-dev}"
[[ "${1:-}" == "--env" ]] || { echo "Usage: bin/run-agent-tests.sh --env <env>" >&2; exit 2; }
[[ -f config/local.env ]] && source config/local.env
source road.config
: "${ROAD_ORDS_HOST:?ROAD_ORDS_HOST must be set (config/local.env)}"

run() { bin/run-sql.sh --env "$1" --script "$2" >/dev/null 2>&1 || { echo "[ERROR] $2 failed on $1" >&2; return 1; }; }
cleanup() { run "${ENV_NAME}" test/agents/90_cleanup.sql || true; }
trap cleanup EXIT

run "${ENV_NAME}" test/agents/10_setup.sql
mint() { bin/get-test-token.sh --env "${ENV_NAME}" --username "$1" --scope "road.agents.rw session.me.read todo.rw" --ttl 15; }
export TOKEN_USER1="$(mint USER1)"
export TOKEN_ADMIN="$(mint ADMIN)"
export TOKEN_OTHER="$(mint ZZ_AGENT_OTHER)"
export ORDS_BASE_URL="${ROAD_ORDS_HOST%/}/ords/${API_BASE_PATH}/api/v1"
export AUTH_URL="${ROAD_ORDS_HOST%/}/ords/${API_BASE_PATH}/api-auth/tokens"

node test/agents/agents.test.mjs
node test/agents/road-cli.test.mjs

# My agents in a browser, against the deployed scaffold app.
export ROAD_APP_URL="${ROAD_ORDS_HOST%/}/ords/${UI_BASE_PATH}/ui/${APP_NAME}/"
# An existing browser folder may be given; otherwise road-kit's own (npx playwright install).
export PLAYWRIGHT_BROWSERS_PATH="${PLAYWRIGHT_BROWSERS_PATH:-${PROJECT_ROOT}/.playwright-browsers}"
(cd hello_world && npx playwright test e2e/agents.smoke.spec.ts --config playwright.config.ts --reporter=line)
