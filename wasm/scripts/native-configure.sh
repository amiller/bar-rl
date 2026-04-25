#!/bin/bash
# Configure a NATIVE x86_64 build of spring-headless from the same RecoilEngine
# source we use for the WASM build. Lets us compare native-vs-WASM where both
# come from identical source + same -ffp-contract / streflop config — isolating
# whether divergence is source-deterministic or compiler/build-flag-driven.
set -eu
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT="$SCRIPT_DIR/.."
RECOIL="$PROJECT/../repos/RecoilEngine"

[[ -d "$RECOIL" ]] || { echo "no Recoil at $RECOIL"; exit 1; }

# Use the same stubs (DevIL, pr-downloader) as the WASM build, so we don't
# require system DevIL or curl 7.85+. The CMakeLists honors BAR_USE_STUBS
# (added via our local patch) to take the same code path as EMSCRIPTEN.
export BAR_WASM_STUBS="$PROJECT/stubs"
export BAR_USE_STUBS=1

# Apply the same patch stack we use for WASM (idempotent).
PATCHES="$PROJECT/patches"
apply_in() {
    local dir="$1" patch="$2"
    if (cd "$dir" && git apply --reverse --check "$patch" 2>/dev/null); then
        echo "patch already applied: $(basename "$patch")"
    elif (cd "$dir" && git apply "$patch" 2>/dev/null); then
        echo "patch applied: $(basename "$patch")"
    else
        echo "WARN: could not apply $(basename "$patch")"
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

BUILD="$PROJECT/build-native"
mkdir -p "$BUILD"
echo "logging to $BUILD/configure.log"

# Same key flags as WASM where applicable: streflop=ON / SSE / no fp-contract.
# Pure native: no emcmake, real DevIL/SDL2/etc. expected from system.
cmake \
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
    -DCMAKE_CXX_FLAGS="-Wno-error -ffp-contract=off" \
    2>&1 | tee "$BUILD/configure.log" || {
      echo
      echo "=== configure failed ==="
      tail -30 "$BUILD/configure.log"
      exit 2
    }
