// Headless captures of the brand guide, one screen at a time, plus console errors.
//   node shot.mjs <port> <outdir> [width=1440] [height=900] [dsf=1] [selectors,comma,separated]
import pw from '/Users/mengto/Downloads/Projects/Landing Pages/node_modules/playwright-core/index.js';
import fs from 'fs';
const { chromium } = pw;
const [port, out, W = '1440', H = '900', dsf = '1', only = ''] = process.argv.slice(2);
fs.mkdirSync(out, { recursive: true });
const browser = await chromium.launch({ headless: true, executablePath: '/Users/mengto/Library/Caches/ms-playwright/chromium-1228/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing', args: ['--use-gl=angle', '--use-angle=metal', '--ignore-gpu-blocklist'] });
const page = await browser.newPage({ viewport: { width: +W, height: +H }, deviceScaleFactor: +dsf });
const errors = [];
page.on('console', m => { if (m.type() === 'error' || m.type() === 'warning') errors.push(m.type() + ': ' + m.text()); });
page.on('pageerror', e => errors.push('PAGEERROR: ' + e.message));
page.on('requestfailed', r => errors.push('REQFAIL: ' + r.url() + ' ' + r.failure()?.errorText));
page.on('response', r => { if (r.status() >= 400) errors.push('HTTP ' + r.status() + ' ' + r.url()); });
await page.goto(`http://localhost:${port}/sunset-brand.html?v=` + Date.now(), { waitUntil: 'load' });
await page.evaluate(() => { document.documentElement.style.scrollBehavior = 'auto'; return document.fonts.ready; });
await page.waitForTimeout(2200);
if (only) {
  for (const sel of only.split(',')) {
    const y = await page.evaluate(s => { const e = document.querySelector(s); if (!e) return null; const r = e.getBoundingClientRect(); return r.top + scrollY; }, sel);
    if (y == null) { console.log('missing', sel); continue; }
    await page.evaluate(v => scrollTo(0, v), Math.max(0, y - 90)); await page.waitForTimeout(2600);
    const name = sel.replace(/[^a-z0-9]+/gi, '_').replace(/^_|_$/g, '');
    await page.screenshot({ path: `${out}/${name}.png` }); console.log('shot', name);
  }
} else {
  const total = await page.evaluate(() => document.documentElement.scrollHeight);
  let i = 0;
  for (let y = 0; y < total; y += +H) {
    await page.evaluate(v => scrollTo(0, v), y); await page.waitForTimeout(1300);
    await page.screenshot({ path: `${out}/s${String(i++).padStart(2, '0')}.png` });
  }
  console.log('screens', i, 'height', total);
}
console.log('errors', JSON.stringify(errors, null, 1));
await browser.close();
