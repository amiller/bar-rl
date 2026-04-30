#!/usr/bin/env python3
"""Fast-iteration consistency check: play a .sdfz with one or both engines,
streaming engine stdout and killing the engine the moment its computed
checksum disagrees with the demo's recorded checksum (i.e. first DESYNC
WARNING). Way faster than waiting for game-over when you just want a bit
of signal.

Usage:
  desync-quick.py <replay.sdfz> [--native | --wasm | --both]
                  [--native-bin PATH] [--wasm-js PATH] [--max-sec N]

Output (one block per engine):
  ENGINE: native|wasm
  binary: <path>
  version: <Spring engine version>
  first divergence at frame <N>: our=<hex> demo=<hex>
   - or -
  no divergence reached frame <last> in <N>s
  exit reason: <killed-on-desync | timeout | clean>
"""

import argparse, os, re, signal, subprocess, sys, time
from pathlib import Path

PROJECT = Path(__file__).resolve().parent.parent  # wasm/
BAR_DATA = Path(os.environ['HOME']) / '.local/state/Beyond All Reason'
ENGINE_DIR = BAR_DATA / 'engine/recoil_2025.06.19'

DESYNC_RE = re.compile(
    r'\[DESYNC WARNING\] checksum ([0-9a-f]+) from demo .*?does not match our checksum ([0-9a-f]+) for frame-number (\d+)')
VERSION_RE = re.compile(r'Spring Engine Version:\s*(\S.*)')
FRAME_RE = re.compile(r'\[f=(\d+)\]')


def stream_until_desync(args, label, max_sec):
    """Run a command, stream stdout, kill on first DESYNC WARNING. Return dict."""
    print(f'\n=== {label} ===', flush=True)
    print(f'cmd: {" ".join(args)}', flush=True)
    t0 = time.time()
    proc = subprocess.Popen(
        args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        text=True, bufsize=1, preexec_fn=os.setsid)
    info = {'engine_version': None, 'first_desync': None,
            'last_frame': None, 'exit_reason': None}
    deadline = t0 + max_sec
    try:
        for line in proc.stdout:
            if time.time() > deadline:
                info['exit_reason'] = 'timeout'
                break
            mv = VERSION_RE.search(line)
            if mv and not info['engine_version']:
                info['engine_version'] = mv.group(1)
                print(f'engine: {info["engine_version"]}', flush=True)
            mf = FRAME_RE.search(line)
            if mf:
                info['last_frame'] = int(mf.group(1))
            md = DESYNC_RE.search(line)
            if md:
                demo_cks, our_cks, frame = md.group(1), md.group(2), int(md.group(3))
                info['first_desync'] = (frame, our_cks, demo_cks)
                info['exit_reason'] = 'killed-on-desync'
                print(f'  ✗ first divergence at frame {frame}: our={our_cks} demo={demo_cks}', flush=True)
                break
        if info['exit_reason'] is None and proc.poll() is not None:
            info['exit_reason'] = 'clean'
    finally:
        try:
            os.killpg(os.getpgid(proc.pid), signal.SIGTERM)
            proc.wait(timeout=5)
        except (ProcessLookupError, subprocess.TimeoutExpired):
            try: os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
            except ProcessLookupError: pass
    info['wall_seconds'] = round(time.time() - t0, 1)
    if info['first_desync'] is None:
        f = info['last_frame'] or 0
        print(f'  ✓ no divergence; reached f={f} (~{f/30:.1f}s sim) in {info["wall_seconds"]}s wall', flush=True)
    print(f'exit: {info["exit_reason"]}', flush=True)
    return info


def setup_native_sandbox(replay):
    """Mirror native-docker-run.sh's sandbox layout."""
    import tempfile, shutil
    sb = Path(tempfile.mkdtemp(prefix='bar-quickdesync-', dir='/tmp'))
    for d in ('engine', 'pool', 'packages', 'rapid', 'maps', 'games'):
        s = BAR_DATA / d
        if s.exists(): (sb / d).symlink_to(s)
    (sb / 'LuaUI/Widgets').mkdir(parents=True, exist_ok=True)
    (sb / 'LuaUI/Config').mkdir(parents=True, exist_ok=True)
    if (BAR_DATA / 'LuaUI/Fonts').exists():
        (sb / 'LuaUI/Fonts').symlink_to(BAR_DATA / 'LuaUI/Fonts')
    # Skip widget setup — we don't need state_trace/probe for desync-quick.
    (sb / '_launch.txt').write_text(
        f'[modoptions] {{ MinSpeed = 9999; MaxSpeed = 9999; }}\n'
        f'[game]       {{ demofile={replay}; hostport={31337 + (os.getpid() % 10000)}; }}\n')
    return sb


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('replay')
    ap.add_argument('--native', action='store_true')
    ap.add_argument('--wasm', action='store_true')
    ap.add_argument('--both', action='store_true')
    ap.add_argument('--native-bin', default=str(PROJECT / 'build-native-docker/spring-headless'),
                    help='native spring-headless binary path')
    ap.add_argument('--wasm-js', default=str(PROJECT / 'build-wasm/spring-headless.js'),
                    help='wasm spring-headless.js path (matched .wasm must be alongside)')
    ap.add_argument('--max-sec', type=int, default=900,
                    help='wall-time cap per engine')
    args = ap.parse_args()

    if not (args.native or args.wasm or args.both):
        args.both = True
    if args.both:
        args.native = args.wasm = True

    replay = str(Path(args.replay).resolve())
    if not Path(replay).is_file():
        print(f'no such replay: {replay}'); sys.exit(2)

    results = {}

    if args.native:
        sb = setup_native_sandbox(replay)
        bin_ = args.native_bin
        cmd = [bin_, '--write-dir', str(sb), '--isolation', './_launch.txt']
        # cd into sandbox so isolation finds _launch.txt
        os.chdir(sb)
        results['native'] = stream_until_desync(cmd, f'NATIVE  {bin_}', args.max_sec)
        results['native']['binary'] = bin_

    if args.wasm:
        wasm_js = args.wasm_js
        if not Path(wasm_js).is_file():
            print(f'no wasm js: {wasm_js}'); sys.exit(2)
        # Ensure base/ symlink (mirrors wasm-run.sh)
        base = BAR_DATA / 'base'
        if not base.exists():
            base.symlink_to(ENGINE_DIR / 'base')
        os.chdir(ENGINE_DIR)
        cmd = ['node', '--max-old-space-size=8192', wasm_js,
               '--write-dir', str(BAR_DATA), '--isolation=true', replay]
        results['wasm'] = stream_until_desync(cmd, f'WASM    {wasm_js}', args.max_sec)
        results['wasm']['binary'] = wasm_js

    print('\n=== SUMMARY ===')
    for k, v in results.items():
        d = v['first_desync']
        if d:
            print(f'  {k:<7} ✗ first divergence f={d[0]} (sim {d[0]/30:.1f}s)  '
                  f'our={d[1]} demo={d[2]}  ({v["engine_version"]})')
        else:
            f = v.get('last_frame') or 0
            print(f'  {k:<7} ✓ no divergence to f={f} (~{f/30:.1f}s sim)  ({v["engine_version"]})')
    if args.both and 'native' in results and 'wasm' in results:
        nd = results['native']['first_desync']
        wd = results['wasm']['first_desync']
        if nd and wd and nd[0] == wd[0]:
            print(f'\n  native and wasm match in their disagreement with demo at frame {nd[0]}')
        elif nd is None and wd is None:
            print('\n  both engines agree with demo through their wall-time runs ✓')


if __name__ == '__main__':
    main()
