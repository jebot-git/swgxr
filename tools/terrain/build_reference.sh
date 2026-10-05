#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
mkdir -p "$ROOT/runtime/terrain"
podman exec "${SWGXR_CONTAINER:-swgxr-core3-build}" bash -c '
cd /workspace/vendor/Core3/MMOCoreORB
/usr/lib/llvm-19/bin/clang++ -std=gnu++14 -O2 -DNDEBUG -DDEFAULT_DYNAMIC_CAST -DODB_REFERENCES -Wno-multichar \
-Iutils/engine3/MMOEngine/src -Isrc -Isrc/autogen -Iutils -I/usr/include/lua5.3 -I/usr/include/mysql \
/workspace/tools/terrain/core3_height_reference.cpp \
build/swgxr/src/terrain/libcore3terrain.a build/swgxr/src/templates/libcore3templates.a \
build/swgxr/src/CMakeFiles/core3.dir/tre3/TreeFile.cpp.o \
utils/engine3/MMOEngine/lib/unix/libengine3.a \
-lboost_thread -lboost_atomic -lboost_program_options -latomic -lmysqlclient -llua5.3 -lm -ldb-5.3 -lssl -lcrypto -lz -ldl -ljemalloc -pthread \
-o /workspace/runtime/terrain/core3_height_reference'
