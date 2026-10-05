#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
CONTAINER=${SWGXR_CONTAINER:-swgxr-core3-build}
mkdir -p "$ROOT/vendor" "$ROOT/runtime/server"
if [[ ! -d "$ROOT/vendor/Core3/.git" ]]; then
  git clone https://github.com/swgemu/Core3.git "$ROOT/vendor/Core3"
  git -C "$ROOT/vendor/Core3" checkout 403893d9b9f8e6fa712fbb3cb1fcd8f0fe45bb79
fi
CURRENT_REV=$(git -C "$ROOT/vendor/Core3" rev-parse HEAD)
if [[ "$CURRENT_REV" != "403893d9b9f8e6fa712fbb3cb1fcd8f0fe45bb79" ]]; then
  echo "Core3 revision differs from server/upstream.json; preserving checkout and stopping." >&2
  exit 1
fi
git -C "$ROOT/vendor/Core3" submodule update --init --recursive
if ! podman container exists "$CONTAINER"; then
  podman run -d --name "$CONTAINER" -v "$ROOT:/workspace:Z" docker.io/library/debian:trixie sleep infinity
fi
podman start "$CONTAINER" >/dev/null
podman exec "$CONTAINER" bash -lc 'apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends build-essential clang-19 lld-19 libmariadb-dev libmariadb-dev-compat liblua5.3-dev libdb5.3-dev libssl-dev cmake git default-jre-headless libboost-all-dev ninja-build libjemalloc-dev mariadb-server zlib1g-dev ca-certificates'
"$ROOT/tools/server/build.sh"
