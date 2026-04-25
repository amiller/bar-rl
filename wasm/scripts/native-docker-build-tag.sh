#!/bin/bash
# Build native spring-headless from the upstream 2025.06.19 tag (worktree at
# repos/RecoilEngine-2025.06.19) — the same engine version the BarR demo
# reports as its recording engine. Tests whether upstream-tag-built engine
# matches the demo's recorded sync checksums.
set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT="$( cd "$SCRIPT_DIR/.." && pwd )"
RECOIL="$( cd "$PROJECT/../repos/RecoilEngine-2025.06.19" && pwd )"
BUILD="$PROJECT/build-native-2025.06.19"
IMAGE="bar-native-build:gcc13"

[[ -d "$RECOIL" ]] || { echo "no worktree at $RECOIL"; exit 1; }
mkdir -p "$BUILD"

# Apply stacked patches against the worktree (host-side, before the docker
# build sees it). Mirrors wasm-configure-tag.sh so a clean checkout produces
# a fix-patched binary on first build.
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

JOBS="${JOBS:-$(nproc)}"
TARGET="${1:-engine-headless}"

# Worktree's .git is a pointer to the parent repo's .git/worktrees/... — mount
# the parent .git too so `git describe` works for the engine version stamp.
PARENT_GIT="$( cd "$PROJECT/../repos/RecoilEngine/.git" && pwd )"

docker run --rm \
    -v "$RECOIL:$RECOIL" \
    -v "$PARENT_GIT:$PARENT_GIT:ro" \
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
else
    echo "WARN: spring-headless not produced"
    exit 2
fi
