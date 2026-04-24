# Session log — headless-replay + WASM port scaffolding

## 2026-04-24

### Goal
Stand up an end-to-end dev/test rig for instrumenting Recoil replay playback,
with a scrubber viewer, then begin a WASM port of spring-headless.

### Done

1. **Project layout** at `~/projects/bar/wasm/`: widgets, scripts, viewer,
   traces, patches, docs.
2. **State-dump widget** (`widgets/state_dump.lua`) — writes one JSONL record
   per sampled frame (`f % 6 == 0`), plus `UnitCreated` / `UnitDestroyed`
   events. Line-buffered output via `fh:setvbuf("line")`.
3. **Capture script** (`scripts/capture.sh`) — sandboxed headless run.
   - Symlinks content dirs (engine, pool, packages, rapid, maps) from the real
     install so `--isolation` mode finds archives.
   - Auto-fetches the replay's map via `pr-downloader` (using the BAR CDN env
     vars).
   - Pre-seeds `LuaUI/Config/BYAR.lua` with `["State Dump"] = 12345` to
     force-enable our widget (BAR's widget handler otherwise ignores new
     user-side widgets).
   - `FAST=1` flag disables all other user widgets to skip CPU-bound
     gfx/GUI widget work during headless playback.
4. **Viewer** (`viewer/index.html`) — single-file Canvas scrubber.
   Arrow keys to scrub, Shift+arrow ×50, Space to play/pause, Home/End.
   Auto-loads first trace from `../traces/`.
5. **Diff tool** (`scripts/diff-traces.py`) — compares two JSONL traces and
   reports first diverging frame/unit (position/HP tolerance configurable).
6. **Emscripten toolchain** — emsdk installed + activated at
   `tools/emsdk/` (emcc 5.0.6).
7. **First WASM configure attempt** — `scripts/wasm-configure.sh`. Blockers
   surfaced and documented in `WASM_PORT_NOTES.md`. Patches to Recoil's
   CMakeLists (bypass 32-bit + arch checks) live in `patches/` and are
   auto-applied by the configure script.

### Open

- WASM configure blocked on DevIL + SDL2. Next: stub DevIL for headless path.
- Haven't tried `FAST=1` yet to quantify speedup.

### Milestone: first real trace rendered in browser (11:19)

Captured 8:27 of a BAR 1v1 on BarR 1.1 via `spring-headless` + our state-dump
widget. Trace: 2539 frame snapshots + 410 UnitCreated + 246 UnitDestroyed
events, 12 MB JSONL. Viewer at http://localhost:8765/viewer/ plays it back
with a scrubber, Canvas 2D rendering, dots per unit, opacity = HP%.
Wall:sim ratio was ~2:1 with all 200+ BAR mod widgets running.

User feedback: "fascinating to watch even without being able to zoom in and
see the exact unit types". Good milestone — we have a working loop.

### WASM configure expedition (~11:30–12:00)

Plowed through 16 configure-stage blockers. Built stub library for DevIL.
cmake shims for ZLIB, SDL2, Freetype, Fontconfig, EXPAT → `-sUSE_X=1` ports.
Patches to bypass arch checks, skip tools/ + legacy exe + test subdir.

### WASM build push (~12:00–12:45)

**Configure now passes cleanly.** `scripts/wasm-configure.sh` is idempotent.

Then into compiling. Patches layered in:

- `-msse -mfpmath=sse` guarded behind `if (NOT EMSCRIPTEN)`; WASM path
  uses `-msimd128` instead, no sse2neon (that targets ARM NEON, not WASM SIMD).
- `rts/System/MainDefines.h`: added `__EMSCRIPTEN__` branch to the CPU
  arch check (was falling through to `#error unknown CPU-architecture`).
- `rts/System/simd_compat.h`: added a WASM branch providing the ~20 SSE
  intrinsics engine code actually uses, mapped to `<wasm_simd128.h>`
  (`_mm_load_ps` → `wasm_v128_load`, `_mm_add_ps` → `wasm_f32x4_add`, etc.).
- `rts/System/MemPoolTypes.h`: `#undef PAGE_SIZE` — musl's `<limits.h>` defines
  it as a macro, colliding with the class's `static constexpr PAGE_SIZE()`.
