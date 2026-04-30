// Headless-browser desync check: opens /viewer/engine.html (which loads the
// 2025.06.19 pthread wasm — same as deployed Pages), plays a specific replay
// by ID, and watches #log for [DESYNC WARNING] lines. Kills the page the
// moment one appears.
//
// Usage:
//   node desync-quick-browser.mjs <pages-base-url> <replay-id> [release-id] [maxSec]
//
// Example:
//   node desync-quick-browser.mjs http://localhost:8765 \
//        a1b2c3... Beyond_All_Reason_test-30018-d71d659 600
//
// Reports first DESYNC frame, or "no divergence to f=N" if game ended / max-sec hit.
import { chromium } from 'playwright';

const [base, replayId, releaseId, maxStr] = process.argv.slice(2);
const MAX_S = +(maxStr || 600);
if (!base || !replayId) {
  console.error('usage: desync-quick-browser.mjs <pages-url> <replay-id> [release-id] [maxSec]');
  process.exit(2);
}

const browser = await chromium.launch({ headless: true });
const ctx = await browser.newContext();
const page = await ctx.newPage();
page.on('pageerror', e => console.log('[pageerror]', e.message));
page.on('crash', () => console.log('[host] page crashed'));

const url = `${base}/viewer/engine.html`;
console.log('open', url);
await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 30000 });
await page.waitForFunction(() => /live=/.test(document.getElementById('any-replay-status')?.textContent || ''),
                           { timeout: 30000 });
console.log('engine.html loaded, replay-list ready');

// Use the by-ID flow: open the details, set release-id (if given) + replay-id, click Play.
await page.locator('summary:has-text("play by ID")').click();
if (releaseId) await page.selectOption('#any-release-pick', releaseId);
await page.fill('#any-replay-id', replayId);
console.log('clicking play for replay', replayId);
await page.click('#any-replay-btn');

// Poll #log every 2s for DESYNC WARNING. The engine main thread blocks
// during callMain — page.evaluate races vs that, so use Race + tolerate hangs.
const deadline = Date.now() + MAX_S * 1000;
let lastLogLen = 0;
let firstDesync = null;
let lastFrameSeen = 0;
const FRAME_RE = /\[f=(\d+)\]/g;
const DESYNC_RE = /\[DESYNC WARNING\] checksum ([0-9a-f]+) from demo .*?does not match our checksum ([0-9a-f]+) for frame-number (\d+)/;

const evalLog = () => Promise.race([
  page.evaluate(() => document.getElementById('log')?.textContent || ''),
  new Promise((_, rej) => setTimeout(() => rej(new Error('eval-timeout')), 4000)),
]);

while (Date.now() < deadline) {
  let log = '';
  try { log = await evalLog(); } catch { /* main thread busy */ }
  if (log && log.length > lastLogLen) {
    const fresh = log.slice(lastLogLen);
    lastLogLen = log.length;
    let m;
    const fre = new RegExp(FRAME_RE.source, 'g');
    while ((m = fre.exec(fresh)) !== null) {
      const f = +m[1];
      if (f > lastFrameSeen) lastFrameSeen = f;
    }
    const md = DESYNC_RE.exec(fresh);
    if (md) {
      firstDesync = { frame: +md[3], our: md[2], demo: md[1] };
      console.log(`[host] ✗ first DESYNC at frame ${firstDesync.frame}: our=${firstDesync.our} demo=${firstDesync.demo}`);
      break;
    }
  }
  // Detect game-over markers too
  if (/GameOver|callMain returned|callMain threw|Fatal:|engine exit/.test(log)) {
    console.log('[host] game ended');
    break;
  }
  await new Promise(r => setTimeout(r, 2000));
}

console.log('=== summary ===');
if (firstDesync) {
  console.log(`first DESYNC at f=${firstDesync.frame} (sim ${(firstDesync.frame/30).toFixed(1)}s)`);
  console.log(`  our=${firstDesync.our}  demo=${firstDesync.demo}`);
  process.exitCode = 1;
} else {
  console.log(`no divergence reached f=${lastFrameSeen} (sim ${(lastFrameSeen/30).toFixed(1)}s) within ${MAX_S}s`);
  process.exitCode = 0;
}
// Dump tail of the log for debugging.
try {
  const log = await Promise.race([
    page.evaluate(() => document.getElementById('log')?.textContent || ''),
    new Promise((_, rej) => setTimeout(() => rej(), 3000)),
  ]);
  console.log('--- tail of #log (last 60 lines) ---');
  console.log(log.split('\n').slice(-60).join('\n'));
  // Also any-replay status (for play-by-id error reporting)
  const stat = await page.evaluate(() => document.getElementById('any-replay-byid-status')?.textContent || '');
  console.log('--- any-replay-byid-status ---');
  console.log(stat);
} catch {}
await browser.close();
