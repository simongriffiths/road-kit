#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: bin/pipeline.sh --env <dev|test|prod> --app <app_name>
EOF
}

usage
echo "bin/pipeline.sh is scaffolded but not implemented yet." >&2
exit 1
