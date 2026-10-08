#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
CONTAINER=${SWGXR_CONTAINER:-swgxr-core3-build}
JOBS=${SWGXR_BUILD_JOBS:-12}
mkdir -p "$ROOT/runtime/server"
if [[ -d "$ROOT/runtime/assets/active_tre" ]]; then
  python3 "$ROOT/tools/configure_core3.py"
fi
podman exec "$CONTAINER" bash -lc 'export PATH=/usr/lib/llvm-19/bin:$PATH; cd /workspace/vendor/Core3/MMOCoreORB; cmake -S . -B build/swgxr -G Ninja -DCMAKE_BUILD_TYPE=Release -DCOMPILE_TESTS=OFF -DENABLE_ERROR_ON_WARNINGS=OFF -DENABLE_NATIVE=OFF -DENABLE_BUILD_CLIENT=ON'
podman exec "$CONTAINER" cmake --build /workspace/vendor/Core3/MMOCoreORB/build/swgxr --parallel "$JOBS"

python3 "$ROOT/tools/server/native_build_receipt.py" record
