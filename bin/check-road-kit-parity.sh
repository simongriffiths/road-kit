#!/usr/bin/env bash
set -euo pipefail

# Compares the files road-cal and road-kit are supposed to hold identically.
#
# The shared surface is maintained BY HAND -- every road-kit change reaches road-cal by copying, and
# vice versa. Spec patch 06 added five tables, three packages, a secured context and a test suite to
# that surface at exactly the moment the two repos most needed to agree (risk 10.4). This is the
# cheap mitigation: it will not stop divergence, but it makes divergence visible on demand rather
# than at the next backport.
#
# Files NOT listed here diverge deliberately -- 95_data.sql, 99_verify.sql, road.config, the ORDS
# modules and anything naming an application.

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PEER="${ROAD_PEER_PATH:-${PROJECT_ROOT}/../road-cal}"

if [[ ! -d "${PEER}" ]]; then
  echo "[ERROR] Peer repository not found: ${PEER}" >&2
  echo "[ERROR] Set ROAD_PEER_PATH to override" >&2
  exit 2
fi

SHARED_FILES=(
  db/tables/road_principals.create.sql        db/tables/road_principals.drop.sql
  db/tables/road_roles.create.sql             db/tables/road_roles.drop.sql
  db/tables/road_permissions.create.sql       db/tables/road_permissions.drop.sql
  db/tables/road_role_permissions.create.sql  db/tables/road_role_permissions.drop.sql
  db/tables/road_principal_roles.create.sql   db/tables/road_principal_roles.drop.sql
  db/tables/road_config.create.sql            db/tables/road_config.drop.sql
  db/tables/error_log.create.sql              db/tables/error_log.drop.sql
  db/triggers/road_principals_updated_at.create.sql db/triggers/road_principals_updated_at.drop.sql
  db/triggers/road_config_updated_at.create.sql     db/triggers/road_config_updated_at.drop.sql
  db/indexes/road_principals_email.create.sql       db/indexes/road_principals_email.drop.sql
  db/indexes/road_principal_roles_role.create.sql   db/indexes/road_principal_roles_role.drop.sql
  db/package_specs/road_ctx_pkg.pks           db/package_bodies/road_ctx_pkg.pkb
  db/package_specs/road_ctx_pkg_test.pks      db/package_bodies/road_ctx_pkg_test.pkb
  db/package_specs/road_admin_api.pks         db/package_bodies/road_admin_api.pkb
  db/package_specs/road_admin_api_test.pks    db/package_bodies/road_admin_api_test.pkb
  db/package_specs/error_api.pks              db/package_bodies/error_api.pkb
  db/package_specs/error_api_test.pks         db/package_bodies/error_api_test.pkb
  db/package_specs/jwt_scaffold_auth_api.pks  db/package_bodies/jwt_scaffold_auth_api.pkb
  deploy/create/65_contexts.sql               deploy/drop/65_contexts.sql
  bin/get-test-token.sh                       bin/run-endpoint-tests.sh
  bin/check-handler-coverage.sh               bin/rotate-scaffold-credential.sh
  admin/grant-schema-privileges.sql
  test/endpoint/auth-conformance.endpoint.sh
  planning/coding-standards-v1.md
)

DIVERGED=0
MISSING=0

for f in "${SHARED_FILES[@]}"; do
  if [[ ! -f "${PROJECT_ROOT}/${f}" ]]; then
    echo "[FAIL] missing here: ${f}" >&2; MISSING=$(( MISSING + 1 )); continue
  fi
  if [[ ! -f "${PEER}/${f}" ]]; then
    echo "[FAIL] missing in peer: ${f}" >&2; MISSING=$(( MISSING + 1 )); continue
  fi
  if ! diff -q "${PROJECT_ROOT}/${f}" "${PEER}/${f}" >/dev/null 2>&1; then
    echo "[FAIL] diverged: ${f}" >&2; DIVERGED=$(( DIVERGED + 1 ))
  fi
done

echo "[INFO] Checked ${#SHARED_FILES[@]} shared files against ${PEER}"

if [[ "${DIVERGED}" -gt 0 || "${MISSING}" -gt 0 ]]; then
  echo "[FAIL] ${DIVERGED} diverged, ${MISSING} missing" >&2
  exit 1
fi

echo "[PASS] Shared surface is identical"
