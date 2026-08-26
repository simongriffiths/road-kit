#!/usr/bin/env bash
set -euo pipefail

# Renders the authentication provider profile deploy-time artifacts, chosen by AUTH_PROFILE
# (spec-patch-09 section 2): deploy/create/80_standalone.generated.sql (the ORDS JWT profile
# registration) and deploy/create/90_rest_auth.generated.sql (whether the scaffold's public login
# endpoint is deployed at all).
#
# AUTH_PROFILE HAS NO DEFAULT, on purpose, matching ROAD_ORDS_HOST below it -- both are "a wrong
# guess here is worse than a missing value" cases. ROAD_ORDS_HOST's own comment explains why: a
# plausible-but-wrong value is exactly how a defect survives unnoticed. Silently defaulting
# AUTH_PROFILE to the scaffold would be a worse version of the same mistake -- it would mean a
# forgotten setting deploys the DEVELOPMENT identity provider to an environment meant to run
# production's.

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROAD_CONFIG="${PROJECT_ROOT}/road.config"
SCAFFOLD_TEMPLATE="${PROJECT_ROOT}/deploy/create/80_standalone.sql.tmpl"
EXTERNAL_OIDC_TEMPLATE="${PROJECT_ROOT}/deploy/create/80_standalone.external_oidc.sql.tmpl"
OUTPUT="${PROJECT_ROOT}/deploy/create/80_standalone.generated.sql"
REST_AUTH_OUTPUT="${PROJECT_ROOT}/deploy/create/90_rest_auth.generated.sql"

usage() {
  cat >&2 <<'EOF'
Usage: bin/render-auth-config.sh --env <dev|test|prod>

Requires AUTH_PROFILE to be set to one of the two names authentication-spec-v1.md section 8
registers:

  AUTH_PROFILE=ords_local_jwt_scaffold   (development -- also requires ROAD_ORDS_HOST)
  AUTH_PROFILE=external_oidc             (production -- also requires ROAD_AUTH0_DOMAIN and
                                           ROAD_AUTH0_AUDIENCE)

Example, scaffold:
  export AUTH_PROFILE=ords_local_jwt_scaffold
  export ROAD_ORDS_HOST=https://example-db.adb.<region>.oraclecloudapps.com
  bin/render-auth-config.sh --env dev

Example, external_oidc:
  export AUTH_PROFILE=external_oidc
  export ROAD_AUTH0_DOMAIN=your-tenant.uk.auth0.com
  export ROAD_AUTH0_AUDIENCE=https://api.your-app.example.com
  bin/render-auth-config.sh --env prod
EOF
}

ENV_NAME=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      ENV_NAME="$2"
      shift 2
      ;;
    *)
      usage
      exit 2
      ;;
  esac
done

if [[ -z "${ENV_NAME}" ]]; then
  usage
  exit 2
fi

case "${ENV_NAME}" in
  dev|test|prod)
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

if [[ -z "${APP_NAME:-}" || -z "${API_BASE_PATH:-}" ]]; then
  echo "[ERROR] road.config must define APP_NAME and API_BASE_PATH" >&2
  exit 2
fi

if [[ -z "${AUTH_PROFILE:-}" ]]; then
  echo "[ERROR] AUTH_PROFILE must be set - there is no default" >&2
  usage
  exit 2
fi

case "${AUTH_PROFILE}" in
  ords_local_jwt_scaffold|external_oidc)
    ;;
  *)
    echo "[ERROR] Unknown AUTH_PROFILE: ${AUTH_PROFILE}" >&2
    echo "[ERROR] Must be exactly 'ords_local_jwt_scaffold' or 'external_oidc' - these are the" >&2
    echo "[ERROR] provider profile names from authentication-spec-v1.md section 8, not free text" >&2
    exit 2
    ;;
esac

sql_escape() {
  printf "%s" "$1" | sed "s/'/''/g"
}

API_BASE_PATH_SQL="$(sql_escape "${API_BASE_PATH}")"

if [[ "${AUTH_PROFILE}" == "ords_local_jwt_scaffold" ]]; then

  # Deliberately no default. A plausible-but-wrong host is exactly how the original defect survived
  # from this template's original prototyping instance into a built app without anyone noticing.
  if [[ -z "${ROAD_ORDS_HOST:-}" ]]; then
    echo "[ERROR] ROAD_ORDS_HOST must be set, for example https://example.adb.region.oraclecloudapps.com" >&2
    echo "[ERROR] Required by AUTH_PROFILE=ords_local_jwt_scaffold - there is no default" >&2
    exit 2
  fi

  HOST_BASE="${ROAD_ORDS_HOST%/}"
  ISSUER="urn:road:${APP_NAME}:${ENV_NAME}"
  JWK_URL="${HOST_BASE}/ords/${API_BASE_PATH}/jwt-auth/.well-known/jwks.json"

  ISSUER_SQL="$(sql_escape "${ISSUER}")"
  JWK_URL_SQL="$(sql_escape "${JWK_URL}")"

  CONTENT="$(cat "${SCAFFOLD_TEMPLATE}")"
  CONTENT="${CONTENT//@@ROAD_ISSUER@@/${ISSUER_SQL}}"
  CONTENT="${CONTENT//@@ROAD_JWK_URL@@/${JWK_URL_SQL}}"
  CONTENT="${CONTENT//@@ROAD_API_BASE_PATH@@/${API_BASE_PATH_SQL}}"

  if [[ "${CONTENT}" == *"@@ROAD_"* ]]; then
    echo "[ERROR] Unsubstituted placeholder remains in rendered output:" >&2
    printf '%s\n' "${CONTENT}" | grep -oE '@@ROAD_[A-Z0-9_]*@@' | sort -u >&2
    exit 1
  fi

  printf '%s\n' "${CONTENT}" > "${OUTPUT}"

  # The scaffold's public login surface deploys under this profile, and only this one.
  cat > "${REST_AUTH_OUTPUT}" <<'FRAGMENT'
