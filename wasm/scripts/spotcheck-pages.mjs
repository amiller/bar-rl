#!/usr/bin/env node
// Headless spot-check of the deployed Pages site.
// Verifies: index loads, /releases/index.json reports its bundle, the live API's
// latest replay gameVersion matches a loaded release-bundle, the worker proxy
// answers /sdfz/<filename> for that replay (HEAD, no body fetch).
//
// Usage:  node spotcheck-pages.mjs [pages-base-url]
// Default: https://bar-replay-demo.pages.dev
import { chromium } from 'playwright';

const BASE = process.argv[2] || 'https://bar-replay-demo.pages.dev';
const API  = 'https://api.bar-rts.com';
const PROXY = 'https://bar-replay-proxy.socrates1024.workers.dev';

const ok = (s) => console.log(`✓ ${s}`);
const bad = (s) => { console.log(`✗ ${s}`); process.exitCode = 1; };

async function fetchJSON(url) {
  const r = await fetch(url, { cache: 'no-cache' });
  if (!r.ok) throw new Error(`HTTP ${r.status} on ${url}`);
  return r.json();
}

// 1) /releases/index.json present, has at least one bundle.
let releases;
try {
  releases = (await fetchJSON(`${BASE}/releases/index.json`)).releases || [];
  if (!releases.length) bad('releases/index.json has no bundles');
  else ok(`Pages bundles: ${releases.map(r => r.gameVersion).join(', ')}`);
} catch (e) { bad(`fetch releases/index.json: ${e.message}`); releases = []; }

// 2) Latest replay's gameVersion vs loaded bundles.
let liveDetail;
try {
  const list = (await fetchJSON(`${API}/replays?limit=1`)).data || [];
  if (!list[0]) throw new Error('API returned 0 replays');
  liveDetail = await fetchJSON(`${API}/replays/${encodeURIComponent(list[0].id)}`);
  ok(`live latest: ${liveDetail.gameVersion} on ${liveDetail.Map?.scriptName}`);
} catch (e) { bad(`fetch live replay: ${e.message}`); }

const known = new Set(releases.map(r => r.gameVersion));
if (liveDetail) {
  if (known.has(liveDetail.gameVersion)) ok('live replay matches a loaded bundle');
  else bad(`live replay gameVersion (${liveDetail.gameVersion}) not in loaded bundles — recent replays will fail to play`);
}

// 3) Worker proxy reachable for that replay's .sdfz (HEAD).
if (liveDetail?.fileName) {
  try {
    const r = await fetch(`${PROXY}/sdfz/${encodeURIComponent(liveDetail.fileName)}`, { method: 'HEAD' });
    if (r.ok) ok(`worker proxy /sdfz/${liveDetail.fileName.slice(0,40)}… HTTP ${r.status}`);
    else bad(`worker proxy returned ${r.status} for ${liveDetail.fileName}`);
  } catch (e) { bad(`worker proxy: ${e.message}`); }
}

// 4) Pages /viewer/engine.html boots (no JS errors during initial load).
const browser = await chromium.launch({ headless: true });
const ctx = await browser.newContext();
const page = await ctx.newPage();
const errors = [];
page.on('pageerror', e => errors.push(e.message));
page.on('console', m => { if (m.type() === 'error') errors.push(m.text()); });
try {
  await page.goto(`${BASE}/viewer/engine.html`, { waitUntil: 'domcontentloaded', timeout: 30000 });
  await page.waitForSelector('#sample-pick option', { state: 'attached', timeout: 15000 });
  // The patched engine.html status line says "N recent · M playable · ..."
  // once it has probed bar-rts.com. The fetch+detail loop takes ~3-30s so
  // wait for the full distribution to appear, not just the initial state.
  await page.waitForFunction(() => / playable /.test(document.getElementById('any-replay-status')?.textContent || ''),
                             { timeout: 60000 });
  const live = await page.evaluate(() => document.getElementById('any-replay-status')?.textContent || '');
  ok(`engine.html loaded · "${live}"`);
} catch (e) {
  bad(`engine.html: ${e.message}`);
} finally {
  if (errors.length) console.log('  page errors:'); for (const e of errors) console.log('   ', e);
  await browser.close();
}
