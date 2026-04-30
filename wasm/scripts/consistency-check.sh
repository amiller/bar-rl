#!/bin/bash
# Run a single .sdfz through both engines and diff.
# Native runs in docker (no host engine required); wasm uses node.
#
#   bash consistency-check.sh <replay.sdfz> [tag]
#
# Outputs:
#   traces/<tag>-native.{jsonl,outcome.jsonl,probe.jsonl,dumpstates/}
#   traces/<tag>-wasm.{jsonl,outcome.jsonl,probe.jsonl,dumpstates/}
#   /tmp/<tag>.consistency.txt   — diff summary (pasteable)
#
# Exit code: 0 = winners agree AND first state-trace diverging frame > 1500
#            1 = winners disagree OR diverges before frame 1500
#            2 = either run failed to produce a trace
set -eu
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT="$SCRIPT_DIR/.."
REPLAY="${1:?usage: consistency-check.sh <replay.sdfz> [tag]}"
TAG="${2:-$(basename "$REPLAY" .sdfz)}"
TRACES="$PROJECT/traces"
SUMMARY="/tmp/${TAG}.consistency.txt"
mkdir -p "$TRACES"
: > "$SUMMARY"

run_native() {
  local out="${TAG}-native"
  if [[ -f "$TRACES/$out.jsonl" && "${REUSE:-0}" = 1 ]]; then
    echo "[native] reusing $TRACES/$out.jsonl"; return 0
  fi
  echo "[native] running in docker..."
  bash "$SCRIPT_DIR/native-docker-run.sh" "$REPLAY" "$out"
}

run_wasm() {
  if [[ -f "$TRACES/${TAG}-wasm.jsonl" && "${REUSE:-0}" = 1 ]]; then
    echo "[wasm] reusing"; return 0
  fi
  echo "[wasm] running..."
  bash "$SCRIPT_DIR/wasm-run.sh" "$REPLAY"
  # wasm-run names output as "<basename>-wasm.jsonl"; rename to our tag.
  local stem="$(basename "$REPLAY" .sdfz)"
  for ext in jsonl outcome.jsonl probe.jsonl interactions.jsonl; do
    local src="$TRACES/${stem}-wasm.$ext"
    [[ -f "$src" && "$src" != "$TRACES/${TAG}-wasm.$ext" ]] && mv "$src" "$TRACES/${TAG}-wasm.$ext" || true
  done
}

run_native
run_wasm

NATIVE_J="$TRACES/${TAG}-native.jsonl"
WASM_J="$TRACES/${TAG}-wasm.jsonl"
NATIVE_O="$TRACES/${TAG}-native.outcome.jsonl"
WASM_O="$TRACES/${TAG}-wasm.outcome.jsonl"

[[ -s "$NATIVE_J" && -s "$WASM_J" ]] || { echo "missing trace(s)" | tee -a "$SUMMARY"; exit 2; }

{
  echo "=== consistency-check ${TAG} ($(date -Iseconds)) ==="
  echo "replay: $REPLAY"
  echo
  echo "--- compare-outcomes ---"
  if [[ -s "$NATIVE_O" && -s "$WASM_O" ]]; then
    python3 "$SCRIPT_DIR/compare-outcomes.py" "$NATIVE_O" "$WASM_O" 2>&1 | tail -25
  else
    echo "(no outcome.jsonl on one side — Outcome Recorder widget didn't fire?)"
  fi
  echo
  echo "--- diff-traces (per-frame unit positions) ---"
  python3 "$SCRIPT_DIR/diff-traces.py" "$NATIVE_J" "$WASM_J" 2>&1 | head -20
  echo
  echo "--- dumpstate hash sample ---"
  for d in "$TRACES/${TAG}-native.dumpstates" "$TRACES/${TAG}-wasm.dumpstates"; do
    [[ -d "$d" ]] || continue
    echo "  $d:"
    ls "$d" | sort | head -5 | sed 's/^/    /'
  done
} | tee "$SUMMARY"

# Pass/fail signal: parse compare-outcomes for "winners match" and diff-traces
# for first divergence frame.
WIN_OK=0; FRAME_OK=0
grep -q "winners match" "$SUMMARY" && WIN_OK=1
grep -qE "identical across|first divergence at frame ([2-9][0-9]{3,}|1[5-9][0-9]{2})" "$SUMMARY" && FRAME_OK=1

if (( WIN_OK && FRAME_OK )); then
  echo "PASS: winners match, state agreement holds past frame ~1500"
  exit 0
else
  echo "DIVERGENCE: see $SUMMARY"
  exit 1
fi