-- GENERATED FILE - DO NOT EDIT. Rendered by bin/render-auth-config.sh from AUTH_PROFILE.
-- ords_local_jwt_scaffold: the scaffold's public login endpoint deploys.
@api/modules/auth/module.create.sql
@api/modules/auth/privileges.create.sql
FRAGMENT

  echo "[INFO] AUTH_PROFILE=ords_local_jwt_scaffold"
  echo "[INFO] ENV=${ENV_NAME}"
  echo "[INFO] ISSUER=${ISSUER}"
  echo "[INFO] JWK_URL=${JWK_URL}"

else
  # external_oidc

  if [[ -z "${ROAD_AUTH0_DOMAIN:-}" ]]; then
    echo "[ERROR] ROAD_AUTH0_DOMAIN must be set, for example your-tenant.uk.auth0.com" >&2
    echo "[ERROR] Required by AUTH_PROFILE=external_oidc - there is no default" >&2
    exit 2
  fi
  if [[ -z "${ROAD_AUTH0_AUDIENCE:-}" ]]; then
    echo "[ERROR] ROAD_AUTH0_AUDIENCE must be set, for example https://api.your-app.example.com" >&2
    echo "[ERROR] Required by AUTH_PROFILE=external_oidc - there is no default" >&2
    exit 2
  fi

  DOMAIN_BASE="${ROAD_AUTH0_DOMAIN%/}"

  # The trailing slash is part of the issuer's value for an Auth0 tenant and must match exactly
  # what the provider puts in the token -- road-blogger's auth0-manual-setup.md section 7 confirms
  # this against a real tenant. A provider other than Auth0 may format its issuer differently; this
  # script assumes Auth0's convention because that is the only external_oidc provider proven so far
  # (authentication-spec-v1.md section 9's Provenance).
  ISSUER="https://${DOMAIN_BASE}/"
  JWK_URL="https://${DOMAIN_BASE}/.well-known/jwks.json"

  ISSUER_SQL="$(sql_escape "${ISSUER}")"
  AUDIENCE_SQL="$(sql_escape "${ROAD_AUTH0_AUDIENCE}")"
  JWK_URL_SQL="$(sql_escape "${JWK_URL}")"

  CONTENT="$(cat "${EXTERNAL_OIDC_TEMPLATE}")"
  CONTENT="${CONTENT//@@ROAD_AUTH0_ISSUER@@/${ISSUER_SQL}}"
  CONTENT="${CONTENT//@@ROAD_AUTH0_AUDIENCE@@/${AUDIENCE_SQL}}"
  CONTENT="${CONTENT//@@ROAD_AUTH0_JWK_URL@@/${JWK_URL_SQL}}"
  CONTENT="${CONTENT//@@ROAD_API_BASE_PATH@@/${API_BASE_PATH_SQL}}"

  if [[ "${CONTENT}" == *"@@ROAD_"* ]]; then
    echo "[ERROR] Unsubstituted placeholder remains in rendered output:" >&2
    printf '%s\n' "${CONTENT}" | grep -oE '@@ROAD_[A-Z0-9_]*@@' | sort -u >&2
    exit 1
  fi

  printf '%s\n' "${CONTENT}" > "${OUTPUT}"

  # The scaffold's public login surface must NOT deploy under this profile -- it is the one thing
  # spec-patch-09 section 2 requires to be absent, not merely inert. See the comment at the
  # inclusion point in deploy/create/90_rest.sql for why the rest of the scaffold's namespace
  # (packages, tables) is left deployed-but-dormant rather than also excluded.
  #
  # NOT ADDING api/modules/auth/module.create.sql's @-include here is enough for a FRESH deploy --
  # the module is simply never created. It is NOT enough for a schema SWITCHING from
  # ords_local_jwt_scaffold to external_oidc: the module from a prior scaffold deploy stays
  # registered, because nothing else ever tells ORDS to remove it. Found deploying this against
  # road_kit_dev, which had the scaffold module from every earlier phase -- omitting the create
  # script left /jwt-auth/ live and reachable. An explicit delete_module closes that, and is safe
  # to run whether or not the module exists (guarded, matching every delete_module call elsewhere
  # in this codebase).
  API_BASE_PATH_MODULE_SQL="$(sql_escape "${API_BASE_PATH}.auth")"
  cat > "${REST_AUTH_OUTPUT}" <<FRAGMENT
-- GENERATED FILE - DO NOT EDIT. Rendered by bin/render-auth-config.sh from AUTH_PROFILE.
-- external_oidc: the scaffold's public login endpoint does not deploy, and any module left behind
-- by a prior ords_local_jwt_scaffold deploy is explicitly removed rather than merely not recreated.
begin
  ords.delete_module(p_module_name => '${API_BASE_PATH_MODULE_SQL}');
exception
  when others then
    null;
end;
/
FRAGMENT

  echo "[INFO] AUTH_PROFILE=external_oidc"
  echo "[INFO] ENV=${ENV_NAME}"
  echo "[INFO] ISSUER=${ISSUER}"
  echo "[INFO] AUDIENCE=${ROAD_AUTH0_AUDIENCE}"
  echo "[INFO] JWK_URL=${JWK_URL}"
fi

echo "[INFO] RENDERED=${OUTPUT#"${PROJECT_ROOT}/"}"
echo "[INFO] RENDERED=${REST_AUTH_OUTPUT#"${PROJECT_ROOT}/"}"
