#!/bin/bash
# Run the WASM-compiled spring-headless on a replay file.
# Usage: wasm-run.sh <replay.sdfz> [seconds-timeout]
#
# Requires:
#   - wasm/build-wasm/spring-headless.{js,wasm} (run scripts/wasm-build.sh)
#   - npm install ws inside build-wasm/ (emscripten socket shim under node)
#   - $BAR_DATA/base symlink to engine/recoil_*/base (so isolation finds it)
#   - state_dump widget enabled in $BAR_DATA/LuaUI/Config/BYAR.lua
#
# Output:
#   Engine log → /tmp/wasm-run.log
#   Per-frame state trace → wasm/traces/<replay-stem>-wasm.jsonl
set -eu
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT="$SCRIPT_DIR/.."
REPLAY="${1:?usage: wasm-run.sh <replay.sdfz> [timeout-sec]}"
TIMEOUT="${2:-600}"
BAR_DATA="$HOME/.local/state/Beyond All Reason"
ENGINE_DIR="$BAR_DATA/engine/recoil_2025.06.19"
WASM="$PROJECT/build-wasm/spring-headless.js"

[[ -f "$WASM" ]]   || { echo "no $WASM (run scripts/wasm-build.sh)"; exit 1; }
[[ -f "$REPLAY" ]] || { echo "no replay at $REPLAY"; exit 1; }

# Make sure 'ws' is installed for emscripten's socket shim under node
if [[ ! -d "$PROJECT/build-wasm/node_modules/ws" ]]; then
    echo "installing ws..."
    (cd "$PROJECT/build-wasm" && npm install ws >/dev/null 2>&1)
fi

# Ensure base/ symlink exists at write-dir so isolation mode finds springcontent.sdz
[[ -e "$BAR_DATA/base" ]] || ln -sfn "$ENGINE_DIR/base" "$BAR_DATA/base"

# shellcheck source=./wasm-env.sh
source "$SCRIPT_DIR/wasm-env.sh" >/dev/null 2>&1

rm -f "$BAR_DATA/state_trace.jsonl" "$BAR_DATA/unit_probe.jsonl"
echo "running ${REPLAY##*/} (timeout ${TIMEOUT}s)..."
cd "$ENGINE_DIR"
timeout "$TIMEOUT" node --max-old-space-size=8192 "$WASM" \
    --write-dir "$BAR_DATA" \
    --isolation=true \
    "$REPLAY" \
    | tee /tmp/wasm-run.log
echo "---"
LAST_F=$(grep -oE "\[f=[0-9]+\]" /tmp/wasm-run.log | grep -v "f=-" | tail -1)
echo "last sim frame: ${LAST_F:-none}"
if [[ -s "$BAR_DATA/state_trace.jsonl" ]]; then
    OUT_NAME="$(basename "$REPLAY" .sdfz)-wasm"
    DEST="$PROJECT/traces/${OUT_NAME}.jsonl"
    mkdir -p "$PROJECT/traces"
    mv "$BAR_DATA/state_trace.jsonl" "$DEST"
    echo "trace: $DEST  ($(wc -l < "$DEST") lines, $(du -h "$DEST" | cut -f1))"
fi
if [[ -s "$BAR_DATA/unit_probe.jsonl" ]]; then
    OUT_NAME="$(basename "$REPLAY" .sdfz)-wasm"
    DEST="$PROJECT/traces/${OUT_NAME}.probe.jsonl"
    mv "$BAR_DATA/unit_probe.jsonl" "$DEST"
    echo "probe: $DEST  ($(wc -l < "$DEST") lines)"
fi
if [[ -s "$BAR_DATA/outcome.jsonl" ]]; then
    OUT_NAME="$(basename "$REPLAY" .sdfz)-wasm"
    DEST="$PROJECT/traces/${OUT_NAME}.outcome.jsonl"
    mv "$BAR_DATA/outcome.jsonl" "$DEST"
    echo "outcome: $DEST"
fi
# /DumpState output (ReplayGameState-*.txt) — collect any present.
OUT_NAME="$(basename "$REPLAY" .sdfz)-wasm"
DUMP_DEST="$PROJECT/traces/${OUT_NAME}.dumpstates"
mkdir -p "$DUMP_DEST"
found_dump=0
for dumpf in "$ENGINE_DIR"/ReplayGameState-*.txt "$BAR_DATA"/ReplayGameState-*.txt; do
    [[ -e "$dumpf" ]] || continue
    mv "$dumpf" "$DUMP_DEST/"
    found_dump=$((found_dump + 1))
done
if (( found_dump > 0 )); then
    echo "dumpstates: $DUMP_DEST ($found_dump files)"
else
    rmdir "$DUMP_DEST" 2>/dev/null
fi
