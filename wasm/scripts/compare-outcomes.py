#!/usr/bin/env python3
"""Compare GameOver outcomes between two outcome.jsonl files.

Usage: compare-outcomes.py <native.outcome.jsonl> <wasm.outcome.jsonl>

Reports: did they match on winner, end-frame (within tolerance), and final
per-team unit count? This is the metric for "is the WASM viewer faithful for
end-of-game purposes" — we don't need bit-exact mid-game state for replay
watching, just the same outcome.
"""
import json, sys
from pathlib import Path

def load(p):
    out = []
    with open(p) as f:
        for line in f:
            line = line.strip()
            if line:
                out.append(json.loads(line))
    return out

def find_event(records, label):
    for r in records:
        if r.get("event") == label:
            return r
    return None

def summarize(rec, label):
    print(f"  {label}:")
    print(f"    event:   {rec.get('event')}")
    print(f"    frame:   {rec.get('frame')}  ({rec.get('frame', 0)/30:.1f}s sim)")
    print(f"    winners: {rec.get('winners')}")
    teams = rec.get("teams", [])
    for t in teams:
        defs = t.get("defs", {})
        top_defs = sorted(defs.items(), key=lambda kv: -kv[1])[:3]
        top_str = ", ".join(f"{d}:{c}" for d, c in top_defs)
        print(f"    team {t['t']}: {t['units']:3d} units, m={t['m']:7.0f} e={t['e']:7.0f}  top: {top_str}")

def main():
    if len(sys.argv) != 3:
        print(__doc__); sys.exit(2)

    a = load(sys.argv[1])
    b = load(sys.argv[2])

    print(f"=== {Path(sys.argv[1]).name} ===")
    a_end = find_event(a, "gameover") or find_event(a, "shutdown") or (a[-1] if a else None)
    if a_end is None:
        print("  NO outcome events"); return
    summarize(a_end, "end-of-game")

    print()
    print(f"=== {Path(sys.argv[2]).name} ===")
    b_end = find_event(b, "gameover") or find_event(b, "shutdown") or (b[-1] if b else None)
    if b_end is None:
        print("  NO outcome events"); return
    summarize(b_end, "end-of-game")

    print()
    print("=== diff ===")
    if a_end.get("event") != b_end.get("event"):
        print(f"  event differs: {a_end['event']} vs {b_end['event']}")
    if a_end.get("winners") != b_end.get("winners"):
        print(f"  WINNERS DIFFER: {a_end['winners']} vs {b_end['winners']}")
    else:
        print(f"  winners match: {a_end['winners']}")
    fa, fb = a_end.get("frame", 0), b_end.get("frame", 0)
    print(f"  frame: {fa} vs {fb}  (delta={fb-fa}, {(fb-fa)/30:+.1f}s)")
    a_teams = {t["t"]: t for t in a_end.get("teams", [])}
    b_teams = {t["t"]: t for t in b_end.get("teams", [])}
    for tid in sorted(set(a_teams) | set(b_teams)):
        ta = a_teams.get(tid, {"units":0})
        tb = b_teams.get(tid, {"units":0})
        unit_diff = tb["units"] - ta["units"]
        marker = "" if unit_diff == 0 else f" Δ={unit_diff:+d}"
        print(f"  team {tid}: {ta['units']:3d} units (native) vs {tb['units']:3d} (wasm){marker}")

if __name__ == "__main__":
    main()
