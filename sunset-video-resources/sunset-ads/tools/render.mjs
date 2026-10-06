// Render an artboard to a print PNG, headless.
//   node tools/render.mjs <art.html[?query]> <out.png> <dpi> [preview-width]
// Artboards are laid out in CSS millimetres (96 CSS px per inch), so the device scale factor is dpi / 96.
// The page sets window.__ready once fonts, images and canvases are in place; the shot is clipped to .sheet.
import pw from '/Users/mengto/Downloads/Projects/Landing Pages/node_modules/playwright-core/index.js';
import { execFileSync } from 'child_process';
const { chromium } = pw;
const exe = process.env.HOME + '/Library/Caches/ms-playwright/chromium-1228/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing';
const [, , art, out, dpiArg, prevW] = process.argv;
const dpi = +dpiArg || 300, dsf = dpi / 96;
const port = process.env.PORT || '53029';
const b = await chromium.launch({ executablePath: exe, headless: true, args: ['--use-gl=angle', '--use-angle=metal', '--ignore-gpu-blocklist'] });
// first pass at scale 1 to measure the sheet, then a viewport exactly that size at the print scale
let p = await b.newPage({ viewport: { width: 800, height: 600 }, deviceScaleFactor: 1 });
const url = `http://localhost:${port}/sunset-ads/art/${art}`;
await p.goto(url + (url.includes('?') ? '&' : '?') + 'measure');
const box = await p.evaluate(() => { const r = document.querySelector('.sheet').getBoundingClientRect(); return { w: r.width, h: r.height }; });
await p.close();
p = await b.newPage({ viewport: { width: Math.ceil(box.w), height: Math.ceil(box.h) }, deviceScaleFactor: dsf });
p.on('console', m => { if (['error', 'warning'].includes(m.type())) console.log('[page]', m.text().slice(0, 300)); });
p.on('pageerror', e => console.log('[pageerror]', e.message));
await p.goto(url);
await p.waitForFunction(() => window.__ready === true, null, { timeout: 300000 });
// film output (?garment=0) keeps its alpha: no page background under the print
await p.screenshot({ path: out, clip: { x: 0, y: 0, width: box.w, height: box.h }, timeout: 300000, omitBackground: /garment=0/.test(art) });
await b.close();
const px = execFileSync('sips', ['-g', 'pixelWidth', '-g', 'pixelHeight', out]).toString().match(/\d+/g).slice(-2);
// tag the file with its print resolution so it opens at the right physical size
execFileSync('sips', ['-s', 'dpiWidth', String(dpi), '-s', 'dpiHeight', String(dpi), out], { stdio: 'ignore' });
console.log(`${out}: ${px[0]} × ${px[1]} px at ${dpi} dpi (${(box.w * 25.4 / 96).toFixed(1)} × ${(box.h * 25.4 / 96).toFixed(1)} mm with bleed)`);
if (prevW) execFileSync('sips', ['-s', 'format', 'jpeg', '-s', 'formatOptions', '88', '-Z', prevW, out, '--out', out.replace(/\.png$/, '.preview.jpg')], { stdio: 'ignore' });
