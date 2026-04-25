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

# Apply stacked patches against the worktree (idempotent: --reverse --check
# first to skip already-applied ones). Patches that target submodule trees go
# inside the submodule. 004-cob-* is the desync fix (short(float) cast UB).
PATCHES="$PROJECT/patches"
apply_in() {
    local dir="$1" patch="$2"
    if (cd "$dir" && git apply --reverse --check "$patch" 2>/dev/null); then
        echo "patch already applied: $(basename "$patch")"
    elif (cd "$dir" && git apply "$patch" 2>/dev/null); then
        echo "patch applied: $(basename "$patch")"
    else
        echo "WARN: could not apply $(basename "$patch") in $dir"
    fi
}
if [[ -d "$PATCHES" ]]; then
    for p in "$PATCHES"/*.patch; do
        [[ -e "$p" ]] || continue
        case "$(basename "$p")" in
            002-streflop-*) apply_in "$RECOIL/rts/lib/streflop" "$p" ;;
            003-streflop-*) apply_in "$RECOIL/rts/lib/streflop" "$p" ;;
            *)              apply_in "$RECOIL" "$p" ;;
        esac
    done
fi

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
