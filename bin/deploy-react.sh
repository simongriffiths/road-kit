#!/usr/bin/env bash
set -euo pipefail

# Stage 1 foundation script:
# validates ROAD config, performs the frontend build,
# and uploads built assets into the Oracle-backed UI asset store.

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROAD_CONFIG="${PROJECT_ROOT}/road.config"
RUN_SQL_SCRIPT="${PROJECT_ROOT}/bin/run-sql.sh"

usage() {
  cat >&2 <<'EOF'
Usage: bin/deploy-react.sh --env <dev|test|prod> --app <app_name>
EOF
}

sql_escape() {
  printf "%s" "$1" | sed "s/'/''/g"
}

detect_content_type() {
  local file_path="$1"
  case "${file_path##*.}" in
    html)
      printf "%s" "text/html"
      ;;
    css)
      printf "%s" "text/css"
      ;;
    js)
      printf "%s" "application/javascript"
      ;;
    json)
      printf "%s" "application/json"
      ;;
    svg)
      printf "%s" "image/svg+xml"
      ;;
    png)
      printf "%s" "image/png"
      ;;
    jpg|jpeg)
      printf "%s" "image/jpeg"
      ;;
    webp)
      printf "%s" "image/webp"
      ;;
    ico)
      printf "%s" "image/x-icon"
      ;;
    txt)
      printf "%s" "text/plain"
      ;;
    *)
      file --mime-type -b "${file_path}"
      ;;
  esac
}

should_skip_asset() {
  local relative_path="$1"
  local file_name

  file_name="$(basename "${relative_path}")"

  case "${file_name}" in
    .*)
      return 0
      ;;
  esac

  return 1
}

upload_asset() {
  local env_name="$1"
  local app_name="$2"
  local file_path="$3"
  local relative_path="$4"
  local temp_sql="$5"
  local append_sql="$6"
  local file_name content_type content_length checksum chunk escaped_app escaped_rel escaped_name escaped_type escaped_checksum

  file_name="$(basename "${file_path}")"
  content_type="$(detect_content_type "${file_path}")"
  content_length="$(wc -c < "${file_path}" | tr -d '[:space:]')"
  checksum="$(shasum -a 256 "${file_path}" | awk '{print $1}')"
  escaped_app="$(sql_escape "${app_name}")"
  escaped_rel="$(sql_escape "${relative_path}")"
  escaped_name="$(sql_escape "${file_name}")"
  escaped_type="$(sql_escape "${content_type}")"
  escaped_checksum="$(sql_escape "${checksum}")"

  : > "${append_sql}"
  while IFS= read -r chunk; do
    printf "  dbms_lob.writeappend(l_blob, utl_raw.length(hextoraw('%s')), hextoraw('%s'));\n" "${chunk}" "${chunk}" >> "${append_sql}"
  done < <(xxd -p -c 2000 "${file_path}")

  cat > "${temp_sql}" <<EOF
whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback
set define off
set serveroutput on size unlimited

declare
  l_blob blob;
begin
  dbms_lob.createtemporary(l_blob, true);
  dbms_lob.open(l_blob, dbms_lob.lob_readwrite);
$(cat "${append_sql}")
  ui_assets_api.upsert_asset(
    p_app_name       => '${escaped_app}',
    p_relative_path  => '${escaped_rel}',
    p_file_name      => '${escaped_name}',
    p_content_type   => '${escaped_type}',
    p_content_length => ${content_length},
    p_checksum       => '${escaped_checksum}',
    p_content        => l_blob
  );
  commit;
  dbms_lob.close(l_blob);
  dbms_lob.freetemporary(l_blob);
end;
/
EOF

  "${RUN_SQL_SCRIPT}" --env "${env_name}" --script "${temp_sql}"
}

ENV_NAME=""
CLI_APP_NAME=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      ENV_NAME="$2"
      shift 2
      ;;
    --app)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      CLI_APP_NAME="$2"
      shift 2
      ;;
    *)
      usage
      exit 2
      ;;
  esac
done

