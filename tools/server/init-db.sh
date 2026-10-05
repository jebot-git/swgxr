#!/usr/bin/env bash
set -euo pipefail
CONTAINER=${SWGXR_CONTAINER:-swgxr-core3-build}
podman exec "$CONTAINER" bash -lc '
set -euo pipefail
mkdir -p /workspace/runtime/server/mysql
if [[ ! -d /workspace/runtime/server/mysql/mysql ]]; then
  mariadb-install-db --user=root --datadir=/workspace/runtime/server/mysql >/workspace/runtime/server/mysql-init.log
fi
if ! mariadb-admin --socket=/workspace/runtime/server/mysql.sock ping >/dev/null 2>&1; then
  mariadbd --user=root --datadir=/workspace/runtime/server/mysql --socket=/workspace/runtime/server/mysql.sock --pid-file=/workspace/runtime/server/mysql.pid --bind-address=127.0.0.1 --log-error=/workspace/runtime/server/mysql.log &
  for count in $(seq 1 40); do
    mariadb-admin --socket=/workspace/runtime/server/mysql.sock ping >/dev/null 2>&1 && break
    sleep 0.5
  done
fi
if ! mariadb --socket=/workspace/runtime/server/mysql.sock -N -e "SELECT SCHEMA_NAME FROM information_schema.SCHEMATA WHERE SCHEMA_NAME = '\''swgemu'\''" | grep -qx swgemu; then
  mariadb --socket=/workspace/runtime/server/mysql.sock < /workspace/vendor/Core3/MMOCoreORB/sql/swgemu.sql
fi
mariadb --socket=/workspace/runtime/server/mysql.sock <<SQL
CREATE USER IF NOT EXISTS '\''swgemu'\''@'\''localhost'\'' IDENTIFIED BY '\''123456'\'';
CREATE USER IF NOT EXISTS '\''swgemu'\''@'\''127.0.0.1'\'' IDENTIFIED BY '\''123456'\'';
GRANT ALL PRIVILEGES ON swgemu.* TO '\''swgemu'\''@'\''localhost'\'';
GRANT ALL PRIVILEGES ON swgemu.* TO '\''swgemu'\''@'\''127.0.0.1'\'';
UPDATE swgemu.galaxy SET name='\''SWGXR Local'\'', address='\''127.0.0.1'\'' WHERE galaxy_id=2;
SQL
'
