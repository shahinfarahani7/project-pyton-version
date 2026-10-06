/* Sunset — boot, page ground, scene registry, render loop, DOM behaviour. */
import { THREE, VP, PTR, STATE, REDUCED, renderer, readViewport, loadEnv, studioEnv, costs, clamp, damp, yieldTask } from './core.js';
import { Post } from './post.js';
import { Petals, NearPetals } from './petals.js';
import Lenis from 'lenis';

const $ = (s, r = document) => r.querySelector(s), $$ = (s, r = document) => [...r.querySelectorAll(s)];
const Q = new URLSearchParams(location.search);

/* ------------------------------------------------------------------ icons (Iconify Solar Duotone, fetched once) */
fetch('assets/icons.json').then(r => r.json()).then(ic => { for (const el of $$('[data-i]')) if (ic[el.dataset.i]) el.innerHTML = ic[el.dataset.i]; });

/* ------------------------------------------------------------------ smooth scroll */
const lenis = REDUCED || Q.has('nolenis') ? null : new Lenis({ autoRaf: false, lerp: .1, wheelMultiplier: .9 });
for (const a of $$('a[href^="#"]')) a.addEventListener('click', e => { const t = $(a.getAttribute('href')); if (!t) return; e.preventDefault(); lenis ? lenis.scrollTo(t, { offset: 0, duration: 1.4 }) : t.scrollIntoView({ behavior: 'smooth' }); });

