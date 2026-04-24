#!/usr/bin/env python3
"""Serve the viewer + traces, plus endpoints to browse & capture replays.

Endpoints (layered on top of plain static serving of the wasm/ tree):

    GET  /api/traces                  -> {traces: [{name, size, lines}]}
    POST /api/capture  {replayId}     -> {traceName}   (downloads + captures if missing)

Run:  python3 scripts/serve.py [port]     (default 8765)
Open: http://localhost:8765/viewer/
"""
import http.server, json, os, socketserver, subprocess, sys, threading, urllib.parse, urllib.request
from pathlib import Path

PROJECT = Path(__file__).resolve().parent.parent
TRACES = PROJECT / "traces"
CAPTURE = PROJECT / "scripts/capture.sh"
BAR_DATA = Path.home() / ".local/state/Beyond All Reason"
BAR_DEMOS = BAR_DATA / "data/demos"
BAR_ENGINE = BAR_DATA / "engine"
BAR_MAPS = BAR_DATA / "maps"
API = "https://api.bar-rts.com/replays"
STORAGE = "https://storage.uk.cloud.ovh.net/v1/AUTH_10286efc0d334efd917d476d7183232e/BAR/demos/"
PRD_ENV = {
    "PRD_RAPID_USE_STREAMER": "false",
    "PRD_RAPID_REPO_MASTER": "https://repos-cdn.beyondallreason.dev/repos.gz",
    "PRD_HTTP_SEARCH_URL": "https://files-cdn.beyondallreason.dev/find",
}

# Serialize captures so we don't double-spawn spring-headless on the same machine.
_capture_lock = threading.Lock()

def _list_traces():
    out = []
    if not TRACES.is_dir(): return out
    for p in sorted(TRACES.glob("*.jsonl"), key=lambda p: p.stat().st_mtime, reverse=True):
        try: lines = sum(1 for _ in p.open())
        except Exception: lines = 0
        out.append({"name": p.name, "size": p.stat().st_size, "lines": lines})
    return out

def _get_detail(replay_id: str) -> dict:
    with urllib.request.urlopen(f"{API}/{replay_id}", timeout=15) as r:
        return json.load(r)

def _download_sdfz(detail: dict) -> Path:
    fname = detail["fileName"]
    dest = BAR_DEMOS / fname
    if dest.exists() and dest.stat().st_size > 0: return dest
    BAR_DEMOS.mkdir(parents=True, exist_ok=True)
    print(f"  downloading {fname}...", flush=True)
    with urllib.request.urlopen(STORAGE + urllib.parse.quote(fname), timeout=120) as r, dest.open("wb") as f:
        while chunk := r.read(1 << 20): f.write(chunk)
    return dest

def _engine_dir(version: str) -> Path | None:
    if not BAR_ENGINE.is_dir(): return None
    for d in BAR_ENGINE.iterdir():
        if version in d.name and (d / "pr-downloader").exists(): return d
    # fallback: any installed engine with pr-downloader
    for d in sorted(BAR_ENGINE.iterdir(), reverse=True):
        if (d / "pr-downloader").exists(): return d
    return None

def _ensure_content(detail: dict):
    """Run pr-downloader for the map + game the replay requires, using the scriptName
    from the bar-rts API directly instead of capture.sh's buggy filename heuristic."""
    edir = _engine_dir(detail.get("engineVersion", ""))
    if not edir:
        print("  warn: no engine dir found, skipping pr-downloader"); return
    prdl = edir / "pr-downloader"
    env = {**os.environ, **PRD_ENV}
    for flag, val in [("--download-map", detail["Map"].get("scriptName")),
                      ("--download-game", detail.get("gameVersion"))]:
        if not val: continue
        print(f"  pr-downloader {flag} {val!r}", flush=True)
        r = subprocess.run([str(prdl), "--filesystem-writepath", str(BAR_DATA), flag, val],
                           env=env, capture_output=True, text=True)
        if r.returncode != 0:
            # Non-fatal: if archive is already present, capture will still succeed.
            print(f"    (pr-downloader exit {r.returncode}: {r.stderr.strip()[-200:]})", flush=True)

def _capture(sdfz: Path) -> Path:
    out_name = sdfz.stem
    trace = TRACES / f"{out_name}.jsonl"
    if trace.exists() and trace.stat().st_size > 0:
        return trace
    with _capture_lock:
        if trace.exists() and trace.stat().st_size > 0: return trace
        print(f"  capturing {sdfz.name}...", flush=True)
        # FAST=1 disables non-essential widgets for much faster headless replay.
        r = subprocess.run(["bash", str(CAPTURE), str(sdfz), out_name],
                           env={**os.environ, "FAST": "1"})
        if r.returncode != 0 or not trace.exists():
            raise RuntimeError(f"capture.sh exit {r.returncode}")
    return trace

class Handler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, fmt, *args):
        sys.stderr.write("[%s] %s\n" % (self.log_date_time_string(), fmt % args))

    def _send_json(self, code, payload):
        body = json.dumps(payload).encode()
        self.send_response(code)
        self.send_header("content-type", "application/json")
        self.send_header("content-length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/api/traces":
            return self._send_json(200, {"traces": _list_traces()})
        return super().do_GET()

    def do_POST(self):
        if self.path == "/api/capture":
            try:
                n = int(self.headers.get("content-length", "0"))
                body = json.loads(self.rfile.read(n) or b"{}")
                replay_id = body["replayId"]
            except Exception as e:
                return self._send_json(400, {"error": f"bad request: {e}"})
            try:
                detail = _get_detail(replay_id)
                _ensure_content(detail)
                sdfz = _download_sdfz(detail)
                trace = _capture(sdfz)
                return self._send_json(200, {"traceName": trace.name})
            except Exception as e:
                import traceback; traceback.print_exc()
                return self._send_json(500, {"error": str(e)})
        self.send_error(404)

class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True

def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8765
    os.chdir(PROJECT)  # serve wasm/ root so /viewer/, /traces/, /icons.json resolve
    with Server(("", port), Handler) as s:
        print(f"serving at http://localhost:{port}/viewer/")
        s.serve_forever()

if __name__ == "__main__":
    main()
