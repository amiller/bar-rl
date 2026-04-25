#!/bin/bash
# WASM configure step pointing at the 2025.06.19 worktree (so the resulting
# WASM binary matches the engine that recorded the demos).
set -eu
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT="$( cd "$SCRIPT_DIR/.." && pwd )"
RECOIL="$( cd "$PROJECT/../repos/RecoilEngine-2025.06.19" && pwd )"
BUILD="$PROJECT/build-wasm-2025.06.19"

source "$SCRIPT_DIR/wasm-env.sh"

export BAR_WASM_STUBS="$PROJECT/stubs"

[[ -d "$RECOIL" ]] || { echo "no Recoil worktree at $RECOIL"; exit 1; }

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
    -DCMAKE_EXE_LINKER_FLAGS="-sINITIAL_MEMORY=128MB -sALLOW_MEMORY_GROWTH=1 -sMAXIMUM_MEMORY=4GB -sSTACK_SIZE=8MB -sUSE_PTHREADS=0 -sNODERAWFS=1 -sEXIT_RUNTIME=1 -sASSERTIONS=1 -g1 -fexceptions" \
    -DCMAKE_CXX_FLAGS="-Wno-error -fexceptions -include cstdlib -include cmath -ffp-contract=off" \
    2>&1 | tee "$BUILD/configure.log" || {
      echo
      echo "=== configure failed ==="
      tail -30 "$BUILD/configure.log"
      exit 2
    }