if [[ -z "${ENV_NAME}" || -z "${CLI_APP_NAME}" ]]; then
  usage
  exit 2
fi

case "${ENV_NAME}" in
  dev)
    BUILD_MODE="development"
    ;;
  test)
    BUILD_MODE="test"
    ;;
  prod)
    BUILD_MODE="production"
    ;;
  *)
    echo "[ERROR] Unknown environment: ${ENV_NAME}" >&2
    usage
    exit 2
    ;;
esac

if [[ ! -f "${ROAD_CONFIG}" ]]; then
  echo "[ERROR] Missing road.config at ${ROAD_CONFIG}" >&2
  exit 2
fi

# shellcheck disable=SC1090
source "${ROAD_CONFIG}"

if [[ -z "${APP_NAME:-}" || -z "${UI_BASE_PATH:-}" || -z "${API_BASE_PATH:-}" ]]; then
  echo "[ERROR] road.config must define APP_NAME, UI_BASE_PATH, and API_BASE_PATH" >&2
  exit 2
fi

if [[ "${CLI_APP_NAME}" != "${APP_NAME}" ]]; then
  echo "[ERROR] --app value must match APP_NAME from road.config (${APP_NAME})" >&2
  exit 2
fi

APP_DIR="${PROJECT_ROOT}/${APP_NAME}"
if [[ ! -d "${APP_DIR}" ]]; then
  echo "[ERROR] Application directory not found: ${APP_DIR}" >&2
  exit 2
fi

if [[ ! -f "${APP_DIR}/package.json" ]]; then
  echo "[ERROR] Missing package.json in application directory: ${APP_DIR}" >&2
  exit 2
fi

if [[ ! -x "${RUN_SQL_SCRIPT}" ]]; then
  echo "[ERROR] Missing executable SQL runner: ${RUN_SQL_SCRIPT}" >&2
  exit 2
fi

if ! command -v npm >/dev/null 2>&1; then
  echo "[ERROR] npm not found on PATH" >&2
  exit 127
fi

if ! command -v xxd >/dev/null 2>&1; then
  echo "[ERROR] xxd not found on PATH" >&2
  exit 127
fi

if ! command -v shasum >/dev/null 2>&1; then
  echo "[ERROR] shasum not found on PATH" >&2
  exit 127
fi

if ! command -v file >/dev/null 2>&1; then
  echo "[ERROR] file command not found on PATH" >&2
  exit 127
fi

echo "[INFO] APP=${APP_NAME}"
echo "[INFO] ENV=${ENV_NAME}"
echo "[INFO] BUILD_MODE=${BUILD_MODE}"
echo "[INFO] APP_DIR=${APP_DIR}"

(
  cd "${APP_DIR}"
  npm run build -- --mode "${BUILD_MODE}"
)

DIST_DIR="${APP_DIR}/dist"
if [[ ! -d "${DIST_DIR}" ]]; then
  echo "[ERROR] Build completed but dist/ was not created: ${DIST_DIR}" >&2
  exit 1
fi

TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TEMP_DIR}"' EXIT

echo "[INFO] BUILD_COMPLETE"
echo "[INFO] DIST_DIR=${DIST_DIR}"
echo "[INFO] Uploading built assets to Oracle"

while IFS= read -r asset_path; do
  relative_path="${asset_path#${DIST_DIR}/}"

  if should_skip_asset "${relative_path}"; then
    echo "[INFO] SKIP=${relative_path}"
    continue
  fi

  safe_name="$(printf "%s" "${relative_path}" | tr '/.' '__')"
  temp_sql="${TEMP_DIR}/${safe_name}.sql"
  append_sql="${TEMP_DIR}/${safe_name}.append.sql"
  echo "[INFO] UPLOAD=${relative_path}"
  upload_asset "${ENV_NAME}" "${APP_NAME}" "${asset_path}" "${relative_path}" "${temp_sql}" "${append_sql}"
done < <(find "${DIST_DIR}" -type f | sort)

echo "[INFO] UPLOAD_COMPLETE"