/* ------------------------------------------------------------------ page ground: section colours, dusk blends, paper grain */
const sections = $$('[data-bg]');
const MAXS = 16;
const ground = (() => {
  const u = { uHole: { value: Array.from({ length: 8 }, () => new THREE.Vector4()) }, uHoleN: { value: 0 }, uLineX: { value: new Float32Array(5) }, uLineN: { value: 0 }, uLines: { value: new Float32Array(MAXS) }, uTop: { value: new Float32Array(MAXS) }, uBlend: { value: new Float32Array(MAXS) }, uCol: { value: Array.from({ length: MAXS }, () => new THREE.Vector3()) }, uN: { value: 0 }, uRes: { value: new THREE.Vector2() }, uDpr: { value: 1 }, uScroll: { value: 0 } };
  const m = new THREE.ShaderMaterial({
    uniforms: u, depthTest: false, depthWrite: false,
    vertexShader: `void main(){ gl_Position = vec4(position.xy, 0., 1.); }`,
    fragmentShader: /* glsl */`
      uniform float uLineX[5]; uniform int uLineN; uniform float uLines[${MAXS}]; uniform vec4 uHole[8]; uniform int uHoleN;
      uniform float uTop[${MAXS}]; uniform float uBlend[${MAXS}]; uniform vec3 uCol[${MAXS}]; uniform int uN; uniform vec2 uRes; uniform float uDpr, uScroll;
      float h12(vec2 p){ vec3 p3 = fract(vec3(p.xyx) * .1031); p3 += dot(p3, p3.yzx + 33.33); return fract((p3.x + p3.y) * p3.z); }
      float vn(vec2 p){ vec2 i = floor(p), f = fract(p); f = f * f * (3. - 2. * f); return mix(mix(h12(i), h12(i + vec2(1,0)), f.x), mix(h12(i + vec2(0,1)), h12(i + vec2(1,1)), f.x), f.y); }
      void main(){
        float y = (uRes.y - gl_FragCoord.y) / uDpr;           // css px from the viewport top
        vec3 c = uCol[0]; float lines = uLines[0];
        for (int i = 1; i < ${MAXS}; i++) {
          if (i >= uN) break;
          if (y >= uTop[i]) lines = uLines[i];
          float b = uBlend[i];
          float t = b < 1. ? step(uTop[i], y) : smoothstep(uTop[i] - b * .3, uTop[i] + b * .7, y);
          c = mix(c, uCol[i], t);
        }
        vec2 pp = vec2(gl_FragCoord.x, gl_FragCoord.y - uScroll * uDpr) / uDpr;   // grain lives on the page, not the screen
        float fib = vn(pp * vec2(.09, .9)) * .6 + vn(pp * vec2(.5, .05)) * .4;       // faint washi fibres
        float g = h12(floor(pp * 1.)) - .5;
        float lum = dot(c, vec3(.3, .59, .11));
        c += (g * .018 + (fib - .5) * .016) * mix(.6, 1., lum);
        // the page grid (the solar array's cell lines), drawn under every scene so 3-D covers it
        float fx = gl_FragCoord.x / uDpr;
        for (int k = 0; k < 8; k++) { if (k >= uHoleN) break; vec4 h = uHole[k]; if (fx > h.x && fx < h.z && y > h.y && y < h.w) lines = 0.; }   // not through scene hosts
        if (lines > 0.) {
          float m = 0.;
          for (int k = 0; k < 5; k++) { if (k >= uLineN) break; m = max(m, 1. - clamp(abs(fx - uLineX[k]) * uDpr - .5, 0., 1.)); }
          c = mix(c, lum < .35 ? vec3(.984, .961, .918) : vec3(.118, .098, .086), m * lines);
        }
        gl_FragColor = vec4(c, 1.);
      }`,
  });
  const g = new THREE.BufferGeometry(); g.setAttribute('position', new THREE.Float32BufferAttribute([-1, -1, 0, 3, -1, 0, -1, 3, 0], 3));
  const mesh = new THREE.Mesh(g, m); mesh.frustumCulled = false;
  const sc = new THREE.Scene(); sc.add(mesh); const cam = new THREE.OrthographicCamera(-1, 1, 1, -1, 0, 1);
  // ground colours are written raw (no colour-space conversion), so the canvas shows exactly the CSS hex
  const cols = sections.map(s => { const c = new THREE.Color(); c.setStyle(s.dataset.bg, THREE.LinearSRGBColorSpace); return c; });
  // sections whose column lines are drawn here (the hero keeps DOM lines over its scene; full-bleed 3-D sections have none)
  const lineA = sections.map(s => s.querySelector(':scope > .grid-lines') && !['hero', 'how', 'start', 'coverage'].includes(s.id) ? .07 : 0);
  let lineMeasured = false;
  const lineHosts = [...document.querySelectorAll('[data-scene]')].filter(h => { const s = h.closest('[data-bg]'); return s && lineA[sections.indexOf(s)] > 0; })
    .map(h => h.closest('.hw-card, .pay-card') || h);   // a whole card is one surface: no lines through its image or its text
  const measureLines = () => {
    const cols = [...document.querySelectorAll('#hero .grid-lines .frame > i')].filter(i => i.offsetWidth > 0);
    if (!cols.length) return;
    const xs = cols.map(i => i.getBoundingClientRect().left); xs.push(cols[cols.length - 1].getBoundingClientRect().right - 1);
    xs.slice(0, 5).forEach((x, k) => u.uLineX.value[k] = x + .5); u.uLineN.value = Math.min(5, xs.length); lineMeasured = true;
  };
  addEventListener('resize', () => lineMeasured = false);
  return {
    render(r, scroll) {
      let n = 0;
      for (let i = 0; i < sections.length && n < MAXS; i++) {
        const rc = sections[i].getBoundingClientRect();
        if (rc.top > VP.h + 800) break;
        if (rc.bottom < -800 && i < sections.length - 1) continue;
        const col = cols[i];
        u.uLines.value[n] = lineA[i];
        u.uTop.value[n] = n === 0 ? -1e5 : rc.top; u.uBlend.value[n] = +(sections[i].dataset.blend || 0); u.uCol.value[n].set(col.r, col.g, col.b); n++;
      }
      if (!lineMeasured) measureLines();
      let hn = 0;
      for (const hs of lineHosts) { if (hn >= 8) break; const rc = hs.getBoundingClientRect(); if (rc.bottom < 0 || rc.top > VP.h) continue; u.uHole.value[hn++].set(rc.left, rc.top, rc.right, rc.bottom); }
      u.uHoleN.value = hn;
      u.uN.value = Math.max(1, n); u.uRes.value.set(VP.w * VP.dpr, VP.h * VP.dpr); u.uDpr.value = VP.dpr; u.uScroll.value = scroll;
      r.setRenderTarget(null); r.setScissorTest(false); r.setViewport(0, 0, VP.w, VP.h);
      const tm = r.toneMapping; r.toneMapping = THREE.NoToneMapping; r.render(sc, cam); r.toneMapping = tm;
    },
    darkAt(y) {   // 0 (paper) .. 1 (night) at a viewport y, for petals / nav
      let d = 0;
      for (const s of sections) { const rc = s.getBoundingClientRect(); if (rc.top <= y && rc.bottom > y) { d = s.classList.contains('dark') ? 1 : 0; break; } }
      return d;
    },
  };
})();

