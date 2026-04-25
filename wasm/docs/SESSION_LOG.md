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

### Streflop-SSE attempt #3 (~19:30–21:00)

Tried `ENABLE_STREFLOP=ON` + `STREFLOP_SSE=ON` again, this time with
`-include cstdlib -include cmath` forced into CXX flags to head off the
sincos.tbl symbol issue from attempt #2. Build linked successfully (with
the `-Wunsupported-floating-point-opt` rounding-mode warning emcc emits
for any `STMXCSR`/`LDMXCSR` inline asm). At runtime the engine never
advanced past `f=-000001` — `good_fpu_control_registers()` spammed
"FPUCW 0x0000 instead of 0x003A" every CGame::Update tick, because
streflop's asm stubs are no-ops in WASM and the env reads back as zero.

After bypassing the FPUCheck loop in WASM (added `__EMSCRIPTEN__`
early-return in `good_fpu_control_registers`), the engine *did* advance
— and desync'd at **f=420** (~366 frames *earlier* than streflop=OFF).
Streflop's typedef wrappers route sin/cos/fmod through its own impls,
which differ from emscripten's libm; without the rounding-mode pin to
make them deterministic, they just substitute a different flavor of
non-determinism for libm's.

**Conclusion (third confirmation):** streflop=ON in WASM is strictly
worse than streflop=OFF until/unless someone implements WASM-equivalent
rounding-mode pinning. That deferred work doesn't have an obvious WASM
path — `wasm_simd128.h` exposes data ops, not rounding-mode control.
Reverted `wasm-configure.sh` back to ENABLE_STREFLOP=OFF, kept the
FPUCheck WASM bypass (defensive, no effect with streflop OFF). Also
fixed an unconditional `target_link_libraries(... streflop)` in
`rts/builds/headless/CMakeLists.txt` that prevented ENABLE_STREFLOP=OFF
from actually unlinking streflop.

Trace match against native re-verified: same 408 common frames, same
divergence at f=786 unit 12910 dx=-0.2 dz=+0.1.

## 2026-04-25

### Streflop attempt #4 (this time it stuck) + commander-aim divergence hunt

Reversed the conclusion of attempt #3: streflop=ON does help, *a lot*. The
prior attempt's "streflop ON desyncs at f=420, worse than f=786 OFF" reading
mixed up two different runs. With ENABLE_STREFLOP=ON + STREFLOP_SSE=ON +
STREFLOP_AUTO=OFF (CMakeLists already skips the x86 flags on emscripten):

- WASM engine's per-frame sync checksum is **bit-faithful to the demo for
  frames 0 and 60** (was diverging at f=0 with streflop OFF). First desync
  pushed from f=0 → **f=120**.
- Wide per-frame probe of all units across f=0..200 shows positions, headings,
  velocities, *and* health/build-progress/team-resources are bit-identical
  native↔WASM through f=200. The remaining divergence lives in non-probed
  synced state.
- New `probe_unit_motion.lua` tracks the three commanders that originally
  diverged — uid 30611 is now bit-identical to native across all 1500 probed
  frames. uid 12910 still diverges, but at f=784 instead of f=685, and the
  intervening cs (currentSpeed) ULP drift is gone.
- Lua's `math.sin/cos/atan2/...` route through `math::*` via lmathlib.cpp,
  which goes through `streflop_cond.h`. Confirmed by reading
  `build-wasm/.../lua.dir/flags.make`: `-DSTREFLOP_SSE` is set on lua too.

`/DumpState` at f=60 (clean) and f=120 (first desync) via a new
`probe_dumpstate.lua` widget reveals the f=120 divergence is exactly:

- One commander unit (uid 30303 corcom) has divergent `aimy1` piece rotation
  hash, and downstream `weaponDir` / `weaponPos` / `weaponMuzzlePos` for both
  weapons. Unit base state (xdir, ydir, zdir, pos, speed, heading) is
  bit-identical between native and WASM at f=120. RNG `genState` matches.
  Just one piece on one commander.

Tried `-ffp-contract=off` engine-wide (added to `wasm-configure.sh`'s
`CMAKE_CXX_FLAGS`; verified propagated to engine, lua, streflop targets).
**No effect** on the f=120 divergence — emcc on wasm32 lacks scalar FMA, so
fp-contract was already a no-op on our side.

Hypothesis for what remains: animation tick (`TickTurnAnim`/`TickSpinAnim` →
`ClampRad` / `TurnToward`) for one specific commander script step produces a
slightly different float in our build vs the upstream BAR `recoil_2025.06.19`
binary. Could be a compiler-codegen difference (gcc vs emcc-clang), x87 vs
SSE intermediates, or auto-vectorization choice. We can't prove it without
building the native engine ourselves from the same source.

Native build attempt: scaffolded `wasm/scripts/native-configure.sh` +
`native-build.sh` plus a `BAR_USE_STUBS=1` env-gated patch to CMakeLists
(reuses the WASM DevIL/pr-downloader stubs) so we can build with system
deps. Hit a wall on RmlUi's `find_package(Freetype)` linkage despite system
freetype-dev being installed. Deferred — the missing piece for verifying
source-determinism is making that native build go through.

### Files / infrastructure added

- `wasm/widgets/probe_unit_motion.lua` — companion to state_dump; per-frame
  full-precision (pos/heading/velocity/dir/cmd/MoveTypeData) for picked
  uids, plus wide-coverage (all units + team resources + health) for the
  first 200 frames. Output: `unit_probe.jsonl`.
- `wasm/widgets/probe_dumpstate.lua` — triggers `/cheat 1` then
  `/dumpstate <f> <f>` at chosen frames, then `Spring.Quit()` shortly
  after — keeps test loops to ~2-3 min instead of 10.
- `wasm/scripts/diff-probe.py` — field-by-field diff of two probe traces,
  pinpoints first-divergent field per uid.
- `wasm/scripts/{native-configure,native-build}.sh` — scaffolding for the
  matching native build.
- `wasm/scripts/streflop-determinism-test.cpp` — minimal harness that
  bit-compares streflop's libm + ClampRad outputs across native/WASM
  builds (left in-progress; overload-resolution issues in standalone
  harness make it less useful than expected).
- `capture.sh` / `wasm-run.sh` — install all `wasm/widgets/*.lua`,
  preserve probe + dumpstate outputs in `traces/<name>.{probe.jsonl,dumpstates/}`,
  honor `HEADLESS=...` env override (so we can swap in a locally-built
  native binary).

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
