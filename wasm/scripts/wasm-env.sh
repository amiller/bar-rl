#!/bin/bash
# Source to put emcc/em++/emcmake on PATH for this shell.
# Usage: . scripts/wasm-env.sh
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
EMSDK_ROOT="$SCRIPT_DIR/../tools/emsdk"
# shellcheck disable=SC1091
source "$EMSDK_ROOT/emsdk_env.sh" >/dev/null
echo "emcc: $(emcc --version | head -1)"
