#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
"$SCRIPT_DIR/stop_backend.sh" || true
docker compose -f "$(cd "$SCRIPT_DIR/.." && pwd)/docker-compose.yml" down -v
rm -rf "$(cd "$SCRIPT_DIR/.." && pwd)/run"
echo "Lab reset complete"
