#!/usr/bin/env python3
"""Compare two state-dump JSONL traces. Report first diverging frame/unit.

Usage: diff-traces.py <native.jsonl> <candidate.jsonl>

Exit code: 0 = identical within tolerance, 1 = diverges, 2 = schema/meta mismatch.
"""
import json, sys
from pathlib import Path

POS_TOL = 0.1   # world-units (Spring maps are in engine units; 1 = 1 map pixel)
HP_TOL  = 1     # percent

def load(path):
    meta = None
    frames = {}   # frame_num -> {uid: (team, defId, x, z, hp)}
    with open(path) as f:
        for line in f:
            r = json.loads(line)
            if r.get("t") == "meta":
                meta = r
            elif r.get("t") == "f":
                frames[r["f"]] = {u[0]: tuple(u[1:]) for u in r["u"]}
    return meta, frames

def main():
    if len(sys.argv) != 3:
        print(__doc__); sys.exit(2)
    a_meta, a = load(sys.argv[1])
    b_meta, b = load(sys.argv[2])

    if a_meta and b_meta:
        if (a_meta["mapX"], a_meta["mapZ"]) != (b_meta["mapX"], b_meta["mapZ"]):
            print(f"META MISMATCH: map size differs ({a_meta['mapX']}x{a_meta['mapZ']} vs {b_meta['mapX']}x{b_meta['mapZ']})")
            sys.exit(2)

    common_frames = sorted(set(a) & set(b))
    only_a = sorted(set(a) - set(b))
    only_b = sorted(set(b) - set(a))
    if only_a or only_b:
        print(f"frame coverage: {len(common_frames)} common, {len(only_a)} only-native, {len(only_b)} only-candidate")

    for f in common_frames:
        fa, fb = a[f], b[f]
        ids_a, ids_b = set(fa), set(fb)
        if ids_a != ids_b:
            missing = ids_a - ids_b
            extra   = ids_b - ids_a
            print(f"\n=== DIVERGENCE at frame {f} ===  unit set differs")
            if missing: print(f"  missing in candidate: {sorted(missing)[:10]}")
            if extra:   print(f"  extra in candidate:   {sorted(extra)[:10]}")
            sys.exit(1)
        for uid in sorted(ids_a):
            ta, da, xa, za, ha = fa[uid]
            tb, db, xb, zb, hb = fb[uid]
            if ta != tb or da != db:
                print(f"\n=== DIVERGENCE frame {f} uid {uid} ===  team/def: ({ta},{da}) vs ({tb},{db})")
                sys.exit(1)
            if abs(xa - xb) > POS_TOL or abs(za - zb) > POS_TOL:
                print(f"\n=== DIVERGENCE frame {f} uid {uid} ===")
                print(f"  native:    x={xa:.2f} z={za:.2f}")
                print(f"  candidate: x={xb:.2f} z={zb:.2f}")
                print(f"  delta: dx={xb-xa:+.3f} dz={zb-za:+.3f}")
                sys.exit(1)
            if abs(ha - hb) > HP_TOL:
                print(f"\n=== DIVERGENCE frame {f} uid {uid} ===  hp: {ha} vs {hb}")
                sys.exit(1)

    print(f"identical across {len(common_frames)} common frames (tol pos={POS_TOL}, hp={HP_TOL})")
    sys.exit(0)

if __name__ == "__main__":
    main()
