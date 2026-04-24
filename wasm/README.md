# bar/wasm

Dev/test scaffolding for instrumenting `spring-headless` replay playback and
eventually porting it to WASM.

## Layout

    widgets/state_dump.lua     Lua widget — dumps per-frame unit state to JSONL
    scripts/capture.sh         Run spring-headless on a .sdfz in a sandbox → trace
    scripts/serve.py           HTTP server: viewer + /api/traces + /api/capture
    scripts/serve-viewer.sh    Shim that launches serve.py
    viewer/index.html          Canvas + scrubber; icons tinted per team color
    viewer/icons.json          unitdef name → icon PNG (parsed from icontypes.lua)
    viewer/icons/              symlink to BAR's official icon set
    traces/                    Captured JSONL traces
    docs/                      Planning notes (WASM port, architecture, etc.)

## Quick start

    scripts/serve-viewer.sh
    # open http://localhost:8765/viewer/

Two sidebar tabs:

- **local** — existing `.jsonl` traces (auto-loads the first one on page load).
- **bar-rts** — live replay browser (hits `api.bar-rts.com` directly). Click
  a replay → server downloads the `.sdfz` into BAR's demos dir and runs
  `capture.sh` with `FAST=1` → viewer auto-loads the trace. ~30–60s for a
  20-minute match.

Unit rendering uses BAR's native minimap icons (grayscale silhouettes,
`source-in`-tinted to team color on the fly, cached per (icon, color) pair).

### Manual capture (no server)

    scripts/capture.sh "$HOME/.local/state/Beyond All Reason/data/demos/<file>.sdfz"

## Gotchas learned

- BAR's widget handler refuses to auto-enable new user-side widgets unless the
  config already has them in `orderList`. `capture.sh` pre-seeds
  `LuaUI/Config/BYAR.lua` with `["State Dump"] = 12345` to force-enable our
  widget on first run.
- `pr-downloader` needs these env vars to see BAR's CDN:
  `PRD_RAPID_USE_STREAMER=false`,
  `PRD_RAPID_REPO_MASTER=https://repos-cdn.beyondallreason.dev/repos.gz`,
  `PRD_HTTP_SEARCH_URL=https://files-cdn.beyondallreason.dev/find`.
- `spring-headless --isolation <script.txt>` reads only from the write-dir.
  The sandbox symlinks `engine/`, `pool/`, `packages/`, `rapid/`, `maps/` from
  the real install so archives are still found; writes go only to the sandbox.
- Headless still executes all 200+ mod widgets. Runs at ~0.5× realtime even
  with `MinSpeed = MaxSpeed = 9999` in the launch script because widgets are
  CPU-bound. Future: strip the mod's luaui/Widgets/ dir in the sandbox to get
  real 10×+ replay speed.

## Next steps

- [ ] Trim mod widgets in the sandbox to speed up capture
- [ ] `scripts/diff-traces.py` — compare two traces, report first diverging frame/unit
- [ ] Emscripten port of `spring-headless` (see `docs/WASM_PORT_NOTES.md`)
