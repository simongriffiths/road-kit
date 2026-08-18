#!/usr/bin/env bash
set -euo pipefail

source bin/assert-http.sh

echo "[INFO] Starting endpoint tests"
bash test/endpoint/health.endpoint.sh
bash test/endpoint/auth-config.endpoint.sh
bash test/endpoint/ui-root.endpoint.sh
bash test/endpoint/ui-asset.endpoint.sh
bash test/endpoint/ui-spa.endpoint.sh
bash test/endpoint/session-me.endpoint.sh
# Enabled by the spec patch 06 phase 8 backport, which brings road_ctx, road_admin_api and the
# identity tables this suite asserts against. Running it before then would fail on missing objects
# rather than on a real conformance gap.
# bash test/endpoint/auth-conformance.endpoint.sh
echo "[INFO] Endpoint tests complete"
