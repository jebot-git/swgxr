#!/usr/bin/env bash
set -euo pipefail
CONTAINER=${SWGXR_CONTAINER:-swgxr-core3-build}
podman exec "$CONTAINER" bash -lc '
if [[ -f /workspace/runtime/server/core3.pid ]] && p=$(cat /workspace/runtime/server/core3.pid) && [[ -r /proc/$p/status ]] && ! grep -q "State:.*Z" /proc/$p/status && [[ "$(cat /proc/$p/comm)" == core3 ]] && kill -0 "$p" 2>/dev/null; then
  timeout 3 bash -c '\''printf "exit\n" >/workspace/runtime/server/core3-console'\''
  echo "Graceful save-and-exit requested. Database and container are left running."
else
  echo "Core3 is not running."
fi
'
