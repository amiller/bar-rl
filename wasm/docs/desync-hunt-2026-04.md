# Desync hunt: WASM viewer vs. recorded demos

Notes from the April 2026 session that took the WASM viewer from "doesn't
reproduce demos" to **zero DESYNC warnings on the BarR + Great Divide demos**.
The fix turned out to be one line of UB in the COB callin layer, found via
a step-level oracle pipeline that's worth reusing on any deterministic-port
problem (game engines, RL envs, GPU kernels, etc.).

## What's actually in the demo file

Spring/Recoil `.sdfz` files embed the *recording engine's* periodic sync
checksums (one per ~30 frames per player). On replay, your engine recomputes
the same checksums and emits

    [DESYNC WARNING] checksum X from demo player Y does not match our checksum Z
                     for frame-number F

on every divergence. **This is a free, frame-by-frame oracle.** Without it
this port would have stayed in "outcomes look kinda different" purgatory.

## Why outcome-comparison (winner / unit count / commander deaths) is
a trap

We started by comparing end-of-game outcomes between WASM and a same-source
native build. They matched perfectly — same winner, same end frame, same 4
commander deaths at the same frames. We declared victory; the user said
"viewer doesn't work." Both were right: WASM and *our HEAD-built native*
agreed bit-for-bit, but **HEAD is 219 commits ahead and 61 commits behind
the recording engine**, so neither agreed with the demo. Outcomes are
*derivative* signals, swamped by latency drift and rounding cascade. Always
prefer step-level oracles when they exist.

## Pipeline that worked

Roughly four iteration loops, each tightening the ring:

1. **Match the source** — built native from the exact `2025.06.19` tag the
   demo was recorded against (in a docker container — host gcc-12 lacked
   `<format>`). That run emits zero DESYNCs, confirming the tag is the
   recording engine. Now any divergence is a target/codegen issue, not a
   source delta.
2. **Bisect frames via per-Sync history dump** — patched
   `rts/System/Sync/DumpState.cpp` to call `CSyncChecker::GetFrameHistory()`
   inline (engine had this buffer; the existing `DumpHistory()` was
   gated behind a cheat-mode check that didn't fire). With dumps at frame
   N, binary-searched 0–480 down to "first record of frame 470 differs".
3. **Bisect within a frame via abort + backtrace** — added
   `SYNC_PROBE_ABORT_FRAME=N SYNC_PROBE_ABORT_REC=M` env-gated `abort()`
   plus glibc `backtrace_symbols_fd`. `addr2line` against the docker-built
   binary turned the offsets into `CUnitScriptEngine::Tick:160` —
   `Sync::Assert(cs, "animating")` — the per-frame anim hash sync.
4. **Bisect among scripts** — instrumented the loop that computes `cs` to
   `fprintf` per-script `(idx, cs, unit_id, unit_name)` for one frame.
   16 of 17 animating scripts agreed; only `armwin` (the one wind
   generator) diverged. Wind direction = unique input → suspect narrowed.
5. **Per-target bit tests for math primitives.** Three throwaway
   programs (`scripts/streflop-bits-test.cpp`, `sqrt-bits-test.cpp`,
   `short-cast-test.cpp`) called specific functions on both targets and
   diffed bytes. Streflop libm: identical. `math::sqrt` / `math::isqrt`:
   identical. `static_cast<short>(36506.0f)`: **gcc-x86 = -29030,
   clang-wasm = 0**. Bug.

## The bug

Three call sites in `rts/Sim/Units/Scripts/CobInstance.cpp` —
`WindChanged`, `StartBuilding`, `AimWeapon` — all do

    Call(COBFN_..., short(heading * RAD2TAANG));

`heading ∈ [0, 2π)`, `RAD2TAANG = 32768/π`, so the product reaches 65536
— outside `short`'s `[-32768, 32767]`. C++ leaves the cast undefined;
gcc-x86 wraps modulo 2^16 (which the COB script expects), clang-wasm
saturates to 0.

Fix: `short(int(...))`. `int(float)` is well-defined for any in-range
float (65536 << INT_MAX); C++20+ makes `int → short` portable wraparound.
Lives in `wasm/patches/004-cob-portable-short-cast.patch`, auto-applied
by all three configure scripts.

## Cost

About six rebuilds + six replay runs end-to-end. Each replay run is
~3 min wall-clock to f=600. Most of that was waiting on docker builds
to relink (~30s incremental). Total active investigation: maybe 90
minutes of wall-clock; would have been a much harder unbounded problem
without the demo-checksum oracle.

## Reusable shape

The pattern works for any "port a deterministic environment to a new
backend" task:

1. Find a step-level oracle in the existing artifact (recorded checksums,
   trace logs, golden output).
2. Get the existing source building + running on the new backend, even
   if buggy.
3. Bisect via dumps until you have one diverging step + one diverging
   sub-component within that step.
4. Per-target bit tests on the suspect primitives (faster + clearer
   than reading code).
5. Fix the offending UB / non-portable codegen, not just the symptom.

What you don't want:
- Aggregate-level oracles ("does the final score match?"). Drift cascades
  hide the cause.
- Blind bisect over commit history (we wasted some loops on this — turned
  out HEAD wasn't even the right baseline).
- Source-level diff staring (the 998-record cascade looked terrifying;
  the *single* divergent record was buried at offset 1010 of one frame).

## Files

- Engine fix: `wasm/patches/004-cob-portable-short-cast.patch`
- Build pipeline auto-applies: `scripts/wasm-configure-tag.sh`,
  `wasm-configure-browser.sh`, `native-docker-build-tag.sh`
- Throwaway bit tests: `scripts/{streflop,sqrt,short-cast}-bits-test.cpp`
- Probe instrumentation (uncommitted, debug-only) in
  `repos/RecoilEngine-2025.06.19/rts/System/Sync/SyncChecker.cpp` and
  `rts/Sim/Units/Scripts/UnitScriptEngine.cpp`
