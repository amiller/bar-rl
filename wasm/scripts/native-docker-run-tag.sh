#!/bin/bash
# Run the 2025.06.19-tag-built native binary on a replay. Same setup as
# native-docker-run.sh but points at build-native-2025.06.19/spring-headless.
set -euo pipefail
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT="$( cd "$SCRIPT_DIR/.." && pwd )"
REPLAY="${1:?usage: native-docker-run-tag.sh <replay.sdfz> [out_name]}"
OUT_NAME="${2:-$(basename "$REPLAY" .sdfz)-2025.06.19}"
IMAGE="bar-native-build:gcc13"
BAR_DATA="$HOME/.local/state/Beyond All Reason"
WIDGETS_DIR="$PROJECT/widgets"
HEADLESS="$PROJECT/build-native-2025.06.19/spring-headless"
TRACES="$PROJECT/traces"

[[ -x "$HEADLESS" ]] || { echo "no $HEADLESS"; exit 1; }
[[ -f "$REPLAY" ]]   || { echo "no replay"; exit 1; }

SANDBOX="$(mktemp -d -t bar-2025.06.19-XXXXXX)"
[[ "${KEEP_SANDBOX:-0}" == "1" ]] || trap 'rm -rf "$SANDBOX"' EXIT
echo "sandbox: $SANDBOX"

for d in engine pool packages rapid maps games; do
    [[ -e "$BAR_DATA/$d" ]] && ln -s "$BAR_DATA/$d" "$SANDBOX/$d"
done
mkdir -p "$SANDBOX/LuaUI/Widgets" "$SANDBOX/LuaUI/Config"
[[ -e "$BAR_DATA/LuaUI/Fonts" ]] && ln -s "$BAR_DATA/LuaUI/Fonts" "$SANDBOX/LuaUI/Fonts"
cp "$WIDGETS_DIR/"*.lua "$SANDBOX/LuaUI/Widgets/"

if [[ -f "$BAR_DATA/LuaUI/Config/BYAR.lua" ]]; then
    cp "$BAR_DATA/LuaUI/Config/BYAR.lua" "$SANDBOX/LuaUI/Config/BYAR.lua"
else
    echo 'return { ["allowUserWidgets"]=true, ["orderList"]={["State Dump"]=12345} }' > "$SANDBOX/LuaUI/Config/BYAR.lua"
fi
python3 - "$SANDBOX/LuaUI/Config/BYAR.lua" <<'PY'
import re, sys
p = sys.argv[1]; t = open(p).read()
KEEP = [("State Dump", 12345), ("Unit Motion Probe", 12346),
        ("Probe DumpState Trigger", 12347), ("Outcome Recorder", 12348),
        ("Interactions Probe", 12349)]
for name, prio in KEEP:
    if f'"{name}"' in t:
        t = re.sub(rf'\["{re.escape(name)}"\]\s*=\s*\d+', f'["{name}"] = {prio}', t)
    else:
        new, n = re.subn(r'(\border\s*=\s*\{)', rf'\1\n\t\t["{name}"] = {prio},', t, count=1)
        if n == 0: raise SystemExit(f"no `order = {{` in config for {name}")
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
echo "running headless inside $IMAGE..."
t0=$(date +%s)
docker run --rm \
    -e SYNC_PROBE_ABORT_FRAME -e SYNC_PROBE_ABORT_REC -e SYNC_PROBE_DUMP_ANIMS \
    -v "$SANDBOX:$SANDBOX" \
    -v "$BAR_DATA:$BAR_DATA:ro" \
    -v "$REPLAY_DIR:$REPLAY_DIR:ro" \
    -v "$PROJECT/build-native-2025.06.19:$PROJECT/build-native-2025.06.19:ro" \
    -w "$SANDBOX" \
    "$IMAGE" \
    "$HEADLESS" --write-dir "$SANDBOX" --isolation ./_launch.txt 2>&1 \
    | tee "$SANDBOX/full.log" | tail -25 || true
dt=$(( $(date +%s) - t0 ))
echo "done in ${dt}s"

DESYNC_COUNT=$(grep -c "DESYNC WARNING" "$SANDBOX/full.log" 2>/dev/null || echo 0)
echo "desync_warnings: $DESYNC_COUNT"
grep "DESYNC WARNING" "$SANDBOX/full.log" 2>/dev/null | head -3 || true

mkdir -p "$TRACES"
[[ -s "$SANDBOX/state_trace.jsonl" ]]  && mv "$SANDBOX/state_trace.jsonl"  "$TRACES/${OUT_NAME}.jsonl"
[[ -s "$SANDBOX/unit_probe.jsonl" ]]   && mv "$SANDBOX/unit_probe.jsonl"   "$TRACES/${OUT_NAME}.probe.jsonl"
[[ -s "$SANDBOX/outcome.jsonl" ]]      && mv "$SANDBOX/outcome.jsonl"      "$TRACES/${OUT_NAME}.outcome.jsonl"
[[ -s "$SANDBOX/interactions.jsonl" ]] && mv "$SANDBOX/interactions.jsonl" "$TRACES/${OUT_NAME}.interactions.jsonl"
gzip -c "$SANDBOX/full.log" > "$TRACES/${OUT_NAME}.infolog.gz"
DD="$TRACES/${OUT_NAME}.dumpstates"; mkdir -p "$DD"; n=0
for f in "$SANDBOX"/ReplayGameState-*.txt "$SANDBOX"/ServerGameState-*.txt; do
    [[ -e "$f" ]] || continue; mv "$f" "$DD/"; n=$((n+1))
done
[[ $n -gt 0 ]] && echo "dumpstates: $DD ($n files)" || rmdir "$DD" 2>/dev/null
echo "done."
