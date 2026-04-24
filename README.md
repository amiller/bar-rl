# bar-hacks

Personal hacking on [Beyond All Reason](https://www.beyondallreason.info/) and
its engine, [Recoil](https://github.com/beyond-all-reason/RecoilEngine).

Layout:

    launcher/bar-replays.py       CLI replay browser/launcher (hits api.bar-rts.com)
    wasm/
      widgets/state_dump.lua      Spring widget — dump per-frame unit state as JSONL
      scripts/capture.sh          Sandboxed spring-headless run → JSONL trace
      scripts/serve.py            Dev server: viewer + /api/traces + /api/capture
      scripts/diff-traces.py      Compare two traces, find first diverging frame
      viewer/index.html           Canvas scrubber — plays a JSONL trace back
      scripts/wasm-configure.sh   emcmake config for spring-headless → WASM
      scripts/wasm-build.sh       emmake wrapper
      scripts/wasm-env.sh         Sources emsdk for the shell
      patches/                    Stacked patches against Recoil for WASM port
      stubs/devil/                No-op DevIL (Bitmap.cpp needs 18 functions)
      stubs/pr-downloader/        Stub pr-downloader lib (no CURL required)
      stubs/cmake/                Find<X>.cmake shims → emscripten ports
      docs/                       SESSION_LOG.md, WASM_PORT_NOTES.md

`repos/` (gitignored) is where you keep local clones of RecoilEngine, bar-lobby, etc.

## Two threads

### `launcher/bar-replays.py` — browse + download + launch replays

Python CLI that hits `api.bar-rts.com`, shows a rofi/tty picker with
per-replay OpenSkill ratings (enriched from the detail endpoint in
parallel), downloads `.sdfz` files to BAR's demos dir, and optionally
invokes the Spring engine directly on the replay — skipping the Chobby
lobby entirely. Also handles the BAR CDN env vars for `pr-downloader`
so it can fetch missing maps and game versions on demand.

```
bar-replays --pro                         # top-tier duels
bar-replays --player Nekstad --play       # auto-launch first hit
bar-replays --min-ts 30 --preset team     # strong team games
```

### `wasm/` — spring-headless → WebAssembly

Stacked patches + build scripts that teach Recoil's CMake and source
tree to cross-compile with Emscripten. Current state:

- Configure passes cleanly with the patches applied.
- Produces `spring-headless.wasm` (~12 MB) + `spring-headless.js` (~250 KB).
- `node spring-headless.js --version` prints and exits 0.
- `node spring-headless.js --write-dir <BAR_DATA> --isolation=true <demo.sdfz>`
  pre-scans the demo, starts the internal GameServer, loads the map and
  game archives, negotiates player slots, creates the LoadScreen.

See `wasm/docs/SESSION_LOG.md` for a running journal and
`wasm/docs/WASM_PORT_NOTES.md` for the blockers in order.

#### Patch surface

- `wasm/patches/001-cmake-emscripten-shims.patch` (~850 lines, 26 files):
  - Bypasses `CMAKE_SIZEOF_VOID_P==8` and x86/ARM64-only arch checks.
  - Adds WASM SIMD (`<wasm_simd128.h>`) mappings for the ~20 SSE
    intrinsics engine code uses directly (in `rts/System/simd_compat.h`).
  - Replaces `spring::thread` with an inline-executor; early-returns
    `Watchdog::HangDetectorLoop` and `ThreadPool::WorkerLoop` so
    daemon-style "threads" don't hang when run inline.
  - Stubs Linux platform files: CpuID, CrashHandler, ThreadSupport,
    ThreadAffinityGuard, Futex, CpuTopology, Mac-addr probe, Misc
    exe-path resolution.
  - Provides `sched_getaffinity/setaffinity` and
    `pthread_setschedparam` bodies so the link resolves without real
    pthread support.
  - Maps `"localhost"` → `"127.0.0.1"` inside `UDPListener::TryBindSocket`
    (emscripten's resolver doesn't know "localhost").
  - Flips `std::async(launch::async)` → `launch::deferred` in
    `PreGame.cpp` and patches `HasPendingAsyncTask` to force-run the
    deferred future.
  - Header-macro collision fixes: `PAGE_SIZE`, `TCP_LISTEN`,
    `isnanf/isinff`, `_MM_SHUFFLE`.
- `wasm/patches/002-streflop-emscripten-undef.patch` — undefs inside
  streflop's SMath.h.
- `wasm/stubs/devil/` — ~100 lines, all 18 DevIL functions as no-ops.
  Every loaded image becomes a 1×1 transparent RGBA pixel.
- `wasm/stubs/pr-downloader/` — stub library providing `prd::jsoncpp`,
  `prd::base64`, and a no-op `pr-downloader` public API so engine link
  succeeds without CURL (downloads are meaningless in browser anyway).
- `wasm/stubs/cmake/Find{ZLIB,SDL2,Freetype,Fontconfig,EXPAT}.cmake` —
  cmake module shims that route `find_package()` to emscripten's port
  flags (`-sUSE_ZLIB=1`, `-sUSE_SDL=2`, `-sUSE_FREETYPE=1`, etc.).

## Getting started

### Replay viewer + state-dump capture

```bash
# 1. Ensure BAR is installed (the AppImage works) and you've run at least one
#    replay so the engine's data dir and rapid pool are populated.
# 2. Serve + open viewer:
cd wasm
scripts/serve-viewer.sh
# open http://localhost:8765/viewer/
# 3. To capture a trace from a replay:
scripts/capture.sh "$HOME/.local/state/Beyond All Reason/data/demos/<file>.sdfz"
# drops JSONL into traces/, auto-loaded by the viewer.
```

### WASM build

```bash
# 1. Clone RecoilEngine into repos/ with submodules:
mkdir -p repos && cd repos
git clone --depth 1 --recurse-submodules \
    https://github.com/beyond-all-reason/RecoilEngine.git
cd ..

# 2. Install emscripten at wasm/tools/emsdk/ (or adjust wasm/scripts/wasm-env.sh)
cd wasm/tools
git clone https://github.com/emscripten-core/emsdk.git
cd emsdk && ./emsdk install latest && ./emsdk activate latest
cd ../..

# 3. Install a modern CMake (Ubuntu 22.04's 3.22 is too old; need >=3.27):
pip install --user cmake

# 4. Configure + build (auto-applies patches, builds to build-wasm/):
scripts/wasm-configure.sh
scripts/wasm-build.sh
# → build-wasm/spring-headless.{js,wasm}

# 5. Install 'ws' for node's emscripten socket shim:
(cd build-wasm && npm install ws)

# 6. Symlink engine base/ so isolation-mode finds springcontent.sdz:
BAR_DATA="$HOME/.local/state/Beyond All Reason"
ln -sfn "$BAR_DATA/engine/recoil_2025.06.19/base" "$BAR_DATA/base"

# 7. Run:
cd "$BAR_DATA/engine/recoil_2025.06.19"
node /path/to/wasm/build-wasm/spring-headless.js \
    --write-dir "$BAR_DATA" \
    --isolation=true \
    "$BAR_DATA/data/demos/<file>.sdfz"
```

## Upstream projects

- [Beyond-All-Reason](https://github.com/beyond-all-reason/Beyond-All-Reason) — game data + Lua
- [RecoilEngine](https://github.com/beyond-all-reason/RecoilEngine) — C++ engine (Spring 105 fork)
- [bar-lobby](https://github.com/beyond-all-reason/bar-lobby) — new Electron lobby
- [BYAR-Chobby](https://github.com/beyond-all-reason/BYAR-Chobby) — legacy Lua lobby
- [bar-replay-analyzer](https://github.com/jorisvddonk/bar-replay-analyzer) — prior art for headless replay instrumentation
- [bar-db](https://github.com/beyond-all-reason/bar-db) — `api.bar-rts.com` backend

## License

Patches under `wasm/patches/` derive from RecoilEngine (GPL v2 or later)
and carry that license. Everything else here (launcher, viewer, widget,
stub libraries, build scripts, docs) is MIT unless stated otherwise.
