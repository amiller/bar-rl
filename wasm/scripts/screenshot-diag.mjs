// Diagnostic screenshot suite — takes multiple shots at different camera
// angles + distances so the viewer dev can spot floating/clipping/scale
// issues that aren't visible from a single angle.
//
// Usage:  node screenshot-diag.mjs [trace-name] [out-dir]
// Each shot uses window.__cam directly (set by trace3d.html for debug),
// so the camera is exactly where I expect it to be — no orbit/drag tricks.
import { chromium } from 'playwright';
import { mkdirSync } from 'fs';

const TRACE = process.argv[2] ||
  '2026-04-25_23-00-48-149_Faster Than Light 1.1_2025.06.19-wasm-2025.06.19.jsonl';
const OUT   = process.argv[3] || '/tmp/trace3d-shots-diag';
mkdirSync(OUT, { recursive: true });

const browser = await chromium.launch({ headless: true });
const ctx = await browser.newContext({ viewport: { width: 1280, height: 800 } });
const page = await ctx.newPage();
page.on('pageerror', e => console.log('[pageerror]', e.message));
page.on('console', m => { if (m.type() === 'error') console.log('[console.err]', m.text()); });

await page.goto(`http://localhost:8765/viewer/trace3d.html?trace=${encodeURIComponent(TRACE)}`,
                { waitUntil: 'networkidle' });
await page.waitForFunction(() => /[ — ]\d+ frames/.test(
  document.getElementById('status')?.textContent || ''));
await page.waitForTimeout(8000);   // let textures + GLBs settle

// Pick a busy mid-late game frame
const frameTotal = +(await page.getAttribute('#scrub', 'max'));
const targetFrame = Math.floor(frameTotal * 0.6);
await page.evaluate((f) => {
  const sc = document.getElementById('scrub');
  sc.value = String(f);
  sc.dispatchEvent(new Event('input', { bubbles: true }));
}, targetFrame);
await page.waitForTimeout(4000);

// Find a unit cluster center: poll the live scene for unit positions
const cluster = await page.evaluate(() => {
  const positions = [];
  window.__scene.traverse(o => {
    if (o.type === 'Group' && o.position.x !== 0 && o.children?.length) {
      // unit groups have at least the model + a ring as children
      positions.push([o.position.x, o.position.y, o.position.z]);
    }
  });
  if (!positions.length) return null;
  // Median position is a reasonable cluster center
  const cx = positions.map(p => p[0]).sort((a,b)=>a-b)[positions.length>>1];
  const cy = positions.map(p => p[1]).sort((a,b)=>a-b)[positions.length>>1];
  const cz = positions.map(p => p[2]).sort((a,b)=>a-b)[positions.length>>1];
  return { x: cx, y: cy, z: cz, n: positions.length };
});
console.log('cluster:', JSON.stringify(cluster));

const map = await page.evaluate(() => ({
  x: window.__ground.geometry.parameters.width,
  z: window.__ground.geometry.parameters.height,
  dispScale: window.__groundMat.displacementScale,
  dispBias:  window.__groundMat.displacementBias,
}));
console.log('map:', JSON.stringify(map));

const cx = map.x / 2, cz = map.z / 2;
const span = Math.max(map.x, map.z);

// Camera presets — fixed locations relative to map size + cluster
const shots = [
  // Pure top-down full map
  { name: '01_topdown_full',  pos: [cx, span,         cz + 1],            look: [cx, 0, cz] },
  // Top-down zoomed in on unit cluster
  { name: '02_topdown_close', pos: [cluster?.x ?? cx, 1500, (cluster?.z ?? cz) + 1], look: [cluster?.x ?? cx, 0, cluster?.z ?? cz] },
  // Standard isometric (45°)
  { name: '03_iso',           pos: [cx + span*0.4, span*0.7, cz + span*0.4], look: [cx, 0, cz] },
  // Low oblique on cluster
  { name: '04_low_oblique',   pos: [(cluster?.x ?? cx) + 800, 400, (cluster?.z ?? cz) + 1500], look: [cluster?.x ?? cx, (cluster?.y ?? 0), cluster?.z ?? cz] },
  // Profile: side-on, low — best to spot floating units against terrain horizon
  { name: '05_profile',       pos: [cx, 200, cz + span*0.8], look: [cx, 200, cz] },
  // Tight close-up on cluster — see if individual units sit on terrain
  { name: '06_tight',         pos: [(cluster?.x ?? cx) + 250, 180, (cluster?.z ?? cz) + 350], look: [cluster?.x ?? cx, (cluster?.y ?? 0), cluster?.z ?? cz] },
];

for (const s of shots) {
  await page.evaluate(({ pos, look }) => {
    window.__cam.position.set(...pos);
    window.__cam.lookAt(...look);
  }, s);
  await page.waitForTimeout(250);
  const out = `${OUT}/${s.name}.png`;
  await page.screenshot({ path: out });
  console.log(`shot: ${out}  pos=(${s.pos.map(n => n.toFixed(0)).join(',')})  look=(${s.look.map(n => n.toFixed(0)).join(',')})`);
}

await browser.close();
console.log('done');
