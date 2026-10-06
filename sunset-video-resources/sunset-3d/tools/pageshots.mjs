#!/usr/bin/env node
/* Capture every section of index.html in one headless session.
   node tools/pageshots.mjs --out <dir> [--w 1440 --h 900 --dpr 2] [--port 64665] [--freeze 3] [--only hero,chart]
   Writes <dir>/<nn>-<name>.png and prints console errors + scene status. */
import { chromium } from 'playwright-core';
import fs from 'node:fs'; import path from 'node:path'; import os from 'node:os';

const A = Object.fromEntries(process.argv.slice(2).reduce((acc, v, i, a) => (v.startsWith('--') ? acc.push([v.slice(2), a[i + 1]?.startsWith('--') || a[i + 1] === undefined ? '1' : a[i + 1]]) : 0, acc), []));
const cache = path.join(os.homedir(), 'Library/Caches/ms-playwright');
const exe = fs.readdirSync(cache).filter(d => /^chromium-\d+$/.test(d)).sort((a, b) => +b.split('-')[1] - +a.split('-')[1])
  .map(d => path.join(cache, d, 'chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing')).find(p => fs.existsSync(p));
const W = +(A.w || 1440), H = +(A.h || 900), DPR = +(A.dpr || 2), out = A.out; fs.mkdirSync(out, { recursive: true });
const browser = await chromium.launch({ executablePath: exe, headless: true, args: ['--use-angle=metal', '--enable-gpu', '--ignore-gpu-blocklist'] });
const page = await browser.newPage({ viewport: { width: W, height: H }, deviceScaleFactor: DPR });
const errors = [];
page.on('console', m => { if (m.type() === 'error' || m.type() === 'warning') errors.push(`[${m.type()}] ${m.text()}`); });
page.on('pageerror', e => errors.push(`[pageerror] ${e.message}`));
const PORT = A.port || fs.readFileSync(new URL('./PORT', import.meta.url), 'utf8').trim();
let url = `http://localhost:${PORT}/sunset-3d/index.html?dpr=${DPR}&freeze=${A.freeze || 3}`;
if (A.only) url += `&only=${A.only}`;
if (A.q) url += `&${A.q}`;
await page.goto(url, { waitUntil: 'load', timeout: 120000 });
await page.waitForFunction(() => window.__sun && window.__sun.ready(), null, { timeout: 240000 }).catch(() => errors.push('[harness] timed out waiting for ready'));
await page.evaluate(() => document.fonts.ready);
// captures show the settled page: finish every scroll-reveal instantly
await page.addStyleTag({ content: '.rv{transition:none!important;opacity:1!important;transform:none!important}' });
const shots = [
  ['hero', '#hero', 0], ['savings', '#savings', 60], ['how-a', '#how', .08], ['how-b', '#how', .5], ['how-c', '#how', .92],
  ['hardware', '#hardware', 80], ['plans', '#plans', 0], ['coverage', '#coverage', 40], ['coverage-map', '#coverage', 520],
  ['voices', '#voices', 60], ['faq', '#faq', 0], ['start', '#start', -40], ['footer', 'footer', 9e6],
];
let n = 0;
for (const [name, sel, off] of shots) {
  await page.evaluate(([sel, off]) => {
    const el = document.querySelector(sel); const top = el.getBoundingClientRect().top + scrollY;
    let y = off > 0 && off < 1 ? top + off * (el.offsetHeight - innerHeight) : off === 9e6 ? document.documentElement.scrollHeight - innerHeight : top + off;
    __sun.lenis ? __sun.lenis.scrollTo(y, { immediate: true, force: true }) : scrollTo(0, y);
  }, [sel, off]);
  await page.waitForTimeout(+(A.wait || 900));
  await page.evaluate(() => { __sun.render(); __sun.render(); });
  const f = path.join(out, `${String(++n).padStart(2, '0')}-${name}.png`);
  await page.screenshot({ path: f });
}
const status = await page.evaluate(() => ({ status: __sun.status(), fps: __sun.fps().toFixed(1) }));
console.log(JSON.stringify({ out, ...status, errors: [...new Set(errors)].slice(0, 25) }, null, 1));
await browser.close();
