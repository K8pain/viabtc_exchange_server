#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

for service in matchengine marketprice readhistory accesshttp accessws alertcenter; do
  pid_file="$RUN_DIR/${service}.pid"
  if [[ -f "$pid_file" ]]; then
    pid="$(cat "$pid_file")"
    if kill -0 "$pid" 2>/dev/null; then
      kill "$pid" || true
      sleep 1
      kill -9 "$pid" 2>/dev/null || true
      echo "[stop] $service ($pid)"
    fi
    rm -f "$pid_file"
  fi
  pkill -f "$service\.exe" 2>/dev/null || true
done

echo "All backend services stopped"
