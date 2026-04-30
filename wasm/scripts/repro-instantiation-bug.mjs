// Stress reproducer for the wasm instantiate / thread_profiler bugs the user
// hits in real browsers but which agent headless-shell tests don't catch.
//
// Strategy:
//  - Use FULL chromium binary (not chromium-headless-shell which is what
//    playwright's default headless mode uses) — same engine real users get.
//  - Run multiple iterations: each opens the page fresh (no cache), clicks
//    the first available Play card, watches for any error/assertion.
//  - Uses --no-cache + clears profile between runs to surface init races.
//
// Usage:  node repro-instantiation-bug.mjs [pages-url] [iterations]

import { chromium } from 'playwright';
import { mkdtempSync, rmSync } from 'fs';
import { tmpdir } from 'os';
import path from 'path';

const PAGES = process.argv[2] || 'https://bar-replay-demo.pages.dev';
const ITERATIONS = +(process.argv[3] || 5);

// FULL chromium binary path (not headless-shell)
const FULL_CHROMIUM = '/home/amiller/.cache/ms-playwright/chromium-1208/chrome-linux64/chrome';

const ALERTS = ['Assertion failed', 'Aborted', 'WebAssembly.instantiate',
                'thread_profiler', 'pageerror', 'Uncaught'];

let totalErrs = 0;

for (let i = 0; i < ITERATIONS; i++) {
  console.log(`\n=== iteration ${i+1}/${ITERATIONS} ===`);
  const profile = mkdtempSync(path.join(tmpdir(), 'pw-prof-'));
  let browser;
  const errs = [];
  try {
    const ctx = await chromium.launchPersistentContext(profile, {
      headless: true,
      executablePath: FULL_CHROMIUM,
      args: ['--no-sandbox', '--headless=new', '--disable-gpu'],
    });
    browser = ctx.browser();
    const page = await ctx.newPage();
    page.on('pageerror', e => { errs.push('PAGEERR ' + e.message); });
    page.on('console', m => {
      const t = m.text();
      if (m.type() === 'error') errs.push('CONSOLE.ERR ' + t);
      else if (ALERTS.some(s => t.includes(s))) errs.push('CONSOLE.' + m.type() + ' ' + t);
    });
    await page.goto(`${PAGES}/viewer/engine.html`, { waitUntil: 'domcontentloaded', timeout: 30000 });
    await page.waitForFunction(() => /live=/.test(document.getElementById('any-replay-status')?.textContent || ''),
                               { timeout: 30000 });
    // Click first non-disabled play button.
    const btn = page.locator('#any-replay-list button:not([disabled])').first();
    const btnTxt = (await btn.textContent()).trim();
    console.log(`clicking: ${btnTxt}`);
    await btn.click();
    // Wait 60 seconds — pool planting takes ~25s, then wasm boots & runs
    await page.waitForTimeout(60000);
    const log = await page.evaluate(() => document.getElementById('log')?.textContent || '');
    const stat = await page.evaluate(() => document.getElementById('any-replay-status')?.textContent || '');
    const lastFrameMatch = log.match(/\[f=(\d+)\]/g);
    const lastFrame = lastFrameMatch ? lastFrameMatch[lastFrameMatch.length - 1] : 'none';
    console.log(`status: ${stat}`);
    console.log(`last frame: ${lastFrame}`);
    if (errs.length) {
      console.log(`✗ ${errs.length} errors:`);
      errs.slice(0, 5).forEach(e => console.log('  ', e.slice(0, 200)));
      totalErrs += errs.length;
    } else {
      console.log('✓ no errors');
    }
    // Always dump tail of #log so we can see if engine is actually running.
    console.log('  last 6 log lines:');
    log.split('\n').slice(-6).forEach(l => console.log('    ' + l.slice(0, 160)));
  } catch (e) {
    console.log('iteration failed:', e.message);
    totalErrs++;
  } finally {
    if (browser) await browser.close().catch(()=>{});
    else { /* persistent ctx; close from any reference */ }
    try { rmSync(profile, { recursive: true, force: true }); } catch {}
  }
}

console.log(`\n=== summary: ${totalErrs} errors across ${ITERATIONS} iterations ===`);
process.exit(totalErrs > 0 ? 1 : 0);
