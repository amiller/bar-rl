// Live smoke-test: open the deployed Pages site, click the first N playable
// cards in turn, watch each engine session for errors. Captures whatever
// errors fire (instantiation, OOM, stack overflow, anything caught by
// window.__crashContext). This is what should run after every deploy AND
// on a regular cron — it exercises actual user flows.
//
// Usage:  node live-smoke-test.mjs [pages-url] [N] [waitSec]
//   pages-url:  default https://bar-replay-demo.pages.dev
//   N:          how many distinct playable cards to try (default 5)
//   waitSec:    seconds to watch each session (default 60)

import { chromium } from 'playwright';
import { mkdtempSync, rmSync, writeFileSync } from 'fs';
import { tmpdir } from 'os';
import path from 'path';

const PAGES = process.argv[2] || 'https://bar-replay-demo.pages.dev';
const N = +(process.argv[3] || 5);
const WAIT_SEC = +(process.argv[4] || 60);
const FULL_CHROMIUM = '/home/amiller/.cache/ms-playwright/chromium-1208/chrome-linux64/chrome';
const OUT_DIR = '/tmp/smoke-test-' + new Date().toISOString().replace(/[:.]/g, '-');

import { mkdirSync } from 'fs';
mkdirSync(OUT_DIR, { recursive: true });

const results = [];

for (let i = 0; i < N; i++) {
  const profile = mkdtempSync(path.join(tmpdir(), 'smoke-'));
  let ctx;
  const errors = [];
  let cardLabel = null, mapName = null, lastFrame = 0, crashCtx = null;

  try {
    ctx = await chromium.launchPersistentContext(profile, {
      headless: true,
      executablePath: FULL_CHROMIUM,
      args: ['--no-sandbox', '--headless=new', '--disable-gpu'],
    });
    const page = await ctx.newPage();
    page.on('pageerror', e => errors.push('PAGEERR: ' + e.message));
    page.on('console', m => {
      const t = m.text();
      if (m.type() === 'error' || /CRASH|Assertion|Aborted|RangeError|TypeError/.test(t)) {
        errors.push(`CONSOLE.${m.type()}: ${t.slice(0, 300)}`);
      }
    });
    await page.goto(`${PAGES}/viewer/engine.html`, { waitUntil: 'domcontentloaded', timeout: 30000 });
    await page.waitForFunction(() => / playable /.test(document.getElementById('any-replay-status')?.textContent || ''),
                               { timeout: 90000 });

    // Pick the i-th playable button (skipping disabled ones).
    const btns = page.locator('#any-replay-list button:not([disabled])');
    const count = await btns.count();
    if (i >= count) { console.log(`only ${count} playable cards, stopping`); break; }
    const btn = btns.nth(i);
    cardLabel = await btn.textContent();
    mapName = await btn.locator('xpath=../../div[1]').textContent().catch(() => '?');
    console.log(`\n[${i+1}/${N}] clicking: ${(mapName||'?').trim().slice(0,40)} — ${cardLabel.trim()}`);
    await btn.click();

    // Watch the session for waitSec, polling for crash context + frame progress.
    const start = Date.now();
    while (Date.now() - start < WAIT_SEC * 1000) {
      const snap = await page.evaluate(() => ({
        log: document.getElementById('log')?.textContent || '',
        crashCtx: window.__crashContext || null,
      })).catch(() => null);
      if (!snap) break;
      const frames = [...snap.log.matchAll(/\[f=(\d+)\]/g)].map(m => +m[1]);
      if (frames.length) lastFrame = Math.max(lastFrame, ...frames);
      if (snap.crashCtx) { crashCtx = snap.crashCtx; break; }
      await new Promise(r => setTimeout(r, 3000));
    }

    // One last sweep
    if (!crashCtx) {
      crashCtx = await page.evaluate(() => window.__crashContext || null).catch(() => null);
    }
  } catch (e) {
    errors.push('TEST FAIL: ' + e.message);
  } finally {
    if (ctx) await ctx.close().catch(()=>{});
    try { rmSync(profile, { recursive: true, force: true }); } catch {}
  }

  const result = {
    n: i+1,
    map: (mapName || '?').trim().slice(0, 40),
    label: (cardLabel || '?').trim(),
    lastFrame,
    pass: !crashCtx && errors.length === 0,
    crashCtx,
    errorCount: errors.length,
    firstError: errors[0] || null,
  };
  results.push(result);
  if (result.pass) {
    console.log(`  ✓ reached f=${lastFrame} (sim ${(lastFrame/30).toFixed(1)}s) clean`);
  } else {
    console.log(`  ✗ ${errors.length} errors / crash=${crashCtx ? 'yes' : 'no'}`);
    if (crashCtx) {
      console.log(`    why: ${crashCtx.why}`);
      const last = (crashCtx.memHistory || []).slice(-3);
      last.forEach(s => console.log(`    mem: ${s.t}s ${s.label} wasm=${s.wasmMB}MB jsHeap=${s.jsHeapMB}MB`));
    }
    if (errors.length) console.log(`    first error: ${errors[0].slice(0, 200)}`);
  }
}

const summary = {
  when: new Date().toISOString(),
  pagesUrl: PAGES,
  pass: results.filter(r => r.pass).length,
  fail: results.filter(r => !r.pass).length,
  results,
};
writeFileSync(path.join(OUT_DIR, 'summary.json'), JSON.stringify(summary, null, 2));

console.log(`\n=== summary: ${summary.pass} pass / ${summary.fail} fail across ${results.length} runs ===`);
console.log(`details: ${OUT_DIR}/summary.json`);

// Group failures by error signature so we can see if the same bug fires repeatedly.
const sigs = new Map();
for (const r of results) {
  if (r.pass) continue;
  const sig = r.crashCtx?.why || r.firstError || 'unknown';
  const norm = sig.slice(0, 80);
  sigs.set(norm, (sigs.get(norm) || 0) + 1);
}
if (sigs.size) {
  console.log('\nfailure signatures:');
  for (const [s, n] of [...sigs.entries()].sort((a,b)=>b[1]-a[1])) {
    console.log(`  ${n}× ${s}`);
  }
}

process.exit(summary.fail > 0 ? 1 : 0);