/* ------------------------------------------------------------------ fade-in veil: a freshly built scene rises out of its section colour */
const veil = (() => {
  const u = { uCol: { value: new THREE.Vector3() }, uA: { value: 1 } };
  const m = new THREE.ShaderMaterial({ uniforms: u, transparent: true, depthTest: false, depthWrite: false,
    vertexShader: `void main(){ gl_Position = vec4(position.xy, 0., 1.); }`,
    fragmentShader: `uniform vec3 uCol; uniform float uA; void main(){ gl_FragColor = vec4(uCol, uA); }` });
  const g = new THREE.BufferGeometry(); g.setAttribute('position', new THREE.Float32BufferAttribute([-1, -1, 0, 3, -1, 0, -1, 3, 0], 3));
  const mesh = new THREE.Mesh(g, m); mesh.frustumCulled = false; const sc = new THREE.Scene(); sc.add(mesh); const cam = new THREE.OrthographicCamera(-1, 1, 1, -1, 0, 1);
  const c = new THREE.Color();
  return (r, host, clip, a) => {
    c.setStyle(host.section?.dataset.bg || '#F3EADB', THREE.LinearSRGBColorSpace); u.uCol.value.set(c.r, c.g, c.b); u.uA.value = a;
    r.setRenderTarget(null); r.setViewport(0, 0, VP.w, VP.h); r.setScissor(clip.left, VP.h - clip.bottom, clip.width, clip.height); r.setScissorTest(true);
    const tm = r.toneMapping; r.toneMapping = THREE.NoToneMapping; r.render(sc, cam); r.toneMapping = tm; r.setScissorTest(false);
  };
})();

/* ------------------------------------------------------------------ scene hosts */
const hosts = $$('[data-scene]').map(el => ({ el, name: el.dataset.scene, obj: null, state: 'idle', section: el.closest('section, footer'), anchors: $$('.gl-anchor', el).map(a => ({ el: a, name: a.dataset.anchor, x: -1e4, y: -1e4, on: false })) }));
const only = Q.get('only');            // ?only=hero,chart to build just some scenes
async function buildHost(h) {
  if (h.state !== 'idle') return; h.state = 'loading';
  try {
    const mod = await import(`./scenes/${h.name}.js`);
    const env = await loadEnv();
    h.obj = await mod.create({ host: h.el, name: h.name, renderer, env: { ...env, studio: studioEnv() }, THREE, VP, STATE, PTR, Post });
    if (h.obj.post && !(h.obj.post instanceof Post)) h.obj.post = new Post(h.obj.post);
    h.state = 'ready'; h.born = performance.now();
    h.el.classList.add('gl-ready');
    if (h.obj.compile !== false) try { renderer.compile(h.obj.scene, h.obj.camera); } catch (e) { }
  } catch (e) { h.state = 'missing'; console.warn(`[sunset] scene "${h.name}" not available:`, e.message); }
}
(async () => {
  const list = only ? hosts.filter(h => only.split(',').includes(h.name)) : hosts;
  // build the hero first, then whatever is closest to the viewport, one at a time
  for (const h of list) { await buildHost(h); await yieldTask(); frame(performance.now(), true); }
})();

/* ------------------------------------------------------------------ petals */
const petals = new Petals(VP.mobile ? 90 : 160);
if (Q.has('nopetals')) petals.density = 0;
const near = new NearPetals($('#petals-near'), VP.mobile ? 0 : 4);

