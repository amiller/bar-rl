#!/bin/bash
# Run docker-built native spring-headless on a replay file. Same isolation/
# sandbox layout as scripts/capture.sh but executes inside the build container
# (binary is linked against ubuntu:24.04 glibc, won't run on Mint 21.3 host).
#
# Usage: native-docker-run.sh <replay.sdfz> [out_name]
set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT="$( cd "$SCRIPT_DIR/.." && pwd )"
REPLAY="${1:?usage: native-docker-run.sh <replay.sdfz> [out_name]}"
OUT_NAME="${2:-$(basename "$REPLAY" .sdfz)-native-docker}"
IMAGE="bar-native-build:gcc13"

BAR_DATA="$HOME/.local/state/Beyond All Reason"
ENGINE_DIR="$BAR_DATA/engine/recoil_2025.06.19"
WIDGETS_DIR="$PROJECT/widgets"
HEADLESS="$PROJECT/build-native-docker/spring-headless"
TRACES="$PROJECT/traces"

[[ -x "$HEADLESS" ]]    || { echo "no $HEADLESS — run native-docker-build.sh first"; exit 1; }
[[ -f "$REPLAY" ]]      || { echo "no replay at $REPLAY"; exit 1; }
[[ -d "$WIDGETS_DIR" ]] || { echo "no widgets dir at $WIDGETS_DIR"; exit 1; }

SANDBOX="$(mktemp -d -t bar-native-docker-XXXXXX)"
[[ "${KEEP_SANDBOX:-0}" == "1" ]] || trap 'rm -rf "$SANDBOX"' EXIT
echo "sandbox: $SANDBOX"

for d in engine pool packages rapid maps games; do
    [[ -e "$BAR_DATA/$d" ]] && ln -s "$BAR_DATA/$d" "$SANDBOX/$d"
done
mkdir -p "$SANDBOX/LuaUI/Widgets" "$SANDBOX/LuaUI/Config"
[[ -e "$BAR_DATA/LuaUI/Fonts" ]] && ln -s "$BAR_DATA/LuaUI/Fonts" "$SANDBOX/LuaUI/Fonts"
cp "$WIDGETS_DIR/"*.lua "$SANDBOX/LuaUI/Widgets/"

# Reuse the same BYAR config patching the WASM capture.sh does — copy real
# config (so mod widgets keep their settings) then force-enable our probes.
if [[ -f "$BAR_DATA/LuaUI/Config/BYAR.lua" ]]; then
    cp "$BAR_DATA/LuaUI/Config/BYAR.lua" "$SANDBOX/LuaUI/Config/BYAR.lua"
else
    cat > "$SANDBOX/LuaUI/Config/BYAR.lua" <<'EOF'
return { ["allowUserWidgets"] = true,
         ["orderList"] = { ["State Dump"] = 12345 } }
EOF
fi
python3 - "$SANDBOX/LuaUI/Config/BYAR.lua" <<'PY'
import re, sys
p = sys.argv[1]
t = open(p).read()
KEEP = [("State Dump", 12345), ("Unit Motion Probe", 12346),
        ("Probe DumpState Trigger", 12347), ("Outcome Recorder", 12348),
        ("Interactions Probe", 12349)]
for name, prio in KEEP:
    if f'"{name}"' in t:
        t = re.sub(rf'\["{re.escape(name)}"\]\s*=\s*\d+', f'["{name}"] = {prio}', t)
    else:
        new, n = re.subn(r'(\border\s*=\s*\{)',
                         rf'\1\n\t\t["{name}"] = {prio},', t, count=1)
        if n == 0: raise SystemExit(f"could not find `order = {{` to insert {name}")
        t = new
open(p, 'w').write(t)
PY

cat > "$SANDBOX/_launch.txt" <<EOF
[modoptions]
{
    MinSpeed = 9999;
    MaxSpeed = 9999;
}
[game]
{
    demofile=$REPLAY;
    hostport=$((31337 + RANDOM % 10000));
}
EOF

REPLAY_DIR="$(cd "$(dirname "$REPLAY")" && pwd)"
REPLAY_BASE="$(basename "$REPLAY")"

echo "running headless inside $IMAGE..."
t0=$(date +%s)
docker run --rm \
    -v "$SANDBOX:$SANDBOX" \
    -v "$BAR_DATA:$BAR_DATA:ro" \
    -v "$REPLAY_DIR:$REPLAY_DIR:ro" \
    -v "$PROJECT/build-native-docker:$PROJECT/build-native-docker:ro" \
    -w "$SANDBOX" \
    "$IMAGE" \
    "$HEADLESS" --write-dir "$SANDBOX" --isolation ./_launch.txt 2>&1 | tail -20 || true
dt=$(( $(date +%s) - t0 ))
echo "done in ${dt}s"

mkdir -p "$TRACES"
if [[ -s "$SANDBOX/state_trace.jsonl" ]]; then
    DEST="$TRACES/${OUT_NAME}.jsonl"
    mv "$SANDBOX/state_trace.jsonl" "$DEST"
    echo "trace: $DEST ($(wc -l < "$DEST") lines)"
fi
[[ -s "$SANDBOX/infolog.txt" ]]      && gzip -c "$SANDBOX/infolog.txt"   > "$TRACES/${OUT_NAME}.infolog.gz"
[[ -s "$SANDBOX/unit_probe.jsonl" ]] && mv "$SANDBOX/unit_probe.jsonl"     "$TRACES/${OUT_NAME}.probe.jsonl"
[[ -s "$SANDBOX/outcome.jsonl" ]]    && mv "$SANDBOX/outcome.jsonl"        "$TRACES/${OUT_NAME}.outcome.jsonl"
[[ -s "$SANDBOX/interactions.jsonl" ]] && mv "$SANDBOX/interactions.jsonl" "$TRACES/${OUT_NAME}.interactions.jsonl"
DUMP_DEST="$TRACES/${OUT_NAME}.dumpstates"
mkdir -p "$DUMP_DEST"
found=0
for dumpf in "$SANDBOX"/ReplayGameState-*.txt "$SANDBOX"/ServerGameState-*.txt; do
    [[ -e "$dumpf" ]] || continue
    mv "$dumpf" "$DUMP_DEST/"; found=$((found+1))
done
if (( found > 0 )); then
    echo "dumpstates: $DUMP_DEST ($found files)"
else
    rmdir "$DUMP_DEST" 2>/dev/null
fi
echo "done."
