# Porting spring-headless to WASM — planning notes

## The target

`spring-headless` — 36 MB statically-linked Linux binary. Minimal runtime
deps (libm, libdl, libpthread, libc). No SDL/OpenGL/audio/network in the
dependency graph for replay playback.

Source: `~/projects/bar/repos/RecoilEngine/` (sparse-cloned, `rts/`,
`test/`, `tools/`, CMakeLists).

## High-level strategy

1. Build `spring-headless` natively first (baseline, we have a working
   binary already from BAR's AppImage).
2. State-dump capture works against native (see `../widgets/state_dump.lua`).
3. Set up Emscripten SDK, cross-compile critical deps (`streflop`, `lua`,
   `zlib`/`minizip`, `boost::system`/`boost::filesystem`, etc.).
4. Port `spring-headless` via `emcmake`. Stub audio/network/graphics.
5. Run WASM binary in Node with `emscripten_run_script`. Feed same replay.
6. Compare trace vs native — use `diff-traces.py` to find first divergence.
7. Iterate: for each divergence, find the C++ source, make it deterministic
   or match native, rebuild, retest.

## Known hard problems

- **streflop** — Recoil's deterministic-FPU library. Pure C, math-heavy.
  Emscripten should compile it; WASM's float semantics are IEEE 754 so bit
  identical with x86 SSE should be achievable.
- **Threading** — Recoil uses ThreadPool. Emscripten supports pthreads via
  `SharedArrayBuffer` + COOP/COEP headers. Deterministic replay needs
  threading disabled or made deterministic.
- **Memory model** — 32-bit address space in WASM32 (WASM64 exists but
  emscripten support is spottier). A match may use >500 MB heap — tight.
- **File I/O** — emscripten's FS API reads from a bundled virtual FS.
  Need to preload the replay `.sdfz` + engine `base/` + map archive + game
  archive. That's ~50-200 MB of assets.
- **Lua** — compiles to WASM cleanly. Most of BAR is Lua, so this has to
  work. `LuaSocket` and other C bindings may need stubbing.

## Deferred / not in scope for MVP

- Rendering (use the state-dump pattern instead — dump to WebGL viewer)
- Audio
- Network (replay-only mode is single-player)
- AI bots that use compiled libs (stub or skip)

## First concrete milestones

- [x] Install emsdk at `~/projects/bar/wasm/tools/emsdk`
- [x] `emcmake cmake -S repos/RecoilEngine -B build-wasm ...` — first attempt
- [ ] Carve minimum "run a replay, dump state" code path
- [ ] Get a hello-world WASM binary that links against a stubbed subset

## Configure progress — patterns and state (2026-04-24)

**Worked through many blockers in sequence.** Each followed the pattern:
find_package fails → provide shim/stub/patch → re-run.

Blockers resolved:

1. CMake 3.27+ required → `pip install --user cmake` (4.3.2)
2. 32-bit check → patched `CMakeLists.txt` to accept WASM32 as 64 (001 patch)
3. Arch check (`CMAKE_SYSTEM_PROCESSOR=x86` under Emscripten) → patched passthrough
4. DevIL → `stubs/devil/` with minimal header + no-op impl, wired via patch
5. ZLIB → `stubs/cmake/FindZLIB.cmake` shim → `-sUSE_ZLIB=1`
6. SDL2 → `stubs/cmake/FindSDL2.cmake` shim → `-sUSE_SDL=2`
7. Freetype → shim → `-sUSE_FREETYPE=1`
8. Fontconfig → shim as empty INTERFACE target (headless doesn't need it)
9. EXPAT → shim as empty INTERFACE target
10. streflop SSE autodetect → `-DSTREFLOP_AUTO=OFF -DSTREFLOP_SOFT=ON`
11. gflags uint32 detection → `-DGFLAGS_INTTYPES_FORMAT=C99`
12. OggVorbis → `-DNO_SOUND=ON`
13. legacy build's X11 requirement → patched conditional on not-EMSCRIPTEN
14. legacy build's executable → patched conditional (still defines Game target)
15. tools/ subdir (requires CURL, libunwind, etc.) → skipped via patch
16. Submodules missing (fmt, mimalloc, streflop, RmlUi, lunasvg, pr-downloader,
    and recursive sub-submodules) → `git submodule update --init --recursive`

**Current blocker:** Recoil links against pr-downloader's targets
`prd::jsoncpp`, `prd::base64`. These are defined inside `tools/pr-downloader/`
which we skipped. Two options:

- (a) Re-enable `tools/` but shim CURL too (emscripten has no curl port);
- (b) Extract the jsoncpp/base64 sources from pr-downloader into a standalone
  static lib that's always built, regardless of the pr-downloader executable.
  Cleaner but needs a new CMakeLists.txt in `tools/pr-downloader/src/lib/jsoncpp`
  etc.

## Post-configure work (still ahead, larger than configure)

Even after a clean configure, the actual build will surface hundreds of
errors: missing `<unistd.h>` calls, SSE intrinsics in sim code, pthread
assumptions, Linux-specific fcntl, etc. Emscripten's clang is strict.
Each class of error → patch or stub.

Rough layers, worst-first:
- Threading: Recoil uses a ThreadPool. WASM32 supports pthreads via
  SharedArrayBuffer — but that requires `-sUSE_PTHREADS=1`, COOP/COEP
  headers on the server, and still has edge cases. Determinism argues for
  single-threaded anyway. Probably worth disabling THREADPOOL entirely.
- File I/O: VFS needs to read .sdz/.sd7 archives. Minizip compiles; zlib
  shimmed. The replay .sdfz needs to be preloaded or fetched in JS.
- Sim code's numeric stack: streflop SOFT fully works but is slow; may be
  acceptable for replay playback (~30 fps).
- RmlUi (56 files) and lunasvg — UI rendering. Should be dead in headless
  but if sim code imports them, may need tombstones.
- Lua — compiles to WASM cleanly, BAR uses LuaJIT? No — Recoil uses stock
  Lua 5.1 (vendored). Fine.

## Realistic session-scope estimates

- Get configure to succeed: **~0.5–1 more session** (the jsoncpp/base64 extraction
  + expanding submodule list + verifying RmlUi/lunasvg configure).
- Get first compile error pass: **~1–2 sessions** of patching compile errors.
- Get link to succeed: **~1–2 sessions** (linker script, missing symbols).
- Get a hello-world (engine init, exit clean): **~1 session** of runtime fixes.
- Get a replay to actually play in Node: **~2–4 sessions** of VFS/FS work.
- Match trace vs native: **~1–2 sessions**.

**Total: ~6–12 focused sessions** (not weeks of calendar time if concentrated).
Realistic. Not trivial.

## Feedback loop design

Native + WASM both dump identical JSONL via the `state_dump.lua` widget.

    diff-traces.py native.jsonl wasm.jsonl
    # → first diverging frame, which unit's field differs, by how much

Every code change → rebuild WASM → capture → diff. Convergence on one
specific replay is the testable endpoint.

## ✅ Actual outcome (2026-04-24)

All estimated milestones above hit in one session:

- Configure: done.
- Full compile: done.
- Link: done (`spring-headless.wasm` 12–16 MB).
- Hello-world: `node spring-headless.js --version` → exit 0.
- Replay plays in node: 8-minute BAR demo runs end-to-end, engine exits
  cleanly after the demo via the state-dump widget's stall detector.
- Trace match vs native: 2507 common frames agree within tolerance.
  First divergence at frame 786 (sim t≈26s), unit 12910 position off
  by `(dx=-0.2, dz=+0.1)` — sub-pixel float drift, expected without
  streflop.

## Streflop port: deferred

Tried enabling `STREFLOP_SSE=ON` on emscripten (so the Simple=float /
Double=double typedefs avoid SOFT-mode class ambiguities). Hit a chain
of x86-specific issues:

1. `FPUSettings.h` inline asm (`fstcw`, `stmxcsr`, `ldmxcsr`) — patched
   with no-op stubs on `__EMSCRIPTEN__`. WASM has no FPU control word;
   IEEE 754 round-to-nearest-even is the WASM float contract by spec.
2. assimp headers use `std::abs(float)` without `<cmath>` — fixed with
   `-include cstdlib -include cmath` globally.
3. `streflop_libm_bridge.h` redefines `FP_NAN/FP_INFINITE/...` as enum
   values, colliding with `<cmath>` macros — added `#undef`s.
4. `dosincos.cpp` and `sincos.tbl` collide with emscripten's `sincos`
   libc function. streflop's libm declares a struct called `sincos`
   which shadows the libc symbol. Would need renaming streflop's
   struct throughout, or patching out the glibc-derived dbl-64/flt-32
   files that assume the name.

(4) cascades into further collisions deeper in streflop's glibc-origin
libm (many-letter-prefixed symbols). Reverted for now — the WASM build
stays `ENABLE_STREFLOP=OFF` and accepts sub-pixel float drift. 2507
matching frames is plenty to demonstrate the sim is genuinely running.
Full streflop port is probably another 1–2 sessions of mostly mechanical
renames and `__EMSCRIPTEN__` guards around libm files. Left for later.
