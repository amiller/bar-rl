#!/usr/bin/env python3
"""Compare two unit-motion probe JSONL files. Pinpoint first diverging field.

Usage: diff-probe.py <native.probe.jsonl> <candidate.probe.jsonl> [--uid=N]

Prints, per probed unit, the first frame where any field diverges and a
short context window of frames around the onset. Useful for narrowing
down whether divergence starts in heading, velocity, position, command
queue, or move-type internals.
"""
import json, sys
from collections import defaultdict

def load(p):
    by_uid = defaultdict(dict)  # uid -> {frame: record}
    with open(p) as f:
        for line in f:
            line = line.strip()
            if not line: continue
            r = json.loads(line)
            by_uid[r['u']][r['f']] = r
    return by_uid

def fields(r):
    """Flatten record into (key, value) pairs we want to diff."""
    out = []
    out.append(('h', r['h']))
    out.append(('cmd', r.get('cmd')))
    for axis, v in zip('xyz', r['p']): out.append((f'p_{axis}', v))
    for axis, v in zip('xyz', r['v']): out.append((f'v_{axis}', v))
    for axis, v in zip('xyz', r['d']): out.append((f'd_{axis}', v))
    mt = r.get('mt') or {}
    for k, v in mt.items(): out.append((f'mt.{k}', v))
    return out

def diff_records(a, b):
    """Return list of (key, a_val, b_val) for differing keys."""
    af = dict(fields(a)); bf = dict(fields(b))
    out = []
    for k in af.keys() | bf.keys():
        if af.get(k) != bf.get(k):
            out.append((k, af.get(k), bf.get(k)))
    return out

def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    flag_uid = next((a for a in sys.argv[1:] if a.startswith('--uid=')), None)
    if len(args) != 2:
        print(__doc__); sys.exit(2)
    A, B = load(args[0]), load(args[1])
    target_uids = [int(flag_uid.split('=', 1)[1])] if flag_uid else sorted(set(A) & set(B))

    for uid in target_uids:
        if uid not in A or uid not in B:
            print(f"\n[uid {uid}] not present in both traces"); continue
        common = sorted(set(A[uid]) & set(B[uid]))
        print(f"\n=== uid {uid} : {len(common)} common frames ({common[0]}..{common[-1]}) ===")
        first = None
        for f in common:
            d = diff_records(A[uid][f], B[uid][f])
            if d:
                first = (f, d); break
        if first is None:
            print("  identical across all common frames")
            continue
        f, diffs = first
        print(f"  first divergent frame: {f}")
        for k, a, b in sorted(diffs):
            print(f"    {k}: {a!r} → {b!r}")
        # Print context: 5 frames before, the divergent frame, 5 after
        print("\n  context (* = first divergent field appears here):")
        for ff in [x for x in common if abs(x - f) <= 5]:
            ar, br = A[uid][ff], B[uid][ff]
            d = diff_records(ar, br)
            marker = '*' if d else ' '
            divs = ','.join(k for k, _, _ in d) if d else '-'
            print(f"    f={ff:5d} {marker} hdg N={ar['h']} W={br['h']}  cs N={ar.get('mt',{}).get('cs','?')} W={br.get('mt',{}).get('cs','?')}  diff={divs}")

if __name__ == '__main__':
    main()
