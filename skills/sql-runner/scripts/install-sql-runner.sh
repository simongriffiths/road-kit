#!/usr/bin/env bash
set -euo pipefail

REPO_URL="${SQL_RUNNER_REPO_URL:-git@github.com:simongriffiths/sql-runner.git}"
TARGET_DIR=""
SOURCE_MODE="auto"

usage() {
  cat >&2 <<'EOF'
Usage: install-sql-runner.sh --target <project-root> [--source auto|local|git]
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      TARGET_DIR="$2"
      shift 2
      ;;
    --source)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      SOURCE_MODE="$2"
      shift 2
      ;;
    *)
      usage
      exit 2
      ;;
  esac
done

if [[ -z "${TARGET_DIR}" ]]; then
  usage
  exit 2
fi

case "${SOURCE_MODE}" in
  auto|local|git)
    ;;
  *)
    echo "[ERROR] Invalid source mode: ${SOURCE_MODE}" >&2
    usage
    exit 2
    ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
LOCAL_REPO_ROOT="$(cd "${SKILL_DIR}/../.." && pwd)"
TARGET_DIR="$(cd "${TARGET_DIR}" && pwd)"

copy_from_root() {
  local source_root="$1"

  mkdir -p "${TARGET_DIR}/bin" "${TARGET_DIR}/config" "${TARGET_DIR}/examples" "${TARGET_DIR}/docs"

  cp "${source_root}/bin/"*.sh "${TARGET_DIR}/bin/"
  chmod +x "${TARGET_DIR}/bin/"*.sh

  cp "${source_root}/config/connections.conf.example" "${TARGET_DIR}/config/connections.conf.example"
  cp "${source_root}/examples/verify-connection.sql" "${TARGET_DIR}/examples/verify-connection.sql"
  cp "${source_root}/docs/publishing-checklist.md" "${TARGET_DIR}/docs/publishing-checklist.md"

  if [[ ! -f "${TARGET_DIR}/config/connections.conf" ]]; then
    cp "${source_root}/config/connections.conf.example" "${TARGET_DIR}/config/connections.conf"
    echo "[INFO] Created config/connections.conf from example; edit connection names before running SQL"
  else
    echo "[INFO] Preserved existing config/connections.conf"
  fi
}

has_local_runner_source() {
  [[ -f "${LOCAL_REPO_ROOT}/bin/run-sql.sh" && -f "${LOCAL_REPO_ROOT}/config/connections.conf.example" ]]
}

if [[ "${SOURCE_MODE}" != "git" ]] && has_local_runner_source; then
  copy_from_root "${LOCAL_REPO_ROOT}"
  echo "[INFO] Installed sql-runner from local checkout: ${LOCAL_REPO_ROOT}"
  exit 0
fi

if [[ "${SOURCE_MODE}" = "local" ]]; then
  echo "[ERROR] Local sql-runner source files were not found near this skill" >&2
  exit 1
fi

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/sql-runner-install.XXXXXX")"
trap 'rm -rf "${TMP_DIR}"' EXIT

git clone --depth 1 "${REPO_URL}" "${TMP_DIR}/sql-runner" >/dev/null
copy_from_root "${TMP_DIR}/sql-runner"
echo "[INFO] Installed sql-runner from ${REPO_URL}"
