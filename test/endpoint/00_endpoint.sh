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
bash test/endpoint/auth-conformance.endpoint.sh
bash test/endpoint/admin-principals.endpoint.sh
bash test/endpoint/admin-permissions.endpoint.sh
# The demo application. Last, because it is the only suite that depends on deploy/create/97_demo.sql
# having been run -- a framework-only deployment does not have these routes.
bash test/endpoint/todos.endpoint.sh
echo "[INFO] Endpoint tests complete"
