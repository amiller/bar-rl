#!/bin/bash
# First-attempt WASM configure step. Will fail — the purpose is to surface
# which dependencies/platform checks break so we can address them one at a time.
# Logs the full error surface to build-wasm/configure.log.
set -eu
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT="$SCRIPT_DIR/.."
RECOIL="$PROJECT/../repos/RecoilEngine"

# shellcheck source=./wasm-env.sh
source "$SCRIPT_DIR/wasm-env.sh"

# Point Recoil's CMake at our bundled stubs (DevIL, maybe more over time)
export BAR_WASM_STUBS="$PROJECT/stubs"

[[ -d "$RECOIL" ]] || { echo "no Recoil at $RECOIL — did you sparse-clone it?"; exit 1; }

# Apply stacked patches (idempotent — skips if already applied).
# `002-streflop-*.patch` targets a submodule tree; apply it inside that submodule.
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
            *)              apply_in "$RECOIL" "$p" ;;
        esac
    done
fi

BUILD="$PROJECT/build-wasm"
mkdir -p "$BUILD"
echo "logging to $BUILD/configure.log"

# Start minimal: headless only, no graphics/audio/network. Shim OFF-by-default options.
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
    -DENABLE_STREFLOP=OFF \
    -DSTREFLOP_SSE=OFF \
    -DGFLAGS_INTTYPES_FORMAT=C99 \
    -DBUILD_gflags_LIBS=OFF \
    -DBUILD_TESTING=OFF \
    -DLTO=OFF \
    -DUSE_MIMALLOC=OFF \
    -DNO_SOUND=ON \
    -DCMAKE_EXE_LINKER_FLAGS="-sINITIAL_MEMORY=128MB -sALLOW_MEMORY_GROWTH=1 -sMAXIMUM_MEMORY=4GB -sSTACK_SIZE=8MB -sUSE_PTHREADS=0 -sNODERAWFS=1 -sEXIT_RUNTIME=1 -sASSERTIONS=1 -g1 -fexceptions" \
    -DCMAKE_CXX_FLAGS="-Wno-error -fexceptions -include cstdlib -include cmath" \
    2>&1 | tee "$BUILD/configure.log" || {
      echo
      echo "=== configure failed (expected on first try) ==="
      echo "tail of configure.log:"; tail -30 "$BUILD/configure.log"
      exit 2
    }
