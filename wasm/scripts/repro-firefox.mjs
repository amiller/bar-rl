// Cross-browser repro: open the live deploy, click first card, capture errors.
// Tests Firefox + WebKit because their wasm worker init differs from Chromium.
import { firefox, webkit, chromium } from 'playwright';

const URL = process.argv[2] || 'https://bar-replay-demo.pages.dev';
const BROWSERS = process.argv[3] ? [process.argv[3]] : ['firefox', 'webkit', 'chromium'];

async function trial(name, browserType) {
  console.log(`\n=== ${name} ===`);
  const errs = [];
  let browser;
  try {
    browser = await browserType.launch({ headless: true });
    const ctx = await browser.newContext();
    const page = await ctx.newPage();
    page.on('pageerror', e => errs.push('PAGEERR ' + e.message));
    page.on('console', m => {
      const t = m.text();
      if (m.type()==='error' || /Assertion|Aborted|WebAssembly|thread_profiler/.test(t)) {
        errs.push(`CONSOLE.${m.type()} ${t}`);
      }
    });
    await page.goto(`${URL}/viewer/engine.html`, { waitUntil: 'domcontentloaded', timeout: 30000 });
    await page.waitForFunction(() => /live=/.test(document.getElementById('any-replay-status')?.textContent || ''),
                               { timeout: 30000 });
    const btn = page.locator('#any-replay-list button:not([disabled])').first();
    const btnTxt = (await btn.textContent()).trim();
    console.log(`clicking: ${btnTxt}`);
    await btn.click();
    await page.waitForTimeout(60000);
    const log = await page.evaluate(() => document.getElementById('log')?.textContent || '');
    const stat = await page.evaluate(() => document.getElementById('any-replay-status')?.textContent || '');
    console.log(`status: ${stat}`);
    console.log(`errors captured: ${errs.length}`);
    errs.slice(0, 5).forEach(e => console.log('  ', e.slice(0, 250)));
    console.log('  last 4 log lines:');
    log.split('\n').slice(-4).forEach(l => console.log('    ' + l.slice(0, 160)));
  } catch (e) {
    console.log('TRIAL FAILED:', e.message);
  } finally {
    if (browser) await browser.close().catch(()=>{});
  }
  return errs.length;
}

const map = { firefox, webkit, chromium };
let total = 0;
for (const b of BROWSERS) {
  if (!map[b]) { console.log(`unknown browser: ${b}`); continue; }
  total += await trial(b, map[b]);
}
console.log(`\n=== ${total} total errors across ${BROWSERS.length} browsers ===`);
process.exit(total ? 1 : 0);
