#!/bin/bash
# Build the native engine. Expects native-configure.sh has been run.
set -eu
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT="$SCRIPT_DIR/.."
BUILD="$PROJECT/build-native"

[[ -f "$BUILD/CMakeCache.txt" ]] || { echo "no build tree — run native-configure.sh first"; exit 1; }

TARGET="${1:-engine-headless}"
JOBS="${JOBS:-$(nproc)}"
echo "building $TARGET with $JOBS jobs"
make -C "$BUILD" -j"$JOBS" "$TARGET" 2>&1 | tee "$BUILD/build.log"
