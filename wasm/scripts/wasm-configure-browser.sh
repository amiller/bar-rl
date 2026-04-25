#!/bin/bash
# Browser-targeted WASM build of the 2025.06.19 engine. Differences vs.
# wasm-configure-tag.sh (which targets Node.js):
#   - drop -sNODERAWFS=1 (browser has no host fs); use MEMFS instead
#   - -sFORCE_FILESYSTEM=1 so FS module is exposed to JS
#   - -sEXPORTED_RUNTIME_METHODS includes FS, callMain, ENV, ccall
#   - -sMODULARIZE=1 + -sEXPORT_NAME=createSpring so the JS shell can do
#     `const Module = await createSpring({ ... })` instead of the global
#     auto-init (so we can wire the FS, plant the demo, then call _main)
set -eu
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT="$( cd "$SCRIPT_DIR/.." && pwd )"
RECOIL="$( cd "$PROJECT/../repos/RecoilEngine-2025.06.19" && pwd )"
BUILD="$PROJECT/build-wasm-browser"

source "$SCRIPT_DIR/wasm-env.sh"
export BAR_WASM_STUBS="$PROJECT/stubs"

mkdir -p "$BUILD"
echo "logging to $BUILD/configure.log"

emcmake cmake \
    -S "$RECOIL" \
    -B "$BUILD" \
    -DCMAKE_BUILD_TYPE=Release \
    -DHEADLESS_SYSTEM=ON \
    -DBUILD_DEDICATED=OFF \
    -DBUILD_SPRING=OFF \
    -DBUILD_spring-dedicated=OFF \
    -DAI_TYPES=NONE \
    -DINSTALL_PORTABLE=OFF \
    -DENABLE_STREFLOP=ON \
    -DSTREFLOP_SSE=ON \
    -DSTREFLOP_AUTO=OFF \
    -DGFLAGS_INTTYPES_FORMAT=C99 \
    -DBUILD_gflags_LIBS=OFF \
    -DBUILD_TESTING=OFF \
    -DLTO=OFF \
    -DUSE_MIMALLOC=OFF \
    -DNO_SOUND=ON \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
    -DCMAKE_EXE_LINKER_FLAGS="-sINITIAL_MEMORY=128MB -sALLOW_MEMORY_GROWTH=1 -sMAXIMUM_MEMORY=4GB -sSTACK_SIZE=8MB -sUSE_PTHREADS=0 -sEXIT_RUNTIME=1 -sASSERTIONS=1 -g1 -fexceptions -sFORCE_FILESYSTEM=1 -sEXPORTED_RUNTIME_METHODS=['FS','callMain','ccall','ENV'] -sINVOKE_RUN=0 -sMODULARIZE=1 -sEXPORT_NAME=createSpring -sENVIRONMENT=web,worker" \
    -DCMAKE_CXX_FLAGS="-Wno-error -fexceptions -include cstdlib -include cmath -ffp-contract=off" \
    2>&1 | tee "$BUILD/configure.log" || {
      echo
      echo "=== configure failed ==="
      tail -30 "$BUILD/configure.log"
      exit 2
    }
