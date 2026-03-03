#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"
load_env

check_tcp() {
  local host="$1" port="$2" label="$3"
  if timeout 2 bash -c "</dev/tcp/${host}/${port}" 2>/dev/null; then
    echo "OK: $label"
  else
    echo "FAIL: $label" >&2
    return 1
  fi
}

check_tcp "$LAB_MYSQL_HOST" "$LAB_MYSQL_PORT" "mysql"
check_tcp "$LAB_REDIS_HOST" "$LAB_REDIS_PORT" "redis"
check_tcp 127.0.0.1 9092 "kafka"
check_tcp 127.0.0.1 8080 "accesshttp"
check_tcp 127.0.0.1 8646 "accessws"
