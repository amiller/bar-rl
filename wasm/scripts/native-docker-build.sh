#!/bin/bash
# Build native spring-headless inside ubuntu:24.04 (gcc-13 with std::format).
# Mounts the Recoil source + a build-native-docker dir; emits ELF that pairs
# with the WASM binary (same source HEAD), so /DumpState output is comparable.
set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT="$( cd "$SCRIPT_DIR/.." && pwd )"
RECOIL="$( cd "$PROJECT/../repos/RecoilEngine" && pwd )"
BUILD="$PROJECT/build-native-docker"
IMAGE="bar-native-build:gcc13"

[[ -d "$RECOIL" ]] || { echo "no Recoil at $RECOIL"; exit 1; }
mkdir -p "$BUILD"

# Build image (cached by Docker layer).
docker build \
    --build-arg UID="$(id -u)" --build-arg GID="$(id -g)" \
    -t "$IMAGE" -f "$PROJECT/docker/Dockerfile.native" "$PROJECT/docker"

JOBS="${JOBS:-$(nproc)}"
TARGET="${1:-engine-headless}"

# Mount paths must match host paths so cmake's absolute include dirs stay valid.
docker run --rm \
    -v "$RECOIL:$RECOIL" \
    -v "$BUILD:$BUILD" \
    -v "$PROJECT/stubs:$PROJECT/stubs:ro" \
    -e BAR_WASM_STUBS="$PROJECT/stubs" \
    -e BAR_USE_STUBS=1 \
    -e CI=1 \
    -w "$BUILD" \
    "$IMAGE" \
    bash -c "
        set -e
        if [[ ! -f CMakeCache.txt ]]; then
            cmake -S '$RECOIL' -B '$BUILD' \
                -G Ninja \
                -DCMAKE_BUILD_TYPE=Release \
                -DBUILD_DEDICATED=OFF \
                -DBUILD_SPRING=OFF \
                -DAI_TYPES=NONE \
                -DINSTALL_PORTABLE=OFF \
                -DENABLE_STREFLOP=ON \
                -DSTREFLOP_SSE=ON \
                -DSTREFLOP_AUTO=OFF \
                -DBUILD_TESTING=OFF \
                -DLTO=OFF \
                -DUSE_MIMALLOC=OFF \
                -DNO_SOUND=ON \
                -DCMAKE_CXX_FLAGS='-Wno-error -ffp-contract=off'
        fi
        cmake --build '$BUILD' -j '$JOBS' --target '$TARGET'
    " 2>&1 | tee "$BUILD/build.log"

if [[ -x "$BUILD/spring-headless" ]]; then
    echo
    echo "built: $BUILD/spring-headless"
    file "$BUILD/spring-headless" | head -1
else
    echo "WARN: spring-headless not produced"
    exit 2
fi
