#!/usr/bin/env python3
"""Browse + download BAR replays from bar-rts.com, drop into demos dir."""
import argparse, json, re, subprocess, sys, urllib.parse, urllib.request
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime
from pathlib import Path

BAR_DATA = Path.home() / ".local/state/Beyond All Reason"
DEMOS_DIR = BAR_DATA / "data/demos"
ENGINE_DIR = BAR_DATA / "engine"
STORAGE = "https://storage.uk.cloud.ovh.net/v1/AUTH_10286efc0d334efd917d476d7183232e/BAR/demos/"
API = "https://api.bar-rts.com/replays"
PRIME_ENV = {
    "__NV_PRIME_RENDER_OFFLOAD": "1",
    "__GLX_VENDOR_LIBRARY_NAME": "nvidia",
    "__VK_LAYER_NV_optimus": "NVIDIA_only",
}
# pr-downloader needs BAR's CDN, not the default springrts repos
PRD_ENV = {
    "PRD_RAPID_USE_STREAMER": "false",
    "PRD_RAPID_REPO_MASTER": "https://repos-cdn.beyondallreason.dev/repos.gz",
    "PRD_HTTP_SEARCH_URL": "https://files-cdn.beyondallreason.dev/find",
}

def get_json(url):
    with urllib.request.urlopen(url, timeout=15) as r:
        return json.load(r)

def list_replays(**filters):
    qs = urllib.parse.urlencode({"limit": 50, "endedNormally": "true", **filters})
    return get_json(f"{API}?{qs}")["data"]

_SKILL_RE = re.compile(r"-?\d+(\.\d+)?")

def _parse_skill(raw):
    if not raw: return None
    m = _SKILL_RE.search(raw)
    return float(m.group()) if m else None

def enrich_skills(replays, workers=16):
    """Fan-out detail-endpoint calls to attach each player's OpenSkill mu."""
    def fetch(r):
        try:
            d = get_json(f"{API}/{r['id']}")
            skills = {p["name"]: _parse_skill(p.get("skill"))
                      for t in d["AllyTeams"] for p in t["Players"]}
            r["_skills"] = skills
        except Exception:
            r["_skills"] = {}
        return r
    with ThreadPoolExecutor(max_workers=workers) as ex:
        list(ex.map(fetch, replays))

def _tier(mu):
    if mu is None: return "   ? "
    if mu >= 38:   return f"{mu:4.1f}★"  # elite
    if mu >= 33:   return f"{mu:4.1f}+"  # strong
    return f"{mu:4.1f} "

def fmt(r):
    t = datetime.fromisoformat(r["startTime"].replace("Z", "+00:00")).astimezone()
    dur = r["durationMs"] // 60000
    m = r["Map"]["scriptName"]
    skills = r.get("_skills", {})
    teams = []
    for team in r["AllyTeams"]:
        parts = []
        for p in team["Players"]:
            mu = skills.get(p["name"])
            parts.append(f"{p['name']}({mu:.0f})" if mu is not None else p["name"])
        for a in team.get("AIs", []):
            parts.append(f"AI:{a['shortName']}")
        tag = "★" if team["winningTeam"] else " "
        teams.append(f"{tag}{'/'.join(parts) or '—'}")
    mus = [v for v in skills.values() if v is not None]
    top = _tier(max(mus)) if mus else "   ? "
    return f"{t.strftime('%m-%d %H:%M')} {dur:>3}m {top} {m:<22}  {' vs '.join(teams)}"

def pick(replays, picker):
    lines = [f"{r['id']}|{fmt(r)}" for r in replays]
    if picker == "rofi":
        cmd = ["rofi", "-dmenu", "-i", "-p", "replay", "-format", "s", "-width", "80"]
    else:
        for i, r in enumerate(replays):
            print(f"[{i:2}] {fmt(r)}")
        choice = input("pick # (or q): ").strip()
        if choice == "q" or not choice.isdigit(): sys.exit(0)
        return replays[int(choice)]["id"]
    display = "\n".join(l.split("|", 1)[1] for l in lines)
    r = subprocess.run(cmd, input=display, capture_output=True, text=True)
    if r.returncode != 0 or not r.stdout.strip(): sys.exit(0)
    picked = r.stdout.strip()
    for l in lines:
        rid, disp = l.split("|", 1)
        if disp == picked: return rid
    sys.exit(1)

