#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
CONTAINER=${SWGXR_CONTAINER:-swgxr-core3-build}
if [[ ! -x "$ROOT/vendor/Core3/MMOCoreORB/bin/core3" ]]; then
  echo "Core3 binary missing; run tools/server/provision.sh first." >&2
  exit 1
fi
python3 "$ROOT/tools/configure_core3.py"
"$ROOT/tools/server/init-db.sh"
if podman exec "$CONTAINER" bash -lc 'test -f /workspace/runtime/server/core3.pid && p=$(cat /workspace/runtime/server/core3.pid) && test -r /proc/$p/status && ! grep -q "State:.*Z" /proc/$p/status && test "$(cat /proc/$p/comm)" = core3 && kill -0 "$p" 2>/dev/null'; then
  echo 'Core3 process is already running.'
  exit 0
fi
podman exec -d -e SWGXR_GROUND_ACTIONS="${SWGXR_GROUND_ACTIONS:-off}" -e SWGXR_ACTION_COMBAT_PROTOTYPE="${SWGXR_ACTION_COMBAT_PROTOTYPE:-0}" "$CONTAINER" bash -lc '
set -euo pipefail
# A previous graceful shutdown may still be saving/clearing zones. Never open
# the same Berkeley DB environment from a replacement server concurrently.
if pgrep -x core3 >/dev/null || pgrep -x corecu >/dev/null; then
  echo "CoreCU is still running or shutting down; wait for it to exit." >&2
  exit 1
fi
cd /workspace/vendor/Core3/MMOCoreORB/bin
mkdir -p /workspace/runtime/server
[[ -p /workspace/runtime/server/core3-console ]] || mkfifo /workspace/runtime/server/core3-console
if [[ -f /workspace/runtime/server/core3-console.log ]]; then
  cp /workspace/runtime/server/core3-console.log /workspace/runtime/server/core3-console.$(date -u +%Y%m%dT%H%M%SZ).log
fi
exec 3<>/workspace/runtime/server/core3-console
echo $$ >/workspace/runtime/server/core3.pid
exec ./core3 <&3 >/workspace/runtime/server/core3-console.log 2>&1
'
echo 'Core3 started inside isolated container; inspect runtime/server/core3-console.log and GET /health.'