/* ------------------------------------------------------------------ DOM behaviour */
const yen = v => v >= 1e6 ? `¥${(v / 1e6).toFixed(1)}M` : `¥${Math.round(v).toLocaleString('en-US')}`;
const bill = $('#bill');
function setBill(v) {
  STATE.set('bill', v); const c = costs(v);
  $('#billOut').innerHTML = `¥${v.toLocaleString('en-US')}<small> / mo</small>`;
  $('#saveOut').textContent = yen(c.save); $('#monthOut').textContent = yen(Math.round(c.save / 300 / 100) * 100);
  $('#lblGrid').textContent = yen(c.grid); $('#lblSolar').textContent = yen(c.solar); $('#lblSunset').textContent = yen(c.sunset);
  bill.style.setProperty('--p', `${(v - bill.min) / (bill.max - bill.min) * 100}%`);
}
bill?.addEventListener('input', () => setBill(+bill.value)); if (bill) setBill(+bill.value);

for (const qa of $$('.qa')) qa.querySelector('button').addEventListener('click', () => { const open = !qa.classList.contains('open'); for (const o of $$('.qa.open')) { o.classList.remove('open'); o.querySelector('button').setAttribute('aria-expanded', 'false'); } if (open) { qa.classList.add('open'); qa.querySelector('button').setAttribute('aria-expanded', 'true'); } });

const REGIONS = [['Hokkaido', 'sapporo', 184], ['Tohoku', 'sendai', 212], ['Tokyo', 'tokyo', 640], ['Kanagawa', 'yokohama', 512], ['Chubu', 'nagoya', 388], ['Kansai', 'osaka', 571], ['Kyoto', 'kyoto', 244], ['Chugoku', 'hiroshima', 196], ['Shikoku', 'matsuyama', 121], ['Kyushu', 'fukuoka', 298]];
$('#zipForm')?.addEventListener('submit', e => {
  e.preventDefault();
  const v = $('#zipIn').value.replace(/\D/g, '');
  const out = $('#zipOut');
  if (v.length < 3) { out.textContent = 'Enter at least the first three digits of your postal code.'; return; }
  const d = +v[0], rg = d === 0 ? REGIONS[0] : d === 1 ? REGIONS[2] : d === 2 ? REGIONS[3] : d <= 4 ? REGIONS[4] : d === 5 ? REGIONS[5] : d === 6 ? REGIONS[6] : d === 7 ? REGIONS[7] : d === 8 ? REGIONS[9] : REGIONS[1];
  out.textContent = `Yes, we install in ${rg[0]}. ${rg[2]} Sunset homes within 20 km of ${v.slice(0, 3)}-${(v.slice(3) + '0000').slice(0, 4)}.`;
  STATE.set('city', rg[1]);
});

const reveals = $$('.rv'), orns = $$('.orn[data-depth]'), keepEls = $$('[data-keep]');
const stepsEl = $$('#how .step'), howBar = $('#how .how-bar i'), how = $('#how');

/* ------------------------------------------------------------------ loop */
let last = performance.now(), T = 0, frameN = 0, lastScroll = scrollY, scrollV = 0, frozen = Q.has('freeze') ? +Q.get('freeze') || 0 : null;
let ftAvg = 16.7, lastGov = 0, lastFrameAt = 0;
const rectOf = el => el.getBoundingClientRect();
function resize() {
  const prevW = VP.w, prevH = VP.h; readViewport();
  renderer.setPixelRatio(VP.dpr); renderer.setSize(VP.w, VP.h, false);
  petals.resize(VP.w, VP.h); near.resize();
}
addEventListener('resize', resize); resize();

