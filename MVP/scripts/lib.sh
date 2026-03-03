#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MVP_DIR="$ROOT_DIR/MVP"
RUN_DIR="$MVP_DIR/run"
LOG_DIR="$RUN_DIR/logs"

load_env() {
  local env_file="$MVP_DIR/.env"
  if [[ ! -f "$env_file" ]]; then
    echo "Missing $env_file (copy from MVP/.env.example)" >&2
    exit 1
  fi
  set -a
  source "$env_file"
  set +a

  : "${LAB_MYSQL_HOST:?missing}"
  : "${LAB_MYSQL_PORT:?missing}"
  : "${LAB_MYSQL_DB:?missing}"
  : "${LAB_MYSQL_USER:?missing}"
  : "${LAB_MYSQL_PASSWORD:?missing}"
  : "${LAB_KAFKA_BROKER:?missing}"
}

ensure_dirs() {
  mkdir -p "$RUN_DIR" "$LOG_DIR"
}
