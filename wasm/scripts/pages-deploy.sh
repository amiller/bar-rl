#!/bin/bash
# Deploy wasm/pages-dist/ to Cloudflare Pages.
# First run: needs `npx wrangler login` (opens browser).
# Subsequent runs: just `bash pages-deploy.sh`.
set -eu
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
DIST="$SCRIPT_DIR/../pages-dist"
PROJECT="${CF_PAGES_PROJECT:-bar-replay-demo}"

# Always rebuild — viewer/engine artifacts change underneath us, and a stale
# pages-dist/ from a previous deploy is the most common cause of "I edited
# engine.html but the deploy didn't change".
bash "$SCRIPT_DIR/pages-build.sh"

# Create the project if it doesn't exist (idempotent: ignores "already exists").
npx --yes wrangler@latest pages project create "$PROJECT" --production-branch=main 2>&1 \
  | grep -v -E '^(✘|.*Error.*already.*exists)' || true

npx --yes wrangler@latest pages deploy "$DIST" --project-name="$PROJECT" --branch=main

# Post-deploy smoke gate. Runs against the live URL since CF Pages serves the
# canonical alias immediately. If a real-browser flow breaks, surface it now —
# we shipped enough silent regressions today (recursion in the mem probe,
# stale-cache stickiness, etc.) that not gating on this is reckless.
# Set BAR_SKIP_SMOKE=1 to bypass (e.g. when iterating on the smoke test itself).
if [[ "${BAR_SKIP_SMOKE:-0}" != "1" ]]; then
  # 180s wait so the engine clears pool-planting (~30-40s) + lua init and
  # actually reaches sim frames. Catching "boots clean but f=0" misses the
  # interesting failures (mid-game OOM, sim divergence) that we care about.
  echo "post-deploy smoke test (3 replays × 180s wait)..."
  if node "$SCRIPT_DIR/live-smoke-test.mjs" https://bar-replay-demo.pages.dev 3 180; then
    echo "✓ smoke pass"
  else
    echo
    echo "================================================================"
    echo "✗ SMOKE TEST FAILED — live deploy is broken in real browsers."
    echo "  CF Pages has no rollback CLI; either:"
    echo "    1) hit a previous versioned URL (wrangler pages deployment list)"
    echo "    2) revert the change locally and re-run pages-deploy.sh"
    echo "  Diagnostics in /tmp/smoke-test-*/summary.json"
    echo "================================================================"
    exit 1
  fi
fi
