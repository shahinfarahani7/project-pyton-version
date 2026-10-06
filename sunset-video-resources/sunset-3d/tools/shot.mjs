#!/usr/bin/env node
/* Headless capture for Sunset scenes (GPU on, headless:true — never opens a visible window).
   node tools/shot.mjs --url "http://localhost:PORT/sunset-3d/lab.html?scene=hero" --out /abs/out.png
     [--w 1440] [--h 900] [--dpr 2] [--wait 1200] [--freeze 4.2] [--jump "#savings"] [--off 0]
     [--clip x,y,w,h] [--eval "js expr run before capture"] [--seq "0,.33,.66,1" --pin "#how"]
   --seq with --pin captures a pinned section at several progress values (out gets -p<value> suffixes).
   Prints console errors and the page's __sun.status(). */
import { chromium } from 'playwright-core';
import fs from 'node:fs'; import path from 'node:path'; import os from 'node:os';

const A = Object.fromEntries(process.argv.slice(2).reduce((acc, v, i, a) => (v.startsWith('--') ? acc.push([v.slice(2), a[i + 1]?.startsWith('--') || a[i + 1] === undefined ? '1' : a[i + 1]]) : 0, acc), []));
const cache = path.join(os.homedir(), 'Library/Caches/ms-playwright');
const exe = fs.readdirSync(cache).filter(d => /^chromium-\d+$/.test(d)).sort((a, b) => +b.split('-')[1] - +a.split('-')[1])
  .map(d => path.join(cache, d, 'chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing')).find(p => fs.existsSync(p));
const W = +(A.w || 1440), H = +(A.h || 900), DPR = +(A.dpr || 2);
const browser = await chromium.launch({ executablePath: exe, headless: true, args: ['--use-angle=metal', '--enable-gpu', '--ignore-gpu-blocklist', '--enable-unsafe-swiftshader=false'] });
const page = await browser.newPage({ viewport: { width: W, height: H }, deviceScaleFactor: DPR });
const errors = [];
page.on('console', m => { if (m.type() === 'error' || m.type() === 'warning') errors.push(`[${m.type()}] ${m.text()}`); });
page.on('pageerror', e => errors.push(`[pageerror] ${e.message}`));
let url = A.url; if (!/[?&]dpr=/.test(url)) url += (url.includes('?') ? '&' : '?') + `dpr=${DPR}`;
if (A.freeze && !/[?&]freeze=/.test(url)) url += `&freeze=${A.freeze}`;
await page.goto(url, { waitUntil: 'load', timeout: 120000 });
await page.waitForFunction(() => window.__sun && window.__sun.ready(), null, { timeout: 180000 }).catch(() => errors.push('[harness] timed out waiting for __sun.ready()'));
await page.evaluate(() => document.fonts.ready);
// captures show the settled page: finish every scroll-reveal instantly
await page.addStyleTag({ content: '.rv{transition:none!important;opacity:1!important;transform:none!important}' });
const settle = async () => { await page.waitForTimeout(+(A.wait || 1200)); await page.evaluate(() => { __sun.render(); __sun.render(); }); };
const outs = [];
const snap = async (out) => {
  const opts = { path: out };
  if (A.clip) { const [x, y, w, h] = A.clip.split(',').map(Number); opts.clip = { x, y, width: w, height: h }; }
  await page.screenshot(opts); outs.push(out);
};
if (A.eval) await page.evaluate(A.eval);
if (A.seq && A.pin) {
  for (const p of A.seq.split(',').map(Number)) {
    await page.evaluate(([sel, p]) => { const el = document.querySelector(sel); const top = el.getBoundingClientRect().top + scrollY; const y = top + p * (el.offsetHeight - innerHeight); __sun.lenis ? __sun.lenis.scrollTo(y, { immediate: true }) : scrollTo(0, y); }, [A.pin, p]);
    await settle();
    await snap(A.out.replace(/\.png$/, `-p${p}.png`));
  }
} else {
  if (A.jump) await page.evaluate(([s, o]) => __sun.jump(s, o), [A.jump, +(A.off || 0)]);
  await settle();
  await snap(A.out);
}
const status = await page.evaluate(() => ({ status: __sun.status(), fps: __sun.fps().toFixed(1), dpr: __sun.VP.dpr })).catch(() => ({}));
console.log(JSON.stringify({ outs, ...status, errors: errors.slice(0, 20) }, null, 1));
await browser.close();