- Streflop's SMath.h: `#undef isnanf/isinff/...` — emscripten's compat/math.h
  defines them as macros, breaking streflop's inline function decls.
- Disabled streflop entirely (`-DENABLE_STREFLOP=OFF`) — SOFT mode still
  emits ambiguous `math::fmod` overloads for plain floats. For replay
  playback we don't need cross-machine float determinism.
- Build script exports `CI=1` so Recoil's git-describe version check skips.

**Current state:** build reaches ~23%. streflop, mimalloc, nowide, fmt,
devil_stub, pr-downloader stub, prd::jsoncpp, prd::base64, sse2neon
compat, GameHeadless — all configure and most compile.

### 🎉 FIRST RUNNING WASM BINARY (~13:10)

`spring-headless.wasm` (12.3 MB) + `spring-headless.js` (110 KB loader) now
build cleanly and run under Node:

    $ node spring-headless.js --version
    spring-headless.js version daddb48 master (Headless)
    $ echo $?   # 0

Engine also responds to `--help` (full gflags help tree). When run with no
args it aborts after streflop-disabled warnings — expected, emscripten's
virtual FS has no BAR content preloaded yet.

Total blockers resolved from start to running binary: ~30. Patches:
- `001-cmake-emscripten-shims.patch` — 714 lines, 22 files
- `002-streflop-emscripten-undef.patch` — 34 lines, 1 file

### Next steps (resume session)

Current state: with `-sNODERAWFS=1` the WASM engine can see the real FS
directly under Node. It reads springsettings.cfg, loads config, resolves
paths. Aborts right after `[operator()] streflop is disabled` warning.

Progress made past the --version point:
- reads springsettings.cfg (sees real values!)
- picks up real CPU info via NODERAWFS (`/proc/cpuinfo` passthrough)
- opens infolog.txt for writes
- hits streflop fpu-check no-op, then aborts (~50ms in)

Next blocker to hunt: what's aborting right after fpu_check. Candidates:
- SDL init (emscripten SDL2 wants a Canvas; we're headless)
- Some assertion in an early init path (e.g., thread pool setup, watchdog)
- Rebuild with `-sASSERTIONS=2 -g` for stack traces next session

Then:
- Preload/load engine base/ sdz + map + game archives (NODERAWFS might handle)
- Try `--isolation <replay.sdfz>` once init completes
- Hook state-dump widget; compare trace to native for determinism check

### WASM build push round 2 (~12:45–13:15)

More blockers fixed:

- `rts/lib/smmalloc/smmalloc.h`: missing `#include <type_traits>` for
  `std::is_trivial` (emscripten libc++ requires explicit include).
- `rts/lib/smmalloc/smmalloc_generic.cpp`: missing `#include <cstdlib>` for
  `std::malloc` / `std::free` in the `std::` namespace.
- `rts/lib/luasocket/src/restrictions.h`: `#undef TCP_LISTEN` + friends —
  musl's `<netinet/tcp.h>` macros shadow enum values.
- `rts/System/simd_compat.h`: added `_MM_SHUFFLE(fp3,fp2,fp1,fp0)` macro
  (used by `_mm_shuffle_ps` callers in SmoothHeightMesh.cpp).
- Stub `pr-downloader` CMakeLists: also `add_subdirectory(lib/7z)` + expose
  the 7z headers globally (Recoil's SevenZipArchive.cpp `#include <7z.h>`).

Patches now 10 files across 2 patch files; still idempotent & re-runnable.

### Gotchas logged for future

- `cd && foo & bar & wait` — only the first `&`-backgrounded command
  inherits the cd; the others run from the original cwd. Use explicit cd
  inside each subshell or run sequentially.
- Lua's `io.open` defaults to block-buffered output. `setvbuf("line")` is
  required for the file to reflect per-record state during a long run.
- `--isolation` mode reads only from write-dir. Symlinking engine/pool/etc.
  into the sandbox makes archives discoverable without polluting the real
  install.
- Emscripten 5.0.6 needs CMake 3.27+. Ubuntu 22.04's 3.22.1 is too old.
  `pip install --user cmake` → cmake 4.3.2 on PATH.
