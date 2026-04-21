#!/usr/bin/env bash
set -euo pipefail

source bin/assert-http.sh

echo "[INFO] Starting endpoint tests"
bash test/endpoint/health.endpoint.sh
echo "[INFO] Endpoint tests complete"
