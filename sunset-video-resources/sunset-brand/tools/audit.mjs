// Audit the brand guide at 390 / 768 / 1024 / 1440: console errors, failed requests, horizontal
// overflow (and which elements cause it), and any rendered text under 11px.
//   node audit.mjs <port> [outdir]
import pw from '/Users/mengto/Downloads/Projects/Landing Pages/node_modules/playwright-core/index.js';
import fs from 'fs';
const { chromium } = pw;
const [port, out = ''] = process.argv.slice(2);
if (out) fs.mkdirSync(out, { recursive: true });
const browser = await chromium.launch({ headless: true, executablePath: '/Users/mengto/Library/Caches/ms-playwright/chromium-1228/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing', args: ['--use-gl=angle', '--use-angle=metal', '--ignore-gpu-blocklist'] });
let fail = 0;
for (const [w, h] of [[390, 844], [768, 1024], [1024, 768], [1440, 900]]) {
  const mobile = w < 800;
  const page = await browser.newPage({ viewport: { width: w, height: h }, deviceScaleFactor: 1, isMobile: mobile, hasTouch: mobile });
  const errors = [];
  page.on('console', m => { if (m.type() === 'error' || m.type() === 'warning') errors.push(m.type() + ': ' + m.text()); });
  page.on('pageerror', e => errors.push('PAGEERROR: ' + e.message));
  page.on('response', r => { if (r.status() >= 400) errors.push('HTTP ' + r.status() + ' ' + r.url()); });
  await page.goto(`http://localhost:${port}/sunset-brand.html?v=` + Date.now(), { waitUntil: 'load' });
  await page.evaluate(() => { document.documentElement.style.scrollBehavior = 'auto'; return document.fonts.ready; });
  // walk the page so lazy images load and every reveal fires
  const H = await page.evaluate(() => document.documentElement.scrollHeight);
  for (let y = 0; y < H; y += h * .8) { await page.evaluate(v => scrollTo(0, v), y); await page.waitForTimeout(60); }
  await page.waitForTimeout(1500);
  const r = await page.evaluate(() => {
    const W = document.documentElement.clientWidth;
    const over = document.documentElement.scrollWidth - W;
    const wide = [];
    for (const e of document.querySelectorAll('body *')) {
      const b = e.getBoundingClientRect();
      if (!b.width) continue;
      if (b.right > W + 1 || b.left < -1) {
        // ignore things clipped by an overflow:hidden/clip ancestor
        let p = e.parentElement, clipped = false;
        while (p && p !== document.body) { const cs = getComputedStyle(p); if (/(hidden|clip)/.test(cs.overflowX)) { const pb = p.getBoundingClientRect(); if (pb.right <= W + 1 && pb.left >= -1) { clipped = true; break; } } p = p.parentElement; }
        if (!clipped && getComputedStyle(e).position !== 'fixed') wide.push((e.id ? '#' + e.id : e.tagName.toLowerCase() + '.' + [...e.classList].join('.')) + ` [${Math.round(b.left)}..${Math.round(b.right)}]`);
      }
    }
    const small = [];
    for (const e of document.querySelectorAll('body *')) {
      const own = [...e.childNodes].some(n => n.nodeType === 3 && n.data.trim());
      if (!own) continue;
      const cs = getComputedStyle(e);
      if (cs.display === 'none' || cs.visibility === 'hidden') continue;
      const b = e.getBoundingClientRect(); if (!b.width || !b.height) continue;
      let fs = parseFloat(cs.fontSize);
      // text inside an SVG: scale by the SVG's rendered size against its viewBox
      const svg = e.closest('svg');
      if (svg && svg.viewBox && svg.viewBox.baseVal && svg.viewBox.baseVal.width) fs *= svg.getBoundingClientRect().width / svg.viewBox.baseVal.width;
      if (fs < 10.95) small.push(`${e.tagName.toLowerCase()}.${[...e.classList].join('.')} ${fs.toFixed(2)}px "${e.textContent.trim().slice(0, 30)}"`);
    }
    return { W, over, wide: [...new Set(wide)].slice(0, 25), small: [...new Set(small)].slice(0, 40), height: document.documentElement.scrollHeight };
  });
  const bad = r.over > 0 || r.small.length || errors.length;
  if (bad) fail++;
  console.log(`\n== ${w}x${h}  width ${r.W}  scroll overflow ${r.over}px  height ${r.height}`);
  if (r.over > 0 || r.wide.length) console.log('  wide:', r.wide.join('\n        '));
  if (r.small.length) console.log('  small text:', r.small.join('\n        '));
  if (errors.length) console.log('  errors:', errors.join('\n        '));
  if (out) { await page.evaluate(() => scrollTo(0, 0)); await page.waitForTimeout(600); await page.screenshot({ path: `${out}/audit-${w}.png` }); }
  await page.close();
}
console.log(fail ? `\n${fail} viewport(s) with issues` : '\nall clear');
await browser.close();