def download(rid):
    detail = get_json(f"{API}/{rid}")
    dest = DEMOS_DIR / detail["fileName"]
    if not dest.exists():
        DEMOS_DIR.mkdir(parents=True, exist_ok=True)
        url = STORAGE + urllib.parse.quote(detail["fileName"])
        print(f"downloading {detail['fileName']}")
        urllib.request.urlretrieve(url, dest)
    else:
        print(f"cached: {dest.name}")
    return dest, detail

def engine_for(engine_version):
    # Chobby names dirs like recoil_2025.06.19 or spring_105.1.1-...
    for d in ENGINE_DIR.iterdir() if ENGINE_DIR.exists() else []:
        if engine_version in d.name and (d / "spring").exists():
            return d
    # fallback: any installed engine
    for d in sorted(ENGINE_DIR.iterdir() if ENGINE_DIR.exists() else [], reverse=True):
        if (d / "spring").exists():
            print(f"warn: engine {engine_version} not installed, using {d.name}")
            return d
    sys.exit(f"no engine found in {ENGINE_DIR}")

def fetch_content(edir, game_version, map_name):
    prdl = edir / "pr-downloader"
    env = {**__import__("os").environ, **PRD_ENV}
    base = [str(prdl), "--filesystem-writepath", str(BAR_DATA)]
    for flag, val in [("--download-game", game_version), ("--download-map", map_name)]:
        if not val: continue
        print(f"  {flag} {val!r}")
        r = subprocess.run(base + [flag, val], env=env)
        if r.returncode != 0:
            print(f"  WARN: {flag} exited {r.returncode}")

def play(path, detail):
    edir = engine_for(detail["engineVersion"])
    map_name = detail.get("hostSettings", {}).get("mapname") or detail.get("Map", {}).get("scriptName")
    print(f"resolving content for {map_name!r} / {detail['gameVersion']!r}")
    fetch_content(edir, detail["gameVersion"], map_name)
    cmd = ["./spring", "--write-dir", str(BAR_DATA), "--isolation", str(path)]
    env = {**__import__("os").environ, **PRIME_ENV}
    print(f"launching engine {edir.name} with replay")
    subprocess.Popen(cmd, cwd=edir, env=env)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--preset", choices=["duel", "team", "ffa"], help="game type filter")
    ap.add_argument("--player", help="player name filter")
    ap.add_argument("--bots", action="store_true", help="allow matches with bots")
    ap.add_argument("--min-ts", type=float, help="minimum TrueSkill rating (pros ≈35+, top ≈40+)")
    ap.add_argument("--max-ts", type=float, default=100)
    ap.add_argument("--pro", action="store_true", help="shortcut: --preset duel --min-ts 35")
    ap.add_argument("--min-mins", type=int, help="minimum match duration (minutes)")
    ap.add_argument("--limit", type=int, default=50)
    ap.add_argument("--picker", choices=["rofi", "tty"], default="rofi")
    ap.add_argument("--play", action="store_true", help="invoke spring engine directly on replay (one-click watch)")
    ap.add_argument("--launch", action="store_true", help="open BAR launcher (Chobby) after download")
    ap.add_argument("--download-only", action="store_true")
    ap.add_argument("--no-skills", action="store_true", help="skip skill enrichment (faster)")
    args = ap.parse_args()

    if args.pro:
        args.preset = args.preset or "duel"
        args.min_ts = args.min_ts or 35

    filters = [("limit", args.limit), ("hasBots", "true" if args.bots else "false"),
               ("endedNormally", "true")]
    if args.preset: filters.append(("preset", args.preset))
    if args.player: filters.append(("players[]", args.player))
    if args.min_ts is not None:
        filters.append(("tsRange[]", args.min_ts))
        filters.append(("tsRange[]", args.max_ts))
    if args.min_mins:
        filters.append(("durationRangeMins[]", args.min_mins))
        filters.append(("durationRangeMins[]", 600))
    qs = urllib.parse.urlencode(filters)
    replays = get_json(f"{API}?{qs}")["data"]
    if not replays:
        print("no replays match"); sys.exit(1)
    if not args.no_skills:
        enrich_skills(replays)
    rid = pick(replays, args.picker)
    path, detail = download(rid)
    if args.play:
        play(path, detail)
    elif args.launch:
        subprocess.Popen(["bar"])
        print("launched BAR — pick from Replays menu")
    elif not args.download_only:
        print(f"\nrun: bar-replays --play  (to auto-launch), or open BAR manually")

if __name__ == "__main__":
    main()
