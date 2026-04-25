#!/usr/bin/env python3
"""Pull a handful of recent 1v1 replays from the bar-rts API for end-to-end
outcome comparison between native engine and our WASM port."""
import json, os, pathlib, sys, urllib.parse, urllib.request

API = "https://api.bar-rts.com/replays"
STORAGE = "https://storage.uk.cloud.ovh.net/v1/AUTH_10286efc0d334efd917d476d7183232e/BAR/demos/"
DEST = pathlib.Path.home() / ".local/state/Beyond All Reason/data/demos"
DEST.mkdir(parents=True, exist_ok=True)

def detail(rid):
    with urllib.request.urlopen(f"{API}/{rid}", timeout=15) as r:
        return json.load(r)

def fetch(rid):
    d = detail(rid)
    fname = d["fileName"]
    dst = DEST / fname
    if dst.exists() and dst.stat().st_size > 0:
        print(f"  cached: {fname}"); return dst
    url = STORAGE + urllib.parse.quote(fname)
    print(f"  downloading {fname} ({d['durationMs']/60000:.1f}min)...")
    with urllib.request.urlopen(url, timeout=120) as r, dst.open("wb") as f:
        f.write(r.read())
    return dst

def main():
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 3
    # Recent finished games, 8-15 min, 1v1, no bots, no spectators-only
    with urllib.request.urlopen(f"{API}?limit=60", timeout=15) as r:
        listing = json.load(r)
    picks = []
    for r in listing.get("data", []):
        if r.get("hasBots"): continue
        dur = r.get("durationMs", 0) / 60000
        if not (8 <= dur <= 14): continue
        ats = r.get("AllyTeams", [])
        if len(ats) != 2: continue
        if sum(len(a.get("Players", [])) for a in ats) != 2: continue
        picks.append(r)
        if len(picks) >= n: break
    print(f"picked {len(picks)} 1v1 replays:")
    for r in picks:
        print(f"  {r['id'][:24]} | {r['durationMs']/60000:5.1f}min | {r.get('Map',{}).get('scriptName','?')}")
    print()
    paths = []
    for r in picks:
        paths.append(str(fetch(r["id"])))
    print()
    print("downloaded:")
    for p in paths: print(p)

if __name__ == "__main__":
    main()
