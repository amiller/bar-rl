// Diagnostic screenshot suite — takes shots from many camera angles + a
// few unit close-ups, then writes an index.html so the developer can
// click through the gallery.
//
// Usage: node screenshot-diag.mjs [trace-name]
// Output: wasm/diag-shots/  (served by serve.py, so visit
//   http://localhost:8765/diag-shots/ to view the gallery)
import { chromium } from 'playwright';
import { mkdirSync, writeFileSync } from 'fs';
import { join, resolve, dirname } from 'path';
import { fileURLToPath } from 'url';

const TRACE = process.argv[2] ||
  '2026-04-25_23-00-48-149_Faster Than Light 1.1_2025.06.19-wasm-2025.06.19.jsonl';
// Output dir: wasm/diag-shots/ — passed in via env or hard-coded path so
// it works regardless of where the script is invoked from.
const OUT = process.env.DIAG_OUT_DIR ||
            '/home/amiller/projects/bar/wasm/diag-shots';
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
await page.waitForTimeout(8000);

// Pick a busy mid-late game frame
const frameTotal = +(await page.getAttribute('#scrub', 'max'));
const targetFrame = Math.floor(frameTotal * 0.6);
await page.evaluate((f) => {
  const sc = document.getElementById('scrub');
  sc.value = String(f);
  sc.dispatchEvent(new Event('input', { bubbles: true }));
}, targetFrame);
await page.waitForTimeout(4000);

// Grab map dimensions and a unit cluster
const map = await page.evaluate(() => ({
  x: window.__ground.geometry.parameters.width,
  z: window.__ground.geometry.parameters.height,
}));
const units = await page.evaluate(() => {
  const u = [];
  window.__scene.traverse(o => {
    if (o.type === 'Group' && o.position.x !== 0 && o.children?.length >= 2) {
      u.push({ x: o.position.x, y: o.position.y, z: o.position.z });
    }
  });
  return u;
});
console.log(`map=${map.x}×${map.z}, units=${units.length}, frame=${targetFrame}/${frameTotal}`);

// Cluster center = median position
function median(arr) { const s = [...arr].sort((a,b)=>a-b); return s[s.length>>1]; }
const cluster = units.length
  ? { x: median(units.map(u=>u.x)), y: median(units.map(u=>u.y)), z: median(units.map(u=>u.z)) }
  : { x: map.x/2, y: 0, z: map.z/2 };

const cx = map.x/2, cz = map.z/2, span = Math.max(map.x, map.z);
const shots = [
  { name: 'top_full',     caption: 'Top-down, full map',
    pos: [cx, span, cz + 1], look: [cx, 0, cz] },
  { name: 'top_close',    caption: 'Top-down, zoomed on unit cluster',
    pos: [cluster.x, 1500, cluster.z + 1], look: [cluster.x, 0, cluster.z] },
  { name: 'iso_45',       caption: 'Isometric (~45°), full map',
    pos: [cx + span*0.4, span*0.7, cz + span*0.4], look: [cx, 0, cz] },
  { name: 'iso_60_close', caption: '60° from above, on cluster',
    pos: [cluster.x + 600, 1000, cluster.z + 1000], look: [cluster.x, cluster.y, cluster.z] },
  { name: 'low_oblique',  caption: 'Low oblique, on cluster',
    pos: [cluster.x + 500, 350, cluster.z + 1200], look: [cluster.x, cluster.y, cluster.z] },
  { name: 'profile',      caption: 'Profile (low side-on), to spot floating',
    pos: [cx, 200, cz + span*0.8], look: [cx, 200, cz] },
  { name: 'profile_close',caption: 'Profile, zoomed near cluster',
    pos: [cluster.x - 800, cluster.y + 50, cluster.z + 200], look: [cluster.x, cluster.y, cluster.z] },
];

// Per-unit close-ups for the first N units (where they're varied enough)
const sample = units.slice(0, Math.min(4, units.length));
for (let i = 0; i < sample.length; i++) {
  shots.push({
    name: `unit_${i}`,
    caption: `Close-up unit ${i} at (${sample[i].x.toFixed(0)}, ${sample[i].z.toFixed(0)})`,
    pos: [sample[i].x + 80, sample[i].y + 60, sample[i].z + 200],
    look: [sample[i].x, sample[i].y + 10, sample[i].z],
  });
}

const taken = [];
for (const s of shots) {
  await page.evaluate(({ pos, look }) => {
    window.__cam.position.set(...pos);
    window.__cam.lookAt(...look);
  }, s);
  await page.waitForTimeout(250);
  const file = `${s.name}.png`;
  await page.screenshot({ path: join(OUT, file) });
  taken.push({ ...s, file });
  console.log(`shot: ${file}  ${s.caption}`);
}
await browser.close();

// --- Build index.html ---
const html = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>BAR viewer diagnostics — ${new Date().toLocaleString()}</title>
<style>
  body { background:#111; color:#ddd; font:14px/1.5 ui-monospace, Menlo, monospace;
         margin:20px; }
  h1 { font-size:16px; margin:0 0 4px; }
  .meta { color:#889; font-size:12px; margin-bottom:18px; }
  .grid { display:grid; grid-template-columns:repeat(auto-fill, minmax(380px, 1fr));
          gap:18px; }
  .card { background:#181818; border:1px solid #333; border-radius:6px; overflow:hidden;
          cursor:pointer; }
  .card img { width:100%; display:block; }
  .card .cap { padding:8px 12px; color:#bbb; font-size:12px; border-top:1px solid #2a2a2a;
               background:#1c1c1c; }
  .card .cap .name { color:#88c0ff; }
  .card:hover { border-color:#4a90ff; }
  /* simple lightbox */
  #box { position:fixed; inset:0; background:rgba(0,0,0,.9); display:none;
         align-items:center; justify-content:center; z-index:99; cursor:zoom-out; }
  #box img { max-width:96vw; max-height:96vh; }
  #box.on { display:flex; }
</style>
</head>
<body>
<h1>BAR 3D viewer — diagnostic gallery</h1>
<div class="meta">
  trace: ${TRACE}<br>
  frame: ${targetFrame} / ${frameTotal} (${(targetFrame/frameTotal*100).toFixed(0)}%)
  &middot; map: ${map.x}×${map.z} &middot; units in scene: ${units.length}
  &middot; cluster center: (${cluster.x.toFixed(0)}, ${cluster.z.toFixed(0)})
  &middot; generated ${new Date().toISOString()}
</div>
<div class="grid">
${taken.map(s => `  <div class="card" data-img="${s.file}">
    <img src="${s.file}" loading="lazy">
    <div class="cap"><span class="name">${s.name}</span> &mdash; ${s.caption}<br>
      pos=(${s.pos.map(n => Math.round(n)).join(', ')}) look=(${s.look.map(n => Math.round(n)).join(', ')})
    </div>
  </div>`).join('\n')}
</div>
<div id="box"><img></div>
<script>
const box = document.getElementById('box'), boxImg = box.querySelector('img');
document.querySelectorAll('.card').forEach(c => c.addEventListener('click', () => {
  boxImg.src = c.dataset.img; box.classList.add('on');
}));
box.addEventListener('click', () => box.classList.remove('on'));
</script>
</body></html>`;
writeFileSync(join(OUT, 'index.html'), html);
console.log(`gallery: http://localhost:8765/diag-shots/`);
