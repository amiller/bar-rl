#!/bin/bash
# Assemble wasm/pages-dist/ — the static deploy bundle for Cloudflare Pages.
# Mirrors viewer/ + build-wasm-browser/ + a landing page + _headers.
set -eu
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
WASM="$SCRIPT_DIR/.."
DIST="$WASM/pages-dist"
SRC_VIEWER="$WASM/viewer"
# Default to the pthread build if it exists (faster), else the single-thread one.
SRC_WASM="${SRC_WASM_DIR:-$WASM/build-wasm-browser-pthread}"
[[ -f "$SRC_WASM/spring-headless.wasm" ]] || SRC_WASM="$WASM/build-wasm-browser"

[[ -f "$SRC_WASM/spring-headless.wasm" ]] || { echo "missing $SRC_WASM/spring-headless.wasm — run wasm-build.sh browser first"; exit 1; }

rm -rf "$DIST"
mkdir -p "$DIST/viewer" "$DIST/build-wasm-browser"

# Viewer: copy index.html, engine.html, icons.json. Resolve the icons/ symlink
# (points at a real BAR install) so the bundle is self-contained.
cp "$SRC_VIEWER/index.html" "$SRC_VIEWER/engine.html" "$SRC_VIEWER/trace3d.html" "$SRC_VIEWER/icons.json" "$DIST/viewer/"
if [[ -L "$SRC_VIEWER/icons" ]]; then
  cp -rL "$SRC_VIEWER/icons" "$DIST/viewer/icons"
elif [[ -d "$SRC_VIEWER/icons" ]]; then
  cp -r "$SRC_VIEWER/icons" "$DIST/viewer/icons"
fi

# Engine artifacts.
cp "$SRC_WASM/spring-headless.js" "$SRC_WASM/spring-headless.wasm" "$DIST/build-wasm-browser/"
# pthread builds also emit a *.worker.js; copy if present so swap-in is free.
[[ -f "$SRC_WASM/spring-headless.worker.js" ]] && cp "$SRC_WASM/spring-headless.worker.js" "$DIST/build-wasm-browser/"

cp "$SCRIPT_DIR/pages-headers" "$DIST/_headers"
cp "$SCRIPT_DIR/pages-index.html" "$DIST/index.html"

# Sample bundles. SAMPLE_BUNDLE (single, legacy) → /sample/. SAMPLE_BUNDLES
# (colon-separated, multi) → /samples/<basename>/ + /samples/index.json.
if [[ -n "${SAMPLE_BUNDLE:-}" && -f "$SAMPLE_BUNDLE/manifest.json" ]]; then
  echo "including sample bundle from $SAMPLE_BUNDLE"
  rsync -a --delete --exclude='.git' "$SAMPLE_BUNDLE/" "$DIST/sample/"
  echo "  sample size: $(du -sh "$DIST/sample" | cut -f1)"
fi
# Persistent bundle dir: any subdir of wasm/sample-bundles/ with a manifest.json
# auto-ships. SAMPLE_BUNDLES (env) is still honored as an override/extension.
SBROOT="$WASM/sample-bundles"
if [[ -d "$SBROOT" ]]; then
  for d in "$SBROOT"/*/; do
    [[ -f "$d/manifest.json" ]] || continue
    SAMPLE_BUNDLES="${SAMPLE_BUNDLES:+$SAMPLE_BUNDLES:}${d%/}"
  done
fi

if [[ -n "${SAMPLE_BUNDLES:-}" ]]; then
  mkdir -p "$DIST/samples"
  index_entries=()
  IFS=':' read -ra dirs <<< "$SAMPLE_BUNDLES"
  for dir in "${dirs[@]}"; do
    [[ -f "$dir/manifest.json" ]] || { echo "skip (no manifest): $dir"; continue; }
    id="$(basename "$dir")"
    # Skip locally-built fat bundles. Cloudflare Pages caps at 20k files /
    # 25 MiB per file per deployment. Strace-trimmed bundles fit; full-pool
    # bundles (~17k files, ~2 GB) blow the file count and the wrangler queue.
    fcount="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('count', 0))" "$dir/manifest.json")"
    if (( fcount > 10000 )); then
      echo "  skip $id ($fcount files > 10000) — local-only, not deployable to Pages"
      continue
    fi
    # Pages also caps single files at 25 MiB. Per-replay bundles include the
    # raw .sd7 map (50–140 MB), which blows the per-file cap. Skip if any
    # file is over 24 MiB (leaving slack for the ceiling).
    bigfile="$(find "$dir" -type f -size +24M -print -quit)"
    if [[ -n "$bigfile" ]]; then
      echo "  skip $id (file >24MiB: ${bigfile##*/}) — local-only, not deployable to Pages"
      continue
    fi
    echo "  bundling $id from $dir"
    rsync -a --delete --exclude='.git' "$dir/" "$DIST/samples/$id/"
    label="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('label', sys.argv[2]))" "$dir/manifest.json" "$id")"
    bytes="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('totalBytes', 0))" "$dir/manifest.json")"
    count="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('count', 0))" "$dir/manifest.json")"
    index_entries+=("$(printf '{"id":"%s","label":"%s","totalBytes":%s,"count":%s}' "$id" "$label" "$bytes" "$count")")
  done
  if (( ${#index_entries[@]} )); then
    printf '{"bundles":[%s]}\n' "$(IFS=,; echo "${index_entries[*]}")" > "$DIST/samples/index.json"
    echo "  samples index: $(cat "$DIST/samples/index.json")"
  fi
fi

# Release-bundles: per-gameVersion engine substrate without replay.sdfz. Each
# is built by release-bundle.py and shared across every replay on that release.
# Combined with the worker proxy (workers/replay-proxy.js), engine.html can
# play any replay matching one of these releases without a per-replay bundle.
RBROOT="$WASM/release-bundles"
if [[ -d "$RBROOT" ]]; then
  mkdir -p "$DIST/releases"
  rel_entries=()
  for d in "$RBROOT"/*/; do
    [[ -f "$d/manifest.json" ]] || continue
    id="$(basename "$d")"
    echo "  release-bundle $id"
    rsync -a --delete --exclude='.git' "$d/" "$DIST/releases/$id/"
    label="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('label', sys.argv[2]))" "$d/manifest.json" "$id")"
    gv="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('gameVersion',''))" "$d/manifest.json")"
    bytes="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('totalBytes', 0))" "$d/manifest.json")"
    count="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('count', 0))" "$d/manifest.json")"
    maps="$(python3 -c "import json,sys; print(json.dumps(json.load(open(sys.argv[1])).get('maps', [])))" "$d/manifest.json")"
    rel_entries+=("$(printf '{"id":"%s","label":"%s","gameVersion":"%s","maps":%s,"totalBytes":%s,"count":%s}' "$id" "$label" "$gv" "$maps" "$bytes" "$count")")
  done
  if (( ${#rel_entries[@]} )); then
    printf '{"releases":[%s]}\n' "$(IFS=,; echo "${rel_entries[*]}")" > "$DIST/releases/index.json"
    echo "  releases index: $(cat "$DIST/releases/index.json")"
  fi
fi

# Mirror local .jsonl traces into pages-dist/traces/ so engine.html's
# "Recent pro replays" panel has something to show. refresh-traces.py also
# writes here; this is the cheap path that uses already-captured local
# traces (no API call, no engine rerun).
python3 "$SCRIPT_DIR/populate-traces-from-local.py" || true

du -sh "$DIST" "$DIST/build-wasm-browser/spring-headless.wasm"
echo "ready: $DIST"
echo "deploy: npx wrangler pages deploy $DIST --project-name=<your-project>"
