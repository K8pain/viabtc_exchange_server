#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"
load_env

mysql -h"$LAB_MYSQL_HOST" -P"$LAB_MYSQL_PORT" -u"$LAB_MYSQL_USER" -p"$LAB_MYSQL_PASSWORD" "$LAB_MYSQL_DB" < "$MVP_DIR/sql/bootstrap.sql"
echo "bootstrap_db.sh completed"
