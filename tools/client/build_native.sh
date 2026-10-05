#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BINDINGS_COMMIT=507ed9d840c01a3c5b2a39af8bb4000bfac30bf5
BINDINGS_DIR="$REPO_ROOT/vendor/godot-cpp"
BUILD_VENV="$REPO_ROOT/runtime/client-build-venv"
API_DIR="$REPO_ROOT/runtime/client-native-api"
if [[ ! -d "$BINDINGS_DIR/.git" ]]; then
  git clone https://github.com/godotengine/godot-cpp.git "$BINDINGS_DIR"
fi
if [[ "$(git -C "$BINDINGS_DIR" rev-parse HEAD)" != "$BINDINGS_COMMIT" ]]; then
  git -C "$BINDINGS_DIR" fetch origin "$BINDINGS_COMMIT"
  git -C "$BINDINGS_DIR" checkout --detach "$BINDINGS_COMMIT"
fi
if [[ ! -x "$BUILD_VENV/bin/scons" ]]; then
  python3 -m venv "$BUILD_VENV"
  "$BUILD_VENV/bin/pip" install 'scons==4.10.1'
fi
mkdir -p "$API_DIR"
"${GODOT:-godot}" --headless --xr-mode off --audio-driver Dummy --path "$API_DIR" --dump-extension-api
cd "$REPO_ROOT/client/native"
"$BUILD_VENV/bin/scons" platform=linux target=template_debug arch=x86_64 use_static_cpp=no \
  custom_api_file="$API_DIR/extension_api.json" \
  build_profile="$REPO_ROOT/client/native/build_profile.json" \
  -j"${SWG_BUILD_JOBS:-4}" "$@"
# Replace the inode after linking. Existing running clients retain their mapped
# library safely; they receive the new native code on their next launch.
cp bin/build/libswg_native.so bin/libswg_native.so.new
mv -f bin/libswg_native.so.new bin/libswg_native.so
