#!/bin/bash
# Run spring-headless on a .sdfz in an isolated sandbox, capture state trace.
# Usage: capture.sh <replay.sdfz> [out_name]
set -euo pipefail

REPLAY="${1:?usage: capture.sh <replay.sdfz> [out_name]}"
OUT_NAME="${2:-$(basename "$REPLAY" .sdfz)}"

PROJECT="$HOME/projects/bar/wasm"
BAR_DATA="$HOME/.local/state/Beyond All Reason"
ENGINE_DIR="$BAR_DATA/engine/recoil_2025.06.19"
# Override which engine binary to run (e.g. our locally-built one) via env.
HEADLESS="${HEADLESS:-$ENGINE_DIR/spring-headless}"
WIDGETS_DIR="$PROJECT/widgets"
TRACES="$PROJECT/traces"

[[ -x "$HEADLESS" ]]    || { echo "no spring-headless at $HEADLESS"; exit 1; }
[[ -f "$REPLAY" ]]      || { echo "no replay at $REPLAY"; exit 1; }
[[ -d "$WIDGETS_DIR" ]] || { echo "no widgets dir at $WIDGETS_DIR"; exit 1; }

# Fetch content the replay needs (map + game) via the bar-replays helper if missing.
# This re-uses the same pr-downloader invocation we pinned down earlier.
REPLAY_ID="$(basename "$REPLAY" .sdfz | awk -F_ '{print $1"_"$2"_"$3}')"
# bar-rts.com API gives us gameVersion + map name; use python for the lookup
python3 - "$REPLAY" "$ENGINE_DIR" "$BAR_DATA" <<'PY'
import json, os, subprocess, sys, urllib.parse, urllib.request
from pathlib import Path
replay, engine_dir, bar_data = sys.argv[1:]
fname = Path(replay).name
# Query API by file name prefix (YYYY-MM-DD_HH-MM-SS-mmm) is not indexed, so
# just skim recent replays to find ours (matches ~50ms per listing page).
# We'll instead parse the map + game out of the file name heuristically as a hint
# and let pr-downloader do its thing.
# Format: 2026-04-22_20-01-45-430_BarR 1.1_2025.06.19.sdfz
stem = Path(replay).stem
try:
    _, rest = stem.split("-430_", 1) if "-430_" in stem else stem.split("_", 3)[3:4][0], None
except Exception:
    rest = stem
# Take everything between the timestamp and the trailing engine version
parts = stem.split("_")
# parts like: [date, time, ms, map, engine]  — but map may contain underscores
# engine version is always the last "_YYYY.MM.DD"
if len(parts) >= 5 and parts[-1].count(".") == 2:
    map_name = "_".join(parts[3:-1])
else:
    map_name = parts[3] if len(parts) > 3 else ""
print(f"guess: map={map_name!r}")
env = {**os.environ,
       "PRD_RAPID_USE_STREAMER": "false",
       "PRD_RAPID_REPO_MASTER": "https://repos-cdn.beyondallreason.dev/repos.gz",
       "PRD_HTTP_SEARCH_URL": "https://files-cdn.beyondallreason.dev/find"}
prdl = Path(engine_dir) / "pr-downloader"
if map_name:
    subprocess.run([str(prdl), "--filesystem-writepath", bar_data,
                    "--download-map", map_name], env=env, check=False)
PY

SANDBOX="$(mktemp -d -t bar-headless-XXXXXX)"
[[ "${KEEP_SANDBOX:-0}" == "1" ]] || trap 'rm -rf "$SANDBOX"' EXIT
echo "sandbox: $SANDBOX"

# Symlink content dirs from the real BAR install so isolation mode still finds archives.
for d in engine pool packages rapid maps games; do
    [[ -e "$BAR_DATA/$d" ]] && ln -s "$BAR_DATA/$d" "$SANDBOX/$d"
done
mkdir -p "$SANDBOX/LuaUI/Widgets" "$SANDBOX/LuaUI/Config"
[[ -e "$BAR_DATA/LuaUI/Fonts"  ]] && ln -s "$BAR_DATA/LuaUI/Fonts"  "$SANDBOX/LuaUI/Fonts"
cp "$WIDGETS_DIR/"*.lua "$SANDBOX/LuaUI/Widgets/"

# Copy the real BYAR.lua config so mod widgets keep their settings, then pre-enable
# our State Dump widget. BAR's barwidgets.lua refuses to auto-enable new user widgets;
# presence of "State Dump" = 12345 in orderList forces it on.
if [[ -f "$BAR_DATA/LuaUI/Config/BYAR.lua" ]]; then
    cp "$BAR_DATA/LuaUI/Config/BYAR.lua" "$SANDBOX/LuaUI/Config/BYAR.lua"
else
    cat > "$SANDBOX/LuaUI/Config/BYAR.lua" <<'EOF'
