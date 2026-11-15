#!/usr/bin/env bash
set -euo pipefail
# Acceptance test for the generated skill (spec-patch-16 section 4.3): Claude Code, using the
# road-kit-todos skill in a fresh session, adds two todos, marks one done, is refused when it adds
# the second again, and reports what road-cli answered. Runs on the dev schema with fixture
# principals that it removes.
#
#   bin/run-skill-acceptance.sh --env dev
#
# 1. Makes the fixture people (test/agents/10_setup.sql) and, as USER1, an agent with an API key (the
#    same calls as the My agents page). road-cli signs in with the key in a private home. The key is
#    never printed; the home is deleted at the end.
# 2. Copies skills/hello_world into a new empty folder as a project skill, puts road-cli on the path,
#    and starts a fresh, headless Claude Code session there. Its only tools are the skill, reading
#    files and road-cli, allowed on the command line: a new folder is untrusted, so its settings are
#    ignored. The prompt is a task as a person would give it; it does not explain the API.
# 3. Checks the outcome through the API and the decision record, then removes every fixture.
#
# Costs one Claude Code session. The transcript goes to scratch/skill-acceptance-<time>.txt.

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${PROJECT_ROOT}"
ENV_NAME="${2:-dev}"
[[ "${1:-}" == "--env" ]] || { echo "Usage: bin/run-skill-acceptance.sh --env <env>" >&2; exit 2; }
[[ -f config/local.env ]] && source config/local.env
source road.config
: "${ROAD_ORDS_HOST:?ROAD_ORDS_HOST must be set (config/local.env)}"

run() { bin/run-sql.sh --env "$1" --script "$2" >/dev/null 2>&1 || { echo "[ERROR] $2 failed on $1" >&2; return 1; }; }
latest() { ls -t logs/"$1"/runs/*"$2"* | head -1; }
# The real path: on macOS mktemp gives /var/..., which is /private/var/..., and a permission rule
# must name the path the session actually uses.
WORK="$(cd "$(mktemp -d)" && pwd -P)"
STAMP="$(date +%s)"
TRANSCRIPT="scratch/skill-acceptance-$(date +%Y%m%d_%H%M%S).txt"
mkdir -p scratch

cleanup() {
  rm -rf "${WORK}"
  run "${ENV_NAME}" test/agents/90_cleanup.sql || true
}
trap cleanup EXIT

run "${ENV_NAME}" test/agents/10_setup.sql
export ORDS_BASE_URL="${ROAD_ORDS_HOST%/}/ords/${API_BASE_PATH}/api/v1"
TOKEN_USER1="$(bin/get-test-token.sh --env "${ENV_NAME}" --username USER1 --scope "road.agents.rw session.me.read todo.rw" --ttl 15)"
auth() { printf 'Authorization: Bearer %s' "${TOKEN_USER1}"; }
post() { curl -sS -X POST "${ORDS_BASE_URL}$1" -H "Content-Type: application/json" -H "Idempotency-Key: $2" -H "@-" -d "$3" <<< "$(auth)"; }

umask 077
mkdir -p "${WORK}/home" "${WORK}/bin"
AGENT="$(post /agents/ "skill-acc-a-${STAMP}" '{"display_name":"agent-test skill acceptance"}' \
  | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>process.stdout.write(String(JSON.parse(s).result.agent_id)))')"
# The key goes from the API answer straight into road-cli login's standard input.
post "/agents/${AGENT}/keys/" "skill-acc-k-${STAMP}" '{"name":"Skill acceptance"}' \
  | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>process.stdout.write(JSON.parse(s).result.api_key))' \
  | ROAD_CLI_HOME="${WORK}/home" tools/road-cli/road-cli login --url "${ORDS_BASE_URL}"
unset TOKEN_USER1

mkdir -p "${WORK}/project/.claude/skills"
cp -R skills/hello_world "${WORK}/project/.claude/skills/road-kit-todos"
ln -s "${PROJECT_ROOT}/tools/road-cli/road-cli" "${WORK}/bin/road-cli"

PROMPT="You manage a todo list in the road-kit demo. Add a todo titled 'Order stamps ${STAMP}' and another \
titled 'Book the van ${STAMP}'. Mark the stamps one done. Then add 'Book the van ${STAMP}' once more, and \
report exactly what road-cli answered. Use the road-kit-todos skill. Do not change any files."

echo "[INFO] starting a fresh Claude Code session with the road-kit-todos skill"
STARTED=$(date +%s)
( cd "${WORK}/project" && \
  ROAD_CLI_HOME="${WORK}/home" PATH="${WORK}/bin:${PATH}" \
  claude -p "${PROMPT}" --setting-sources project --permission-mode default --output-format json \
    --allowedTools "Skill" "Read" "Bash(road-cli:*)" \
    < /dev/null ) > "${TRANSCRIPT}" 2>&1 || true
echo "[INFO] the session took $(( $(date +%s) - STARTED )) s; transcript ${TRANSCRIPT}"
RESULT="${TRANSCRIPT%.txt}.result.txt"
node -e '
  const o = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
  const u = o.usage || {};
  const input = (u.input_tokens || 0) + (u.cache_read_input_tokens || 0) + (u.cache_creation_input_tokens || 0);
  console.log(`[INFO] tokens: ${input} in (${u.cache_read_input_tokens || 0} from cache), ${u.output_tokens || 0} out; ${o.num_turns} turns; cost ${o.total_cost_usd} USD`);
  require("fs").writeFileSync(process.argv[2], String(o.result || ""));
' "${TRANSCRIPT}" "${RESULT}" || true
grep -qF -f "${WORK}/home/key" "${TRANSCRIPT}" && { echo "[FAIL] the transcript contains the API key" >&2; : > "${TRANSCRIPT}"; exit 1; }

ROAD_CLI_HOME="${WORK}/home" ACC_STAMP="${STAMP}" ACC_RESULT="${RESULT}" node test/skill/verify.mjs

# What the agent did must be in road-kit's decision record, the refusal as TITLE_TAKEN from the agent.
run "${ENV_NAME}" test/skill/decisions.sql
D="$(latest "${ENV_NAME}" decisions)"
grep -h "^AGENT_" "${D}"
grep -q "^AGENT_CREATES=2" "${D}" && grep -q "^AGENT_COMPLETIONS=1" "${D}" && grep -q "^AGENT_TITLE_TAKEN=[1-9]" "${D}" \
  || { echo "[FAIL] the decision record does not show 2 adds, 1 completion and a TITLE_TAKEN refusal" >&2; exit 1; }
echo "[PASS] skill acceptance: a fresh Claude Code session worked the todos with the generated skill"
