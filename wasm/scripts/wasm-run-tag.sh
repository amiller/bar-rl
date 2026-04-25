#!/bin/bash
# Run the 2025.06.19-tag-built WASM spring-headless on a replay file.
# This binary should match the demo's recorded sync checksums (zero DESYNC).
set -eu
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT="$( cd "$SCRIPT_DIR/.." && pwd )"
REPLAY="${1:?usage: wasm-run-tag.sh <replay.sdfz> [timeout-sec]}"
TIMEOUT="${2:-1500}"
BAR_DATA="$HOME/.local/state/Beyond All Reason"
ENGINE_DIR="$BAR_DATA/engine/recoil_2025.06.19"
WASM="$PROJECT/build-wasm-2025.06.19/spring-headless.js"

[[ -f "$WASM" ]]   || { echo "no $WASM (run wasm-configure-tag.sh + build)"; exit 1; }
[[ -f "$REPLAY" ]] || { echo "no replay at $REPLAY"; exit 1; }

# 'ws' for emscripten socket shim under node
if [[ ! -d "$PROJECT/build-wasm-2025.06.19/node_modules/ws" ]]; then
    (cd "$PROJECT/build-wasm-2025.06.19" && npm install ws >/dev/null 2>&1)
fi
[[ -e "$BAR_DATA/base" ]] || ln -sfn "$ENGINE_DIR/base" "$BAR_DATA/base"

source "$SCRIPT_DIR/wasm-env.sh" >/dev/null 2>&1
rm -f "$BAR_DATA/state_trace.jsonl" "$BAR_DATA/unit_probe.jsonl" "$BAR_DATA/outcome.jsonl" "$BAR_DATA/interactions.jsonl"
echo "running ${REPLAY##*/} (timeout ${TIMEOUT}s) with WASM-2025.06.19..."
cd "$ENGINE_DIR"
timeout "$TIMEOUT" node --max-old-space-size=8192 "$WASM" \
    --write-dir "$BAR_DATA" \
    --isolation=true \
    "$REPLAY" \
    | tee /tmp/wasm-tag-run.log
echo "---"
LAST_F=$(grep -oE "\[f=[0-9]+\]" /tmp/wasm-tag-run.log | grep -v "f=-" | tail -1)
echo "last sim frame: ${LAST_F:-none}"
DESYNC_COUNT=$(grep -c "DESYNC WARNING" /tmp/wasm-tag-run.log 2>/dev/null || echo 0)
echo "desync_warnings: $DESYNC_COUNT"
[[ "$DESYNC_COUNT" -gt 0 ]] && grep "DESYNC WARNING" /tmp/wasm-tag-run.log | head -3

OUT_NAME="$(basename "$REPLAY" .sdfz)-wasm-2025.06.19"
DEST_DIR="$PROJECT/traces"; mkdir -p "$DEST_DIR"
[[ -s "$BAR_DATA/state_trace.jsonl" ]]  && mv "$BAR_DATA/state_trace.jsonl"  "$DEST_DIR/${OUT_NAME}.jsonl"  && echo "trace: $DEST_DIR/${OUT_NAME}.jsonl"
[[ -s "$BAR_DATA/unit_probe.jsonl" ]]   && mv "$BAR_DATA/unit_probe.jsonl"   "$DEST_DIR/${OUT_NAME}.probe.jsonl"
[[ -s "$BAR_DATA/outcome.jsonl" ]]      && mv "$BAR_DATA/outcome.jsonl"      "$DEST_DIR/${OUT_NAME}.outcome.jsonl"
[[ -s "$BAR_DATA/interactions.jsonl" ]] && mv "$BAR_DATA/interactions.jsonl" "$DEST_DIR/${OUT_NAME}.interactions.jsonl"
gzip -c /tmp/wasm-tag-run.log > "$DEST_DIR/${OUT_NAME}.infolog.gz"
DD="$DEST_DIR/${OUT_NAME}.dumpstates"; mkdir -p "$DD"; n=0
for f in "$ENGINE_DIR"/ReplayGameState-*.txt "$BAR_DATA"/ReplayGameState-*.txt "$ENGINE_DIR"/ServerGameState-*.txt; do
    [[ -e "$f" ]] || continue; mv "$f" "$DD/"; n=$((n+1))
done
[[ $n -gt 0 ]] && echo "dumpstates: $DD ($n files)" || rmdir "$DD" 2>/dev/null
echo "done."