-- Widget Custom data and order
return {
	["allowUserWidgets"] = true,
	["orderList"] = { ["State Dump"] = 12345 },
}
EOF
fi
FAST="${FAST:-0}"
python3 - "$SANDBOX/LuaUI/Config/BYAR.lua" "$FAST" <<'PY'
import re, sys
p, fast = sys.argv[1], sys.argv[2] == "1"
t = open(p).read()

# Names of our project-side widgets (in $PROJECT/widgets/) that must be force-
# enabled so they actually run during headless playback. Add new widgets here.
KEEP = [("State Dump", 12345), ("Unit Motion Probe", 12346),
        ("Probe DumpState Trigger", 12347), ("Outcome Recorder", 12348)]

# Force-enable each KEEP widget by patching the BYAR config's order list.
for name, prio in KEEP:
    needle = f'"{name}"'
    if needle in t:
        t = re.sub(rf'\["{re.escape(name)}"\]\s*=\s*\d+', f'["{name}"] = {prio}', t)
    else:
        new, n = re.subn(r'(\border\s*=\s*\{)',
                         rf'\1\n\t\t["{name}"] = {prio},', t, count=1)
        if n == 0:
            raise SystemExit(f"could not find `order = {{` in config to insert {name}")
        t = new

# FAST mode: disable every other user widget to dodge CPU-bound gfx/gui widgets.
# Gadgets (sim-side) continue to run from the game archive regardless.
if fast:
    keep_names = {name for name, _ in KEEP}
    lines, out, in_order = t.splitlines(), [], False
    for ln in lines:
        if not in_order and re.search(r'\border\s*=\s*\{', ln):
            in_order = True; out.append(ln); continue
        if in_order and ln.strip().startswith("}"):
            in_order = False; out.append(ln); continue
        if in_order:
            if any(f'"{n}"' in ln for n in keep_names):
                out.append(ln)  # keep ours enabled
            else:
                out.append(re.sub(r'=\s*\d+', '= 0', ln))
            continue
        out.append(ln)
    t = "\n".join(out) + "\n"

open(p, 'w').write(t)
PY
[[ "$FAST" == "1" ]] && echo "FAST mode: other user widgets disabled"

cat > "$SANDBOX/_launch.txt" <<EOF
[modoptions]
{
    MinSpeed = 9999;
    MaxSpeed = 9999;
}
[game]
{
    demofile=$REPLAY;
    hostport=31337;
}
EOF

cd "$SANDBOX"
echo "running headless..."
t0=$(date +%s)
"$HEADLESS" --write-dir "$SANDBOX" --isolation ./_launch.txt 2>&1 | tail -20 || true
dt=$(( $(date +%s) - t0 ))
echo "done in ${dt}s"

mkdir -p "$TRACES"
if [[ -s "$SANDBOX/state_trace.jsonl" ]]; then
    DEST="$TRACES/${OUT_NAME}.jsonl"
    mv "$SANDBOX/state_trace.jsonl" "$DEST"
    # Compress a copy of the engine log for future debugging.
    if [[ -s "$SANDBOX/infolog.txt" ]]; then
        gzip -c "$SANDBOX/infolog.txt" > "$TRACES/${OUT_NAME}.infolog.gz"
    fi
    # Probe widget output (if any).
    if [[ -s "$SANDBOX/unit_probe.jsonl" ]]; then
        mv "$SANDBOX/unit_probe.jsonl" "$TRACES/${OUT_NAME}.probe.jsonl"
        echo "probe: $TRACES/${OUT_NAME}.probe.jsonl ($(wc -l < "$TRACES/${OUT_NAME}.probe.jsonl") lines)"
    fi
    # Outcome widget output (GameOver, final per-team summary).
    if [[ -s "$SANDBOX/outcome.jsonl" ]]; then
        mv "$SANDBOX/outcome.jsonl" "$TRACES/${OUT_NAME}.outcome.jsonl"
        echo "outcome: $TRACES/${OUT_NAME}.outcome.jsonl"
    fi
    # /DumpState output (if any) — ReplayGameState-*.txt files in write-dir.
    DUMP_DEST="$TRACES/${OUT_NAME}.dumpstates"
    mkdir -p "$DUMP_DEST"
    found_dump=0
    for dumpf in "$SANDBOX"/ReplayGameState-*.txt "$SANDBOX"/ServerGameState-*.txt; do
        [[ -e "$dumpf" ]] || continue
        mv "$dumpf" "$DUMP_DEST/"
        found_dump=$((found_dump + 1))
    done
    if (( found_dump > 0 )); then
        echo "dumpstates: $DUMP_DEST ($found_dump files)"
    else
        rmdir "$DUMP_DEST" 2>/dev/null
    fi
    wc -l "$DEST"
    ls -la "$DEST"
    echo "trace: $DEST"
else
    echo "NO trace produced — widget may not have loaded. Recent engine log:"
    tail -30 "$SANDBOX/infolog.txt" 2>/dev/null || true
    exit 2
fi
