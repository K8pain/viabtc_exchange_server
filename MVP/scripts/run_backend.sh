#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"
load_env
ensure_dirs

start_service() {
  local name="$1"
  local bin="$2"
  local cfg="$3"

  if [[ ! -x "$bin" ]]; then
    echo "Binary not found/executable: $bin" >&2
    exit 1
  fi

  echo "[start] $name"
  nohup "$bin" "$cfg" > "$LOG_DIR/${name}.log" 2>&1 &
  echo $! > "$RUN_DIR/${name}.pid"
  sleep 1

  if ! kill -0 "$(cat "$RUN_DIR/${name}.pid")" 2>/dev/null; then
    echo "Failed to start $name" >&2
    exit 1
  fi
}

start_service "matchengine" "$ROOT_DIR/matchengine/matchengine.exe" "$ROOT_DIR/matchengine/config.json"
start_service "marketprice" "$ROOT_DIR/marketprice/marketprice.exe" "$ROOT_DIR/marketprice/config.json"
start_service "readhistory" "$ROOT_DIR/readhistory/readhistory.exe" "$ROOT_DIR/readhistory/config.json"
start_service "accesshttp" "$ROOT_DIR/accesshttp/accesshttp.exe" "$ROOT_DIR/accesshttp/config.json"
start_service "accessws" "$ROOT_DIR/accessws/accessws.exe" "$ROOT_DIR/accessws/config.json"
start_service "alertcenter" "$ROOT_DIR/alertcenter/alertcenter.exe" "$ROOT_DIR/alertcenter/config.json"

echo "All backend services started"
