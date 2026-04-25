// Headless-Chrome screenshot tool for the 3D trace viewer.
// Loads viewer/trace3d.html, waits for the auto-loaded trace + GLBs to settle,
// drags the scrubber across N points, saves PNGs to /tmp/trace3d-shots/.
//
// Usage:  node screenshot-trace3d.mjs [url] [outDir] [shots]
//   url:    default http://localhost:8765/viewer/trace3d.html
//   outDir: default /tmp/trace3d-shots
//   shots:  default 4   (evenly spaced across the trace timeline)
//
// Pre: have playwright reachable. From any dir under ~/, `node` resolves it
// via ~/node_modules. If you hit MODULE_NOT_FOUND, run `cd ~ && node ...`.
import { chromium } from 'playwright';
import { mkdirSync } from 'fs';
import { join, resolve } from 'path';

const url    = process.argv[2] || 'http://localhost:8765/viewer/trace3d.html';
const outDir = resolve(process.argv[3] || '/tmp/trace3d-shots');
const shots  = +(process.argv[4] || 4);
mkdirSync(outDir, { recursive: true });

const browser = await chromium.launch({ headless: true });
const ctx  = await browser.newContext({ viewport: { width: 1280, height: 800 } });
const page = await ctx.newPage();
page.on('pageerror', e => console.log('[pageerror]', e.message));
page.on('console',   m => { if (m.type() === 'error') console.log('[console.err]', m.text()); });

console.log(`[host] goto ${url}`);
await page.goto(url, { waitUntil: 'networkidle', timeout: 60000 });

// Wait for the trace to populate (status text contains " — N frames").
await page.waitForFunction(() => {
  const s = document.getElementById('status')?.textContent || '';
  return / — \d+ frames/.test(s);
}, { timeout: 30000 });
const status0 = await page.textContent('#status');
console.log('[host] loaded:', status0);

// Read N (frames) from the scrubber max attribute.
const N = +(await page.getAttribute('#scrub', 'max'));
const targets = Array.from({length: shots}, (_, i) => Math.floor(i * N / Math.max(1, shots-1)));
console.log(`[host] taking ${shots} shots at frames`, targets);

for (let i = 0; i < targets.length; i++) {
  const f = targets[i];
  // dispatch input event after setting the value so the scrubber handler fires
  await page.evaluate((v) => {
    const sc = document.getElementById('scrub');
    sc.value = String(v);
    sc.dispatchEvent(new Event('input', { bubbles: true }));
  }, f);
  // give GLB fetches + first paint time to settle (prototypes are cached
  // after the first frame, so subsequent frames render quickly).
  await page.waitForTimeout(i === 0 ? 6000 : 1500);
  const out = join(outDir, `frame${String(i).padStart(2,'0')}_f${f}.png`);
  await page.screenshot({ path: out, fullPage: false });
  const status = await page.textContent('#frameLabel');
  console.log(`[host] ${out}  (${status})`);
}

await browser.close();
console.log('[host] done; pngs in', outDir);
