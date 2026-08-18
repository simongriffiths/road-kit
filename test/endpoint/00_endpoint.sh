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
echo "[INFO] Endpoint tests complete"
