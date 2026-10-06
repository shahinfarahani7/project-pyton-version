// Headless captures of the Sunseto site (sunset.html, read only) for the brand guide.
//   node capture-site.mjs <port> <outdir> [ref|tiles]
// ref:   1x section views at 1440x900 for reference
// tiles: 2x close-ups of each 3D tile and of the components the guide ports
import pw from '/Users/mengto/Downloads/Projects/Landing Pages/node_modules/playwright-core/index.js';
import fs from 'fs';
const { chromium } = pw;
const [port, out, mode = 'ref'] = process.argv.slice(2);
fs.mkdirSync(out, { recursive: true });
const browser = await chromium.launch({ headless: true, executablePath: '/Users/mengto/Library/Caches/ms-playwright/chromium-1228/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing', args: ['--use-gl=angle', '--use-angle=metal', '--ignore-gpu-blocklist'] });
const errors = [];
async function open(w, h, dsf) {
  const page = await browser.newPage({ viewport: { width: w, height: h }, deviceScaleFactor: dsf });
  page.on('pageerror', e => errors.push('PAGEERROR: ' + e.message));
  await page.goto(`http://localhost:${port}/sunset.html?v=` + Date.now(), { waitUntil: 'load' });
  await page.waitForFunction(() => window.__dl && window.__dl.ready, null, { timeout: 180000 });
  await page.evaluate(() => { window.__lockQ = true; });
  await page.waitForTimeout(3500);
  page._y = 0;
  return page;
}
async function go(page, y, wait = 1400) {
  const step = y > page._y ? 420 : -420;
  for (let yy = page._y; step > 0 ? yy < y : yy > y; yy += step) { await page.evaluate(v => scrollTo(0, v), yy); await page.waitForTimeout(35); }
  await page.evaluate(v => scrollTo(0, v), y); page._y = y;
  await page.waitForTimeout(wait);
}
const top = (page, sel) => page.evaluate(s => { const e = document.querySelector(s); if (!e) return null; const b = e.getBoundingClientRect(); return { y: b.top + scrollY, h: b.height, x: b.left, w: b.width }; }, sel);
async function closeup(page, sel, name, pad = 0) {
  const r = await top(page, sel); if (!r) { console.log('missing', sel); return; }
  const H = page.viewportSize().height;
  await go(page, Math.max(0, r.y + r.h / 2 - H / 2), 2400);
  const b = await page.evaluate(s => { const e = document.querySelector(s).getBoundingClientRect(); return { x: e.left, y: e.top, width: e.width, height: e.height }; }, sel);
  await page.screenshot({ path: `${out}/${name}.png`, clip: { x: Math.max(0, b.x - pad), y: Math.max(0, b.y - pad), width: b.width + pad * 2, height: b.height + pad * 2 } });
  console.log('shot', name);
}
if (mode === 'ref') {
  const p = await open(1440, 900, 1);
  await p.screenshot({ path: `${out}/r00-hero.png` });
  for (const [name, sel, off] of [['r01-usp', '#usp', 60], ['r02-usp2', '.usp-row[data-i="1"]', -130], ['r03-hiw', '#hiw', 200], ['r04-step1', '.hiw-item[data-i="0"]', 60], ['r05-step1b', '#s1Cell', -130],
    ['r06-step2', '.hiw-item[data-i="1"]', 900], ['r07-step3', '.hiw-item[data-i="2"]', 60], ['r08-step3b', '.hiw-item[data-i="2"] .hg-chart', -130], ['r09-why', '#why', 0], ['r10-network', '#network', 500],
    ['r11-letters', '#letters', 60], ['r12-letters2', '#letters', 700], ['r13-cta', '#cta', 0], ['r14-pricing', '#pricing', 100], ['r15-footer', '#footer', 0]]) {
    const r = await top(p, sel); if (!r) continue;
    await go(p, Math.max(0, r.y + off), 1700); await p.screenshot({ path: `${out}/${name}.png` }); console.log('shot', name);
  }
} else {
  const p = await open(1440, 900, 2);
  await p.screenshot({ path: `${out}/tile-hero.png` });
  // the tiles alone: no falling petals over them, no nav across them
  await p.evaluate(() => { const pl = document.getElementById('petalLayer'); if (pl) pl.style.display = 'none'; document.getElementById('header').style.visibility = 'hidden'; });
  for (const [sel, name, pad] of [['[data-view="modern"]', 'tile-house', 0], ['[data-view="battery"]', 'tile-battery', 0], ['[data-view="hand"]', 'tile-hand', 0],
    ['[data-view="s1Solar"]', 'tile-machiya', 0], ['[data-view="s1Device"]', 'tile-cedar-yard', 0], ['[data-view="s3Dusk"]', 'tile-dusk', 0], ['[data-view="s3Storm"]', 'tile-storm', 0],
    ['.net-slot', 'tile-network', 0], ['#phoneSlot', 'tile-phone', 40], ['.hiw-item[data-i="1"] .hiw-card', 'tile-step2', 0],
    ['.get-started', 'ref-button', 14], ['#chart', 'ref-chart', 30], ['#letters .lt-row>li:nth-child(1) .hagaki', 'ref-hagaki', 28], ['.pr-card', 'ref-pricing', 0]]) {
    await closeup(p, sel, name, pad);
  }
}
console.log('errors', JSON.stringify(errors));
await browser.close();