function frame(now, forced) {
  lastFrameAt = now;
  const dt = Math.min(Math.max((now - last) / 1000, 0), 1 / 20); last = now;
  if (frozen === null) T += dt; else T = frozen;
  frameN++;
  lenis?.raf(now);
  const sy = lenis ? lenis.animatedScroll : scrollY;
  scrollV = damp(scrollV, (sy - lastScroll) / Math.max(dt, 1 / 240), 8, dt); lastScroll = sy;

  // governor: keep frames near the vsync cap by trading pixel ratio (never below 1)
  if (!forced && dt > 0) ftAvg = ftAvg * .95 + dt * 1000 * .05;
  if (!forced && now - lastGov > 2500 && !Q.has('dpr')) {
    if (ftAvg > 24 && VP.dpr > 1) { VP.dpr = Math.max(1, VP.dpr - .25); resize(); lastGov = now; }
    else if (ftAvg < 15 && VP.dpr < VP.maxDpr) { VP.dpr = Math.min(VP.maxDpr, VP.dpr + .25); resize(); lastGov = now; }
  }

  ground.render(renderer, sy);

  const H = VP.h, W = VP.w;
  for (const h of hosts) {
    if (h.state !== 'ready') continue;
    const r = rectOf(h.el);
    const vis = r.bottom > 0 && r.top < H && r.right > 0 && r.left < W && r.width > 2 && r.height > 2;
    h.visible = vis;
    if (!vis) { for (const a of h.anchors) if (a.on) { a.on = false; a.el.classList.remove('on'); } continue; }
    const o = h.obj, sec = h.section ? rectOf(h.section) : r;
    const s = {
      rect: r, w: r.width, h: r.height, dt, t: T,
      progress: clamp((H - r.top) / (H + r.height)),
      pin: clamp(-sec.top / Math.max(1, sec.height - H)),
      pointer: { x: clamp((PTR.x - (r.left + r.width / 2)) / (r.width / 2), -1.5, 1.5), y: clamp((PTR.y - (r.top + r.height / 2)) / (r.height / 2), -1.5, 1.5) },
      hover: PTR.x >= r.left && PTR.x <= r.right && PTR.y >= r.top && PTR.y <= r.bottom,
      scrollV, age: (now - h.born) / 1000,
    };
    if (o.autoAspect !== false && o.camera.isPerspectiveCamera) { const a = r.width / r.height; if (Math.abs(o.camera.aspect - a) > 1e-4) { o.camera.aspect = a; o.camera.updateProjectionMatrix(); } }
    o.update?.(dt, T, s);
    const clip = { left: Math.max(0, r.left), top: Math.max(0, r.top), right: Math.min(W, r.right), bottom: Math.min(H, r.bottom) };
    clip.width = clip.right - clip.left; clip.height = clip.bottom - clip.top;
    if (o.post) o.post.render(renderer, o.scene, o.camera, r, clip, VP.dpr, T);
    else {
      renderer.setRenderTarget(null);
      renderer.setViewport(r.left, H - r.bottom, r.width, r.height);
      renderer.setScissor(clip.left, H - clip.bottom, clip.width, clip.height); renderer.setScissorTest(true);
      renderer.clear(false, true, false);
      renderer.toneMapping = o.tone === 'agx' ? THREE.AgXToneMapping : o.tone === 'neutral' ? THREE.NeutralToneMapping : THREE.ACESFilmicToneMapping;
      renderer.toneMappingExposure = o.exposure ?? 1;
      renderer.render(o.scene, o.camera);
      renderer.setScissorTest(false);
    }
    const fade = Q.has('freeze') ? 1 : clamp(s.age / 1.1);
    if (fade < 1) veil(renderer, h, clip, 1 - fade * fade * (3 - 2 * fade));
    // DOM labels pinned to 3-D points
    if (h.anchors.length && o.anchors) for (const a of h.anchors) {
      const src = o.anchors[a.name]; if (!src) continue;
      const v = src.isVector3 ? _p.copy(src) : src.getWorldPosition(_p);
      v.project(o.camera);
      const x = (v.x * .5 + .5) * r.width, y = (-v.y * .5 + .5) * r.height;
      const on = v.z < 1 && (o.anchorOn ? o.anchorOn(a.name) : true);
      if (Math.abs(x - a.x) > .2 || Math.abs(y - a.y) > .2) { a.el.style.transform = `translate(${x.toFixed(1)}px,${y.toFixed(1)}px)`; a.x = x; a.y = y; }
      if (on !== a.on) { a.on = on; a.el.classList.toggle('on', on); }
    }
  }

  // petals: density follows the section under the viewport middle
  let dens = .45, dark = ground.darkAt(H * .5);
  for (const s of sections) { const rc = rectOf(s); if (rc.top <= H * .5 && rc.bottom > H * .5) { dens = s.id === 'hero' ? .75 : s.id === 'how' ? .25 : s.classList.contains('dark') ? .4 : .5; break; } }
  // text blocks petals must never cross: the hero copy column and its stats strip (plus the headline block of whichever section is centred)
  const keep = []; const hc = document.querySelector('#hero .hero-copy'), hs = document.querySelector('#hero .hero-stats');
  if (hc) { const r = hc.getBoundingClientRect(); if (r.bottom > 0 && r.top < H) keep.push({ left: r.left, top: r.top + 110, right: Math.min(r.right, r.left + 640), bottom: r.bottom }); }
  if (hs) { const r = hs.getBoundingClientRect(); if (r.bottom > 0 && r.top < H) keep.push(r); }
  for (const el of keepEls) { if (keep.length >= 8) break; const r = el.getBoundingClientRect(); if (r.bottom > 0 && r.top < H) { const c = el.querySelector('h2')?.getBoundingClientRect(), st = el.querySelector('.steps')?.getBoundingClientRect(); keep.push(c && st ? { left: r.left, top: c.top, right: Math.max(c.right, st.right), bottom: st.bottom } : r); } }
  // …and every scene on the paper: a petal drawn over lacquer or coins looks stuck to them
  for (const h of hosts) { if (keep.length >= 8) break; if (!h.visible || !h.section || h.section.classList.contains('dark') || h.name === 'hero') continue; keep.push(h.el.getBoundingClientRect()); }
  petals.keepOut(keep);
  petals.update(dt, T, sy, Q.has('nopetals') ? 0 : dens, dark); petals.render(renderer);
  // the big near-layer petals belong to the hero only: over data (chart labels, prices) they read as smudges
  const heroRc = rectOf(sections[0]);
  near.update(dt, scrollV, !Q.has('nopetals') && heroRc.bottom > H * .45);

  // DOM (throttled reads, transform-only writes)
  if (frameN % 4 === 0 || forced) {
    for (const el of reveals) if (!el.classList.contains('in')) { const rc = rectOf(el); if (rc.top < H * .92 && rc.bottom > 0) el.classList.add('in'); }
    for (const el of orns) { const rc = rectOf(el.parentElement); if (rc.bottom < -200 || rc.top > H + 200) continue; const y = clamp((rc.top + rc.height / 2 - H / 2) * -(+el.dataset.depth) * .35, -70, 70); el.style.transform = `translate3d(0,${y.toFixed(1)}px,0)`; }
  }
  if (how) {
    const rc = rectOf(how), p = clamp(-rc.top / Math.max(1, rc.height - H));
    const k = Math.min(2, Math.floor(p * 3 + .08));
    stepsEl.forEach((el, i) => el.classList.toggle('on', i === k));
    if (howBar) howBar.style.width = `${(p * 100).toFixed(2)}%`;
  }
}
const _p = new THREE.Vector3();
function loop(now) { frame(now); requestAnimationFrame(loop); }
requestAnimationFrame(loop);
// when rAF stalls (background tab, a hidden preview pane) keep painting slowly so captures are never blank
setInterval(() => { const n = performance.now(); if (n - lastFrameAt > 400) frame(n, true); }, 250);
frame(performance.now(), true);

/* ------------------------------------------------------------------ harness API */
window.__sun = {
  hosts, lenis, renderer, VP, STATE,
  freeze(t) { frozen = t; }, unfreeze() { frozen = null; },
  ready() { return hosts.filter(h => !only || only.split(',').includes(h.name)).every(h => h.state === 'ready' || h.state === 'missing'); },
  status() { return Object.fromEntries(hosts.map(h => [h.name, h.state])); },
  jump(sel, off = 0) { const el = $(sel); if (!el) return; const y = el.getBoundingClientRect().top + scrollY + off; lenis ? lenis.scrollTo(y, { immediate: true }) : scrollTo(0, y); frame(performance.now(), true); },
  render() { frame(performance.now(), true); },
  fps() { return 1000 / ftAvg; },
};
