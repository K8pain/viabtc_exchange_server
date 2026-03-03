#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

cd "$ROOT_DIR"

for dir in network utils matchengine marketprice readhistory accesshttp accessws alertcenter; do
  echo "[build] $dir"
  make -C "$dir"
done

echo "Backend compilation completed"
