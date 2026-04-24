#!/bin/bash
# Build the WASM engine. Expects `wasm-configure.sh` already ran cleanly.
set -eu
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT="$SCRIPT_DIR/.."
BUILD="$PROJECT/build-wasm"

source "$SCRIPT_DIR/wasm-env.sh"
export BAR_WASM_STUBS="$PROJECT/stubs"
export CI=1  # skips Recoil's `git describe` version-format check (sparse clones fail it)

[[ -f "$BUILD/CMakeCache.txt" ]] || { echo "no build tree — run wasm-configure.sh first"; exit 1; }

TARGET="${1:-engine-headless}"
JOBS="${JOBS:-$(nproc)}"
echo "building $TARGET with $JOBS jobs"
emmake make -C "$BUILD" -j"$JOBS" "$TARGET" 2>&1 | tee "$BUILD/build.log"
