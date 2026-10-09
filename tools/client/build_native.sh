#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BINDINGS_COMMIT=507ed9d840c01a3c5b2a39af8bb4000bfac30bf5
BINDINGS_DIR="$REPO_ROOT/vendor/godot-cpp"
BUILD_VENV="$REPO_ROOT/runtime/client-build-venv"
API_DIR="$REPO_ROOT/runtime/client-native-api"
NATIVE_PLATFORM="${SWG_NATIVE_PLATFORM:-linux}"
NATIVE_TARGET="${SWG_NATIVE_TARGET:-template_debug}"
NATIVE_ARCH=x86_64
NATIVE_OFFLINE=0
NATIVE_ARGS=()
for argument in "$@"; do
  case "$argument" in
    --offline) NATIVE_OFFLINE=1 ;;
    platform=*) NATIVE_PLATFORM="${argument#platform=}" ;;
    target=*) NATIVE_TARGET="${argument#target=}" ;;
    arch=*) NATIVE_ARCH="${argument#arch=}" ;;
    -h|--help)
      echo 'Usage: tools/client/build_native.sh [--offline] platform=linux|windows target=template_debug|template_release [SCons options]'
      echo 'Windows: install x86_64-w64-mingw32 GCC/binutils (or LLVM-MinGW with use_llvm=yes); set MINGW_PREFIX for a non-PATH SDK.'
      echo '--offline refuses to download bindings or SCons; it does not launch the VR client.'
      exit 0 ;;
    *) NATIVE_ARGS+=("$argument") ;;
  esac
done
case "$NATIVE_PLATFORM/$NATIVE_ARCH" in
  linux/x86_64) NATIVE_LIBRARY=libswg_native.so; NATIVE_STATIC_CPP=no ;;
  windows/x86_64) NATIVE_LIBRARY=libswg_native.dll; NATIVE_STATIC_CPP=yes ;;
  *) echo "Unsupported native target: $NATIVE_PLATFORM/$NATIVE_ARCH (Linux and Windows x86_64 only)." >&2; exit 2 ;;
esac
case "$NATIVE_TARGET" in template_debug|template_release) ;; *) echo "Unsupported native configuration: $NATIVE_TARGET" >&2; exit 2 ;; esac
if [[ "$NATIVE_PLATFORM" == windows ]]; then
  NATIVE_MINGW_PREFIX="${MINGW_PREFIX:-}"
  NATIVE_LLVM=0
  for argument in "${NATIVE_ARGS[@]}"; do
    case "$argument" in
      mingw_prefix=*) NATIVE_MINGW_PREFIX="${argument#mingw_prefix=}" ;;
      use_llvm=yes|use_llvm=true|use_llvm=1) NATIVE_LLVM=1 ;;
    esac
  done
  NATIVE_COMPILER=x86_64-w64-mingw32-g++
  if [[ "$NATIVE_LLVM" == 1 ]]; then NATIVE_COMPILER=x86_64-w64-mingw32-clang++; fi
  if [[ -n "$NATIVE_MINGW_PREFIX" ]]; then NATIVE_COMPILER="$NATIVE_MINGW_PREFIX/bin/$NATIVE_COMPILER"; fi
  if ! command -v "$NATIVE_COMPILER" >/dev/null 2>&1; then
    echo "Windows native build blocked: missing $NATIVE_COMPILER and its matching Windows headers/CRT/C++ libraries." >&2
    echo 'Install a complete x86_64 MinGW-w64 toolchain, then rerun this exact command. A host Linux clang installation is insufficient.' >&2
    exit 2
  fi
fi
if [[ ! -d "$BINDINGS_DIR/.git" ]]; then
  if [[ "$NATIVE_OFFLINE" == 1 ]]; then echo "Offline build requires pinned godot-cpp at $BINDINGS_DIR" >&2; exit 2; fi
  git clone https://github.com/godotengine/godot-cpp.git "$BINDINGS_DIR"
fi
if [[ "$(git -C "$BINDINGS_DIR" rev-parse HEAD)" != "$BINDINGS_COMMIT" ]]; then
  if [[ "$NATIVE_OFFLINE" == 1 ]]; then echo "Offline build requires godot-cpp revision $BINDINGS_COMMIT" >&2; exit 2; fi
  git -C "$BINDINGS_DIR" fetch origin "$BINDINGS_COMMIT"
  git -C "$BINDINGS_DIR" checkout --detach "$BINDINGS_COMMIT"
fi
if [[ ! -x "$BUILD_VENV/bin/scons" ]]; then
  if [[ "$NATIVE_OFFLINE" == 1 ]]; then echo "Offline build requires SCons 4.10.1 in $BUILD_VENV" >&2; exit 2; fi
  python3 -m venv "$BUILD_VENV"
  "$BUILD_VENV/bin/pip" install 'scons==4.10.1'
fi
mkdir -p "$API_DIR"
"${GODOT:-godot}" --headless --xr-mode off --audio-driver Dummy --path "$API_DIR" --dump-extension-api
cd "$REPO_ROOT/client/native"
"$BUILD_VENV/bin/scons" platform="$NATIVE_PLATFORM" target="$NATIVE_TARGET" arch="$NATIVE_ARCH" use_static_cpp="$NATIVE_STATIC_CPP" \
  custom_api_file="$API_DIR/extension_api.json" \
  build_profile="$REPO_ROOT/client/native/build_profile.json" \
  -j"${SWG_BUILD_JOBS:-4}" "${NATIVE_ARGS[@]}"
# Replace the inode after linking. Existing running clients retain their mapped
# library safely; they receive the new native code on their next launch.
cp "bin/build/$NATIVE_LIBRARY" "bin/$NATIVE_LIBRARY.new"
mv -f "bin/$NATIVE_LIBRARY.new" "bin/$NATIVE_LIBRARY"
