/* =====================================================================================
   Sunseto brand guide. The live parts are ports of the site's own code (sunset-assets/src,
   read only): wave.js (the sunset print), dom.js (glass nav, chart tray, heading hand-off,
   reveals), sections.js (postmark, pricing) and main.js (the button's tide).
   ===================================================================================== */
(() => {
'use strict';
const clamp = (v, a = 0, b = 1) => Math.min(b, Math.max(a, v));
const lerp = (a, b, t) => a + (b - a) * t;
const inv = (a, b, v) => clamp((v - a) / (b - a));
const smooth = (a, b, v) => { const t = inv(a, b, v); return t * t * (3 - 2 * t); };
const E = {                                                   // core.js
  inOutQuint: t => t < .5 ? 16 * t ** 5 : 1 - (-2 * t + 2) ** 5 / 2,
  inOutCubic: t => t < .5 ? 4 * t ** 3 : 1 - (-2 * t + 2) ** 3 / 2,
  outCubic: t => 1 - (1 - t) ** 3,
  outQuart: t => 1 - (1 - t) ** 4,
  outExpo: t => t >= 1 ? 1 : 1 - 2 ** (-10 * t),
  inOutSine: t => -(Math.cos(Math.PI * t) - 1) / 2,
  inQuad: t => t * t,
};
const $ = (s, r = document) => r.querySelector(s);
const $$ = (s, r = document) => [...r.querySelectorAll(s)];
const reduce = matchMedia('(prefers-reduced-motion: reduce)').matches;
const VP = { w: 1440, h: 900 };
function readViewport() {
  VP.w = window.innerWidth || document.documentElement.clientWidth || Math.min(screen.width || 1440, 1600);
  VP.h = window.innerHeight || document.documentElement.clientHeight || Math.min(screen.height || 900, 900);
}
readViewport();
const PTR = { x: -1e4, y: -1e4 };
addEventListener('pointermove', e => { PTR.x = e.clientX; PTR.y = e.clientY; }, { passive: true });
const onScreen = (el, m = 60) => { const r = el.getBoundingClientRect(); return r.width > 0 && r.bottom > -m && r.top < VP.h + m; };
const hex3 = h => { h = h.replace('#', ''); return [0, 2, 4].map(i => parseInt(h.slice(i, i + 2), 16) / 255); };

/* ------------------------------------------------------------------ the sunset print
   wave.js's fragment shader, unchanged, on one shared WebGL context: each view renders into
   the corner of the shared drawing buffer and is copied onto its own 2-D canvas. */
const WAVE_FRAG = `
precision highp float;
varying vec2 vUv;
uniform vec2 uRes; uniform float uTime, uGrain, uDpr, uHz, uSunR, uSunX, uSunY, uSunDeep, uClouds, uCloudY;
uniform vec3 uC0, uC1, uC2; uniform vec2 uOff; uniform float uScale;
uniform float uSwell, uSpark, uBurst, uDusk, uMoon;
float hash12(vec2 p){ vec3 p3 = fract(vec3(p.xyx)*.1031); p3 += dot(p3, p3.yzx+33.33); return fract((p3.x+p3.y)*p3.z); }
float hsh(float n){ return fract(sin(n * 91.3458) * 47453.5453); }
float band(vec2 p, vec2 c, float halfLen, float th){
  vec2 q = p - c; q.x = max(abs(q.x) - halfLen, 0.0);
  return length(q) - th * (1.0 + 0.12 * sin(p.x * 9.0 + c.y * 40.0));
}
void main(){
  vec2 px = vUv*uRes;
  float S = max(uRes.x, uRes.y);
  vec2 p = (px - 0.5*uRes)/S*2.0*uScale + uOff;
  float fw = 2.0 / S * uScale * 1.2;
  float t = uTime;
  float h = p.y - uHz;
  float hs = h - uSwell * (sin(p.x * 11.0 - t * 3.2) * 0.65 + sin(p.x * 23.0 + t * 4.6) * 0.35);
  vec3 gold = vec3(1.0, .82, .45), orange = vec3(.98, .55, .24), coral = uC2, rose = uC1, indigo = uC0;
  vec3 col = mix(gold, orange, smoothstep(0.0, 0.16, h));
  col = mix(col, coral, smoothstep(0.1, 0.38, h));
  col = mix(col, rose, smoothstep(0.32, 0.72, h));
  col = mix(col, indigo, smoothstep(0.66, 1.45, h));
  vec2 sc = vec2(uSunX, uSunY > -9.0 ? uSunY : uHz + uSunR * 0.35);
  float d = length(p - sc);
  col += vec3(1.0, .6, .3) * exp(-max(d - uSunR, 0.0) * 4.0) * 0.28 * step(0.0, hs);
  float disc = (1.0 - smoothstep(uSunR - fw, uSunR + fw, d)) * smoothstep(-fw, fw, hs);
  vec3 sunCol = mix(vec3(1.0, .6, .28), vec3(1.0, .95, .74), smoothstep(-0.2, 1.0, (p.y - sc.y) / uSunR));
  sunCol = mix(sunCol, mix(vec3(.86, .24, .15), vec3(.98, .47, .22), smoothstep(-1.0, 1.0, (p.y - sc.y) / uSunR)), uSunDeep);
  col = mix(col, sunCol, disc);
  for (int i = 0; i < 3; i++) {
    float fi = float(i);
    float y = uCloudY + fi * 0.17 + 0.015 * sin(t * 0.07 + fi);
    float len = 0.22 + 0.16 * hsh(fi + 3.0), th = 0.014 + 0.008 * hsh(fi + 7.0);
    float x = fract((hsh(fi) * 3.0 + t * (0.006 + 0.004 * hsh(fi + 1.0)) * (mod(fi, 2.0) * 2.0 - 1.0)) / 3.2) * 3.2 - 1.6;
    float sd = band(p, vec2(x, y), len, th);
    float a = (1.0 - smoothstep(-fw, fw, sd)) * uClouds;
    float lit = smoothstep(0.0, -th * 1.6, p.y - y) * exp(-abs(p.x - uSunX) * 1.4);
    vec3 cc = mix(mix(col, vec3(1.0, .8, .78), 0.28), vec3(1.0, .76, .46), lit * 0.7);
    col = mix(col, cc, a * (0.7 - fi * 0.12));
  }
  if (hs < 0.0) {
    float dn = -hs;
    vec3 sea = mix(mix(coral, rose, 0.5) * 0.85, mix(rose, indigo, 0.75) * 0.8, smoothstep(0.0, 0.5, dn));
    float rowc = pow(dn, 0.62) * 70.0;
    float row = floor(rowc), fr = fract(rowc);
    float stroke = smoothstep(0.5, 0.0, abs(fr - 0.5) * 2.0 - 0.35);
    sea = mix(sea, sea * 1.18 + 0.02, stroke * 0.35);
    float w = uSunR * (0.55 + dn * 1.6);
    float xs = (p.x - uSunX) / w;
    float seg = floor((p.x - uSunX) * (18.0 / (0.4 + dn)) + hsh(row) * 7.0 + t * 0.35 * (hsh(row + 2.0) - 0.5));
    float on = step(0.45, hsh(seg * 1.7 + row * 3.1)) * stroke;
    float g = on * smoothstep(1.0, 0.2, abs(xs)) * 0.62 * smoothstep(-uSunR * 1.1, uSunR * 0.1, sc.y - uHz);
    sea = mix(sea, mix(sea, vec3(1.0, .8, .56), 0.78), g * smoothstep(0.0, 0.03, dn));
    col = mix(col, sea, smoothstep(0.0, fw, -hs));
  }
  col += vec3(1.0, .8, .55) * (1.0 - smoothstep(0.0, fw * 1.5, abs(hs))) * 0.25 * (1.0 - uDusk);
  if (uDusk > 0.0) {
    float lum = dot(col, vec3(0.299, 0.587, 0.114));
    vec3 night = mix(uC0 * 0.55, vec3(0.12, 0.1, 0.24), 0.35) + lum * vec3(0.3, 0.27, 0.44);
    col = mix(col, night, uDusk);
  }
  if (uMoon > 0.0) {
    vec2 mc = vec2(0.3, uHz + 0.92);
    float md = length(p - mc) - 0.07, mo = length(p - mc - vec2(0.03, 0.017)) - 0.064;
    float mk = (1.0 - smoothstep(-fw, fw, md)) * smoothstep(-fw, fw, mo) * step(0.0, hs);
    col = mix(col, vec3(1.0, 0.93, 0.8), mk * uMoon);
  }
  if (uSpark > 0.001) {
    float cpx = 2.0 * uDpr / S;
    float sp = 0.0;
    for (int i = 0; i < 16; i++) {
      float fi = float(i);
      float life = 1.6 + 1.6 * hsh(fi + 11.0);
      float k = t / life + hsh(fi + 5.0), ph = fract(k), cyc = floor(k);
      float jx = hsh(fi * 3.1 + cyc * 7.7) * 2.0 - 1.0;
      float sx = i < 9 ? uSunX + jx * uSunR * 1.4 : jx * 0.95;
      float rise = 0.14 + 0.3 * hsh(fi + 23.0 + cyc * 1.3);
      vec2 c = vec2(sx + sin(ph * 4.0 + fi * 2.3) * 0.018 + (hsh(fi + 31.0 + cyc) - 0.5) * 0.1 * ph, uHz + 0.004 + ph * rise);
      float r = cpx * (0.3 + 0.7 * pow(hsh(fi + 41.0 + cyc), 2.0)) * (1.0 - 0.45 * ph);
      float a = smoothstep(0.0, 0.1, ph) * pow(1.0 - ph, 1.4) * (0.5 + 0.5 * sin(t * 9.0 + fi * 4.1)) * 0.85;
      float dd = length(p - c);
      sp += a * (smoothstep(r + cpx * 0.7, r - cpx * 0.3, dd) + 0.3 * exp(-dd / (r * 2.2)));
    }
    float bt = uBurst - 0.1;
    if (bt > 0.0 && bt < 1.6) {
      for (int i = 0; i < 10; i++) {
        float fi = float(i);
        float tl = (bt - 0.3 * hsh(fi + 57.0)) / (0.6 + 0.5 * hsh(fi + 61.0));
        if (tl <= 0.0 || tl >= 1.0) continue;
        float vx = (hsh(fi + 67.0) - 0.5) * 0.6, vy = 0.4 + 0.6 * hsh(fi + 71.0);
        float tt = tl * 0.8;
        vec2 c = vec2(uSunX + (hsh(fi + 73.0) - 0.5) * uSunR * 2.4 + vx * tt, uHz + vy * tt - 0.5 * tt * tt);
        float r = cpx * (0.35 + 0.85 * pow(hsh(fi + 79.0), 2.0)) * (1.0 - 0.5 * tl);
        float a = smoothstep(0.0, 0.05, tl) * pow(1.0 - tl, 1.2);
        float dd = length(p - c);
        sp += a * (smoothstep(r + cpx * 0.7, r - cpx * 0.3, dd) + 0.3 * exp(-dd / (r * 2.2)));
      }
    }
    col += vec3(1.0, .9, .66) * min(sp, 1.2) * uSpark;
  }
  vec2 gp = floor(px/max(uDpr,1.0));
  col += (hash12(gp + fract(uTime*1.37)*vec2(113.0, 71.0)) - 0.5) * uGrain;
  gl_FragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}`;
const PALETTES = {                                            // wave.js
  phone: { c0: '#2c1d55', c1: '#b0406c', c2: '#ea5f4a' },
  button: { c0: '#4a2255', c1: '#c4466a', c2: '#f0683f' },
};
const PRINT = (() => {
  const cv = document.createElement('canvas');
  cv.width = cv.height = 16;
  const gl = cv.getContext('webgl', { alpha: false, antialias: false, depth: false, stencil: false, premultipliedAlpha: false, preserveDrawingBuffer: false });
  const views = [];
  if (!gl) return { views, add() {}, frame() {} };
  const sh = (type, src) => { const o = gl.createShader(type); gl.shaderSource(o, src); gl.compileShader(o); if (!gl.getShaderParameter(o, gl.COMPILE_STATUS)) console.error(gl.getShaderInfoLog(o)); return o; };
  const pr = gl.createProgram();
  gl.attachShader(pr, sh(gl.VERTEX_SHADER, 'attribute vec2 a; varying vec2 vUv; void main(){ vUv = a * .5 + .5; gl_Position = vec4(a, 0., 1.); }'));
  gl.attachShader(pr, sh(gl.FRAGMENT_SHADER, WAVE_FRAG));
  gl.bindAttribLocation(pr, 0, 'a'); gl.linkProgram(pr);
  if (!gl.getProgramParameter(pr, gl.LINK_STATUS)) { console.error(gl.getProgramInfoLog(pr)); return { views, add() {}, frame() {} }; }
  gl.useProgram(pr);
  gl.bindBuffer(gl.ARRAY_BUFFER, gl.createBuffer());
  gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 3, -1, -1, 3]), gl.STATIC_DRAW);
  gl.enableVertexAttribArray(0); gl.vertexAttribPointer(0, 2, gl.FLOAT, false, 0, 0);
  const U = {};
  for (const n of ['uRes', 'uTime', 'uGrain', 'uDpr', 'uHz', 'uSunR', 'uSunX', 'uSunY', 'uSunDeep', 'uClouds', 'uCloudY', 'uC0', 'uC1', 'uC2', 'uOff', 'uScale', 'uSwell', 'uSpark', 'uBurst', 'uDusk', 'uMoon']) U[n] = gl.getUniformLocation(pr, n);
  let GW = 16, GH = 16;
  function add(el, cfg) {
    const canvas = el.querySelector('canvas');
    if (!canvas) return;
    const P = PALETTES[cfg.pal || 'phone'];
    const s = { c0: hex3(P.c0), c1: hex3(P.c1), c2: hex3(P.c2), hz: -.3, sunR: .3, sunX: 0, sunY: -10, sunDeep: 0, clouds: 0, cloudY: .3, grain: .04, scale: 1, swell: 0, spark: 0, burst: 99, dusk: 0, moon: 0, ...cfg.s };
    const v = { el, canvas, ctx: canvas.getContext('2d', { alpha: false }), cfg, s, t0: cfg.t0 ?? Math.random() * 40, drawn: false };
    views.push(v);
    return v;
  }
  function render(v, t, dt, force) {
    const host = v.el;
    if (!force && !onScreen(host, 40)) return;
    const lw = host.offsetWidth, lh = host.offsetHeight;
    if (!lw || !lh) return;
    const dpr = Math.min(window.devicePixelRatio || 1, v.cfg.dprCap || 1.5);
    const w = Math.max(1, Math.round(lw * dpr)), h = Math.max(1, Math.round(lh * dpr));
    if (v.canvas.width !== w || v.canvas.height !== h) { v.canvas.width = w; v.canvas.height = h; }
    if (w > GW || h > GH) { GW = Math.max(GW, w); GH = Math.max(GH, h); cv.width = GW; cv.height = GH; }
    const s = v.s;
    if (v.cfg.update) v.cfg.update(s, v, t, dt, lw, lh);
    gl.viewport(0, 0, w, h);
    gl.uniform2f(U.uRes, w, h); gl.uniform1f(U.uTime, reduce ? 20 + v.t0 : t + v.t0); gl.uniform1f(U.uDpr, dpr);
    gl.uniform1f(U.uGrain, s.grain); gl.uniform1f(U.uHz, s.hz); gl.uniform1f(U.uSunR, s.sunR); gl.uniform1f(U.uSunX, s.sunX); gl.uniform1f(U.uSunY, s.sunY);
    gl.uniform1f(U.uSunDeep, s.sunDeep); gl.uniform1f(U.uClouds, s.clouds); gl.uniform1f(U.uCloudY, s.cloudY);
    gl.uniform3fv(U.uC0, s.c0); gl.uniform3fv(U.uC1, s.c1); gl.uniform3fv(U.uC2, s.c2);
    gl.uniform2f(U.uOff, s.offX || 0, 0); gl.uniform1f(U.uScale, s.scale);
    gl.uniform1f(U.uSwell, s.swell); gl.uniform1f(U.uSpark, s.spark); gl.uniform1f(U.uBurst, s.burst); gl.uniform1f(U.uDusk, s.dusk); gl.uniform1f(U.uMoon, s.moon);
    gl.drawArrays(gl.TRIANGLES, 0, 3);
    v.ctx.drawImage(cv, 0, cv.height - h, w, h, 0, 0, w, h);    // the view sits in the buffer's lower-left corner
    v.drawn = true;
  }
  return { views, add, frame(t, dt, force) { for (const v of views) render(v, t, dt, force); } };
})();

/* the button's sun behind one word of its label, and the tide that comes in on hover (main.js sunBehindWord) */
function tideButton(btn) {
  const word = btn.dataset.word || 'roof', label = btn.querySelector('span');
  const forced = btn.dataset.tide === '1';
  let n = 0, G = null, tide = forced ? 1 : 0, vel = 0, on = forced ? 1 : 0, since = 99, last = -1;
  if (!forced) {
    const set = k => { if (k && !on) since = 0; on = k; };
    btn.addEventListener('pointerenter', () => set(1));
    btn.addEventListener('pointerleave', () => set(btn.matches(':focus-visible') ? 1 : 0));
    btn.addEventListener('focus', () => { if (btn.matches(':focus-visible')) set(1); });
    btn.addEventListener('blur', () => set(btn.matches(':hover') ? 1 : 0));
  }
  return (s, v, t) => {
    if (!(n++ % 20 && n > 2) || !G) {
      const b = btn.getBoundingClientRect(), txt = label.firstChild;
      const i = txt ? txt.data.lastIndexOf(word) : -1;
      if (i >= 0 && b.width) {
        const r = document.createRange(); r.setStart(txt, i); r.setEnd(txt, i + word.length);
        const w = r.getBoundingClientRect(), S = Math.max(b.width, b.height);
        const cx = (w.left + w.width / 2 - b.left - b.width / 2) / S * 2, cy = (b.top + b.height / 2 - (w.top + w.height * .56)) / S * 2;
        const hw = w.width / S, hh = w.height * .36 / S;
        const R = Math.hypot(hw, hh) * 1.5;
        const drop = b.height * .12 / S * 2;
        const lb = label.getBoundingClientRect();
        G = { cx, R, sun: cy - drop, lift: b.height * .05 / S * 2, hz: (b.top + b.height / 2 - lb.bottom - 1.5) / S * 2, rest: -(b.height / 2 - 4.5 * b.height / 44) / S * 2, wave: 1.3 * b.height / 44 / S * 2 };
      }
    }
    if (!G) return;
    const dt = last < 0 ? 0 : Math.min(.05, Math.max(0, t - last)); last = t;
    if (reduce || forced) { tide = on; vel = 0; }
    else { const w = 11, z = .62; vel += (w * w * (on - tide) - 2 * z * w * vel) * dt; tide += vel * dt; }
    since += dt;
    const k = clamp(tide);
    s.sunX = G.cx; s.sunR = G.R;
    s.sunY = G.sun + G.lift * (1 - k);
    s.hz = G.rest + (G.hz - G.rest) * tide;
    s.swell = reduce ? G.wave * (1 - k) : Math.min(.03, G.wave * (1 - k) + Math.abs(vel) * .007);
    s.spark = reduce ? 0 : k * (forced ? .8 : 1);
    s.burst = forced ? 99 : since;
  };
}

/* ------------------------------------------------------------------ pricing (sections.js) */
const PLANS = {
  ko: { k: '小', name: 'Ko', for: '1–2 people', price: 9800, panels: '3.2 kW, 11 panels', batt: '5 kWh' },
  naka: { k: '中', name: 'Naka', for: '3–4 people', price: 13800, panels: '4.8 kW, 16 panels', batt: '10 kWh' },
  o: { k: '大', name: 'Ō', for: '5–6 people', price: 17800, panels: '6.4 kW, 21 panels', batt: '13.5 kWh' },
};
const NIGHT = [null, ['10:30 pm', .3], ['9:30 pm', .24], ['12:10 am', .58], ['11:20 pm', .52], ['Sunrise', 1], ['4:40 am', .92]];
const planOf = n => n <= 2 ? 'ko' : n <= 4 ? 'naka' : 'o';
const peopleLabel = n => n === 1 ? '1 person' : n === 6 ? '6 or more' : n + ' people';
function skyUpdate(state) {                                  // the pricing card's sky, from how deep into the night the plan carries you
  return (s, v, t, dt) => {
    state.shown += (state.night - state.shown) * Math.min(1, (dt || 0) * 3.2);
    if (reduce) state.shown = state.night;
    const k = state.shown;
    s.sunY = s.hz + s.sunR * (.35 - 2.4 * smooth(.15, .62, k));
    s.dusk = .82 * smooth(.12, 1, k);
    s.moon = smooth(.55, .95, k);
  };
}
const PRICE = { n: 3, night: NIGHT[3][1], shown: NIGHT[3][1], price: 13800, priceShown: 13800, plan: 'naka' };
(function pricing() {
  const input = $('#prPeople');
  if (!input) return;
  const tiers = $$('.pr-tiers button');
  function set(n) {
    n = clamp(Math.round(n), 1, 6);
    PRICE.n = n; input.value = n;
    input.style.setProperty('--f', ((n - 1) / 5 * 100).toFixed(1) + '%');
    const label = peopleLabel(n);
    $('#prPeopleOut').textContent = label; input.setAttribute('aria-valuetext', label);
    const id = planOf(n), P = PLANS[id];
    PRICE.night = NIGHT[n][1];
    $('#prUntil').textContent = NIGHT[n][0];
    if (id !== PRICE.plan) {
      PRICE.plan = id; PRICE.price = P.price;
      $('#prKanji').textContent = P.k; $('#prName').textContent = P.name; $('#prFor').textContent = P.for;
      $('#prPanels').textContent = P.panels; $('#prBatt').textContent = P.batt;
    }
    tiers.forEach(b => b.setAttribute('aria-pressed', b.dataset.plan === id ? 'true' : 'false'));
  }
  input.addEventListener('input', () => set(+input.value));
  tiers.forEach(b => b.addEventListener('click', () => set(+b.dataset.p)));
  set(3);
})();
const yen = v => (Math.round(v / 100) * 100).toLocaleString('en-US');
function pricingTick(dt) {
  if (Math.abs(PRICE.price - PRICE.priceShown) > .5) {
    PRICE.priceShown += (PRICE.price - PRICE.priceShown) * Math.min(1, dt * 9);
    if (Math.abs(PRICE.price - PRICE.priceShown) < 60 || reduce) PRICE.priceShown = PRICE.price;
    $('#prPrice').textContent = yen(PRICE.priceShown);
  }
}
const DUSK = { n: 3, night: NIGHT[3][1], shown: NIGHT[3][1] };
(function duskDemo() {
  const input = $('#duskPeople');
  if (!input) return;
  const set = n => {
    n = clamp(Math.round(n), 1, 6); DUSK.n = n; DUSK.night = NIGHT[n][1];
    input.style.setProperty('--f', ((n - 1) / 5 * 100).toFixed(1) + '%');
    $('#duskOut').textContent = peopleLabel(n); input.setAttribute('aria-valuetext', peopleLabel(n));
    $('#duskUntil').textContent = NIGHT[n][0]; $('#duskKanji').textContent = PLANS[planOf(n)].k;
  };
  input.addEventListener('input', () => set(+input.value));
  set(3);
})();

/* ------------------------------------------------------------------ register the prints */
const portrait = (lw, lh) => lw / Math.max(1, lh);
PRINT.add($('[data-print="hero"]'), { pal: 'phone', dprCap: 1.5, t0: 12, s: { hz: -.24, sunR: .17, sunX: .42, clouds: 0, grain: .04 },
  update(s, v, t, dt, lw, lh) { const a = portrait(lw, lh); s.sunX = a >= .75 ? 0 : a * .5; s.hz = a >= 1 ? -.24 : a >= .75 ? -.1 : .16; s.sunR = a >= 1 ? .17 : .2; } });   // on a portrait screen the horizon rises above the copy, so the type sits on the sea
$$('[data-print="plate"]').forEach(el => PRINT.add(el, { pal: 'phone', s: { hz: -.5, sunR: .24, sunX: 0, grain: .045 } }));
$$('[data-print="phone"]').forEach(el => PRINT.add(el, { pal: 'phone', s: { hz: -.56 * 1.333 / 1.333, sunR: .21, sunX: 0, grain: .045 },
  update(s, v, t, dt, lw, lh) { s.hz = -.56 * (lh / Math.max(lw, lh)); } }));
$$('[data-print="swatch-button"]').forEach(el => PRINT.add(el, { pal: 'button', s: { hz: -.3, sunR: .3, sunX: .12, sunDeep: 1, grain: .05 } }));
$$('[data-print="pricing"]').forEach(el => PRINT.add(el, { pal: 'phone', s: { hz: -.3, sunR: .19, sunX: .16, grain: .045 }, update: skyUpdate(PRICE) }));
$$('[data-print="dusk"]').forEach(el => PRINT.add(el, { pal: 'phone', s: { hz: -.3, sunR: .19, sunX: .16, grain: .045 }, update: skyUpdate(DUSK) }));
$$('[data-print="night"]').forEach(el => PRINT.add(el, { pal: 'phone', dprCap: 1.25, s: { hz: -.42, sunR: .19, sunX: .3, grain: .045, dusk: .82, moon: 1 },
  update(s, v, t, dt, lw, lh) { const a = portrait(lw, lh); s.hz = a >= 1 ? -.42 : -.5; s.offX = a >= 1 ? -.36 : 0; s.sunX = .3; s.sunY = s.hz - s.sunR * 2.1; } }));   // the moon sits at x .3 in the shader: offset it into the third column
$$('a[data-print="button"]').forEach(btn => PRINT.add(btn.querySelector('.view'), { pal: 'button', dprCap: 2, s: { hz: -.26, sunR: .3, sunX: .5, sunDeep: 1, grain: .05, cloudY: 1 }, update: tideButton(btn) }));

/* ------------------------------------------------------------------ liquid glass (dom.js GLASS) */
const GLASS = (() => {
  const pills = $$('.nav-pill[data-lens]'), svg = $('#lenses');
  const chromium = !!(navigator.userAgentData && navigator.userAgentData.brands.some(b => /Chromium/.test(b.brand)));
  if (chromium) document.documentElement.classList.add('lg-refract');
  svg.innerHTML = pills.map((_, i) => `<filter id="lgLens${i}" x="0" y="0" width="100%" height="100%" color-interpolation-filters="sRGB"><feImage id="lgMap${i}" x="0" y="0" width="600" height="58" preserveAspectRatio="none" result="map"/><feDisplacementMap in="SourceGraphic" in2="map" scale="30" xChannelSelector="R" yChannelSelector="G"/></filter>`).join('');
  const sizes = pills.map(() => [0, 0]);
  function build(i) {
    const pill = pills[i], img = document.getElementById('lgMap' + i);
    const w = Math.round(pill.offsetWidth), h = Math.round(pill.offsetHeight);
    if (!w || !h || (w === sizes[i][0] && h === sizes[i][1])) return;
    sizes[i] = [w, h];
    const c = document.createElement('canvas'); c.width = w; c.height = h;
    const g = c.getContext('2d'), id = g.createImageData(w, h), d = id.data;
    const R = parseFloat(getComputedStyle(pill).borderTopLeftRadius) || 16, band = 16;
    for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
      const px = x + .5, py = y + .5, sx = Math.sign(px - w / 2), sy = Math.sign(py - h / 2);
      const ex = w / 2 - Math.abs(px - w / 2), ey = h / 2 - Math.abs(py - h / 2);
      let din, nx, ny;
      if (ex < R && ey < R) { const cx = R - ex, cy = R - ey, L = Math.max(1e-3, Math.hypot(cx, cy)); din = R - L; nx = sx * cx / L; ny = sy * cy / L; }
      else if (ex < ey) { din = ex; nx = sx; ny = 0; } else { din = ey; nx = 0; ny = sy; }
      let ox = 0, oy = 0;
      if (din < band) { const t = 1 - Math.max(0, din) / band, m = Math.pow(t, 1.8); ox = -nx * m; oy = -ny * m; }
      const k = (y * w + x) * 4;
      d[k] = 128 + Math.round(ox * 127); d[k + 1] = 128 + Math.round(oy * 127); d[k + 2] = 128; d[k + 3] = 255;
    }
    g.putImageData(id, 0, 0);
    img.setAttribute('href', c.toDataURL()); img.setAttribute('width', w); img.setAttribute('height', h);
    pill.style.setProperty('--lens', `url(#lgLens${i})`);
  }
  const buildAll = () => pills.forEach((_, i) => build(i));
  // specimen pills scale to fit their plate (their lens is drawn at layout size, so scaling keeps it true)
  function fit() {
    for (const pill of $$('.nav-pill[data-fit]')) {
      const slot = pill.parentElement, plate = slot.closest('.plate');
      const s = Math.min(1, (plate.clientWidth - 40) / Math.max(1, pill.offsetWidth));
      slot.style.transform = s < 1 ? `scale(${s.toFixed(4)})` : '';
    }
  }
  buildAll(); fit();
  new ResizeObserver(() => { buildAll(); fit(); }).observe(document.documentElement);
  document.fonts && document.fonts.ready.then(() => { buildAll(); fit(); });
  const header = $('#header'), main = $('#header .nav-pill');
  let last = 0, dark = null, lx = -1, ly = -1;
  function update(t) {
    if (PTR.x !== lx || PTR.y !== ly) {                        // the rim is lit where each pill is nearest the cursor
      lx = PTR.x; ly = PTR.y;
      for (const pill of pills) {
        const r = pill.getBoundingClientRect(); if (!r.width || r.bottom < 0 || r.top > VP.h) continue;
        const k = pill.offsetWidth / r.width;
        const mx = clamp((PTR.x - r.left) * k, -60, pill.offsetWidth + 60), my = clamp((PTR.y - r.top) * k, -50, pill.offsetHeight + 50);
        pill.style.setProperty('--mx', mx.toFixed(0) + 'px'); pill.style.setProperty('--my', my.toFixed(0) + 'px');
      }
    }
    if (t - last < .15) return; last = t;
    const r = main.getBoundingClientRect(), y = r.top + r.height / 2;
    let isDark = false;
    for (const x of [r.left + r.width * .2, r.left + r.width * .5, r.left + r.width * .8]) {
      const hit = document.elementsFromPoint(x, y).find(e => !header.contains(e) && e.id !== 'gridOverlay' && !e.closest('#gridOverlay'));
      if (hit && hit.closest('[data-nav="dark"]')) isDark = true;
    }
    if (isDark !== dark) { dark = isDark; header.classList.toggle('dark', dark); }
  }
  return { update, buildAll };
})();

/* ------------------------------------------------------------------ reveals (dom.js) */
const svEls = $$('.sv');
svEls.forEach(el => el.classList.add('rv'));
function checkReveals() {
  for (const el of svEls) {
    if (el.classList.contains('in')) continue;
    const r = el.getBoundingClientRect();
    if (r.top < VP.h * 0.92 && r.bottom > 0) {
      const sib = [...el.parentElement.parentElement.querySelectorAll('.sv')];
      el.style.setProperty('transition-delay', (Math.max(0, sib.indexOf(el)) * 0.09) + 's');
      el.classList.add('in');
    }
  }
}
function revealIntro() {
  $$('#top .rv').forEach((el, i) => setTimeout(() => el.classList.add('in'), 250 + i * 90));
  setTimeout(() => $('#top .fade').classList.add('in'), 750);
}

/* ------------------------------------------------------------------ postmarks (sections.js) */
function postmarkSVG(place, date, time) {
  const arcTop = 'M9.5 42 A32.5 32.5 0 0 1 74.5 42', arcBot = 'M16 46 A26 26 0 0 0 68 46';
  const wave = y => `M78 ${y} q6 -3 12 0 t12 0 t12 0 t12 0`;
  const id = place.length + date.replace(/\W/g, '');
  return `<defs><path id="pmT${id}" d="${arcTop}"/><path id="pmB${id}" d="${arcBot}"/></defs>
    <circle cx="42" cy="42" r="39" fill="none" stroke="currentColor" stroke-width="1.6"/>
    <circle cx="42" cy="42" r="31" fill="none" stroke="currentColor" stroke-width=".9"/>
    <line x1="13" y1="34" x2="71" y2="34" stroke="currentColor" stroke-width=".8"/><line x1="13" y1="52" x2="71" y2="52" stroke="currentColor" stroke-width=".8"/>
    <text text-anchor="middle"><textPath href="#pmT${id}" startOffset="50%">${place}</textPath></text>
    <text class="c" x="42" y="47" text-anchor="middle">${date}</text>
    <text x="42" y="63" text-anchor="middle">${time.replace('-', ':')}</text>
    <g fill="none" stroke="currentColor" stroke-width="1.3" transform="translate(-4 0)"><path d="${wave(30)}"/><path d="${wave(42)}"/><path d="${wave(54)}"/></g>`;
}
const cards = $$('[data-pm]');
cards.forEach(c => {
  const [place, date, time] = c.dataset.pm.split('|');
  const svg = $('.hk-pm', c);
  if (svg) { svg.setAttribute('viewBox', '0 0 128 84'); svg.style.width = (128 * 110 / 84).toFixed(1) + 'px'; svg.innerHTML = postmarkSVG(place, date, time); }
});
function checkStamps() {
  for (const c of cards) {
    if (c.classList.contains('stamped')) continue;
    const r = c.getBoundingClientRect();
    if (r.width && (r.top < VP.h * .72 || r.bottom < VP.h * .92) && r.bottom > VP.h * .1) c.classList.add('stamped');
  }
}
$$('[data-replay]').forEach(b => b.addEventListener('click', () => {
  const c = document.getElementById(b.dataset.replay);
  c.classList.remove('stamped'); void c.offsetWidth; c.classList.add('stamped');
}));

/* ------------------------------------------------------------------ the chart tray (dom.js) */
const CH = { u: .5, v: .5, on: 0, in: false, rx: 0, ry: 0, lx: 1, ly: 1, p: 0, start: -1 };
(function buildChart() {
  const pts = [[0, 120], [22, 128], [45, 150], [68, 165], [95, 158], [118, 138], [140, 131], [165, 122], [190, 110], [210, 103], [232, 90], [255, 77], [275, 70], [295, 56], [318, 38], [338, 32], [355, 42], [372, 70], [390, 96], [410, 100]];
  const d = pts.map((p, i) => {
    if (i === 0) return `M${p[0]},${p[1]}`;
    const a = pts[i - 1], b = p, pa = pts[i - 2] || a, nb = pts[i + 1] || b;
    const c1 = [a[0] + (b[0] - pa[0]) / 6, a[1] + (b[1] - pa[1]) / 6], c2 = [b[0] - (nb[0] - a[0]) / 6, b[1] - (nb[1] - a[1]) / 6];
    return `C${c1[0].toFixed(1)},${c1[1].toFixed(1)} ${c2[0].toFixed(1)},${c2[1].toFixed(1)} ${b[0]},${b[1]}`;
  }).join(' ');
  $('#chartLineShape').setAttribute('d', d);
  $('#chartArea').setAttribute('d', d + ' L410,211 L0,211 Z');
  const use = [], batt = [];
  for (let i = 0; i <= 280; i++) {
    const x = i / 280 * 410, day = x / 58.57, h = (day % 1) * 24;
    const load = .3 + .25 * Math.exp(-((h - 7.5) ** 2) / 4) + .45 * Math.exp(-((h - 19) ** 2) / 6);
    use.push([x, 200 - load * 36]);
    const hh = h < 5 ? h + 24 : h, sg = z => 1 / (1 + Math.exp(-z));
    const soc = .28 + .6 * sg((hh - 11) / 1.6) - .6 * sg((hh - 21) / 2.2) + .12 * Math.sin(day * .9);
    batt.push([x, 176 - soc * 62]);
  }
  const poly = a => a.map((p, i) => (i ? 'L' : 'M') + p[0].toFixed(1) + ',' + p[1].toFixed(1)).join(' ');
  $('#chartUse').setAttribute('d', poly(use)); $('#chartBattShape').setAttribute('d', poly(batt));
  let gsv = '';
  for (let i = 0; i <= 28; i++) { const x = i / 28 * 410, day = i % 4 === 0; gsv += `<line x1="${x.toFixed(1)}" x2="${x.toFixed(1)}" y1="0" y2="211" stroke="rgba(76,40,6,${day ? .16 : .07})" stroke-width="1" vector-effect="non-scaling-stroke"${day ? '' : ' stroke-dasharray="2 4"'}/>`; }
  for (let j = 0; j <= 3; j++) { const y = j / 3 * 211; gsv += `<line x1="0" x2="410" y1="${y.toFixed(1)}" y2="${y.toFixed(1)}" stroke="rgba(76,40,6,.12)" stroke-width="1" vector-effect="non-scaling-stroke"/>`; }
  $('#chartGrid').innerHTML = gsv;
  const g = pts.map(p => (p[0] < 200 ? p : [p[0], p[1] - (p[0] - 200) * 0.06 - 6 * Math.sin((p[0] - 200) / 40)]));
  $('#chartGhost').setAttribute('d', g.map((p, i) => (i ? 'L' : 'M') + p[0] + ',' + p[1].toFixed(1)).join(' '));
  $('#chartGhost').setAttribute('stroke-linejoin', 'round');
  const c3 = $('#chart3d');
  c3.addEventListener('pointerenter', () => { CH.in = true; });
  c3.addEventListener('pointerleave', () => { CH.in = false; });
  c3.addEventListener('pointermove', e => { const r = c3.getBoundingClientRect(); CH.u = (e.clientX - r.left) / r.width; CH.v = (e.clientY - r.top) / r.height; }, { passive: true });
  $('#chartReplay').addEventListener('click', () => { CH.start = -2; });
})();
const shades = $$('#chartStage [data-l]').map(e => [e, e.dataset.l, e.hasAttribute('data-w')]);
function updateChart(t, dt) {
  const stage = $('#chartStage');
  CH.on += ((CH.in ? 1 : 0) - CH.on) * Math.min(1, dt * 4);
  const tx = lerp(0, (CH.v - .5) * 16, CH.on), ty = lerp(0, (CH.u - .5) * 24, CH.on);
  const k = 1 - Math.pow(.004, dt);
  CH.rx += (tx - CH.rx) * k; CH.ry += (ty - CH.ry) * k;
  if (Math.abs(CH.rx - CH.lx) + Math.abs(CH.ry - CH.ly) > .02) {
    CH.lx = CH.rx; CH.ly = CH.ry;
    stage.style.transform = `translateZ(-20px) rotateX(${CH.rx.toFixed(2)}deg) rotateY(${CH.ry.toFixed(2)}deg)`;
    const a = CH.rx * Math.PI / 180, b = CH.ry * Math.PI / 180, sa = Math.sin(a), ca = Math.cos(a), sb = Math.sin(b), cb = Math.cos(b);
    const lit = (x, y, z) => (0.5 + 0.5 * Math.max(0, (-0.398 * x + -0.597 * y + 0.697 * z + 0.35) / (1 + 0.35))) / 0.9591;
    const ex = [cb, sb * sa, -sb * ca], ey = [0, ca, sa];
    const L = { px: lit(ex[0], ex[1], ex[2]), nx: lit(-ex[0], -ex[1], -ex[2]), py: lit(0, ey[1], ey[2]), ny: lit(0, -ey[1], -ey[2]) };
    for (const [e, kk, w] of shades) e.style.opacity = Math.max(0, 1 - (w ? L[kk] * .7 + .36 : L[kk])).toFixed(3);
  }
  // the lines draw in over 2.4 s once the tray is well on screen (the site ties this to scroll)
  const r = $('#chart3d').getBoundingClientRect();
  if (CH.start === -1 && r.width && r.top < VP.h * .7 && r.bottom > VP.h * .2) CH.start = t;
  if (CH.start === -2) CH.start = t;
  const cp = reduce ? (CH.start >= 0 ? 1 : 0) : CH.start >= 0 ? E.outCubic(clamp((t - CH.start) / 2.4)) : 0;
  if (Math.abs(cp - CH.p) > 1e-4 || cp === 0) {
    CH.p = cp;
    $('#kwh').textContent = (11.9 * cp).toFixed(1);
    $('#chartClipRect').setAttribute('width', (18 + cp * 330).toFixed(1));
    $('#chartGhost').style.opacity = smooth(0.45, 0.7, cp) * 0.9;
    $('#chartNow').style.opacity = smooth(0.4, 0.55, cp);
    $('#chartChip').style.opacity = smooth(0.5, 0.62, cp);
    $('#chartUse').style.opacity = smooth(0.15, 0.4, cp); $('#chartBattShape').style.opacity = smooth(0.25, 0.5, cp);
  }
}

/* ------------------------------------------------------------------ easing cards */
const bezier = (x1, y1, x2, y2) => {
  const cx = 3 * x1, bx = 3 * (x2 - x1) - cx, ax = 1 - cx - bx, cy = 3 * y1, by = 3 * (y2 - y1) - cy, ay = 1 - cy - by;
  const X = t => ((ax * t + bx) * t + cx) * t, Y = t => ((ay * t + by) * t + cy) * t, dX = t => (3 * ax * t + 2 * bx) * t + cx;
  return x => { let t = x; for (let i = 0; i < 8; i++) { const e = X(t) - x, d = dX(t); if (Math.abs(e) < 1e-6 || Math.abs(d) < 1e-6) break; t -= e / d; } return Y(clamp(t)); };
};
const EASES = [
  { n: 'outCubic', f: E.outCubic, code: '1 − (1 − t)³', use: 'Tiles zooming out as their row enters, postcards rising, the drawings inking in.' },
  { n: 'inOutCubic', f: E.inOutCubic, code: 't < .5 ? 4t³ : 1 − (−2t + 2)³ / 2', use: 'The heading hand-off, the phone’s toggle, the hero window settling.' },
  { n: 'inOutQuint', f: E.inOutQuint, code: 't < .5 ? 16t⁵ : 1 − (−2t + 2)⁵ / 2', use: 'The app icon growing into the phone: long ends, a quick middle.' },
  { n: 'inOutSine', f: E.inOutSine, code: '−(cos πt − 1) / 2', use: 'The call to action’s panel, and anything that should simply breathe.' },
  { n: 'outQuart', f: E.outQuart, code: '1 − (1 − t)⁴', use: 'In the set, not on the page yet. Between outCubic and outExpo.' },
  { n: 'outExpo', f: E.outExpo, code: '1 − 2^(−10t)', use: 'In the set, not on the page yet. The JS twin of the CSS expo-out.' },
  { n: 'inQuad', f: E.inQuad, code: 't²', use: 'In the set, not on the page yet. For things leaving, never arriving.' },
  { n: 'Expo out', f: bezier(.16, 1, .3, 1), code: 'cubic-bezier(.16, 1, .3, 1)', use: 'The house curve: line reveals, fades, buttons, the nav hiding.', css: 1 },
  { n: 'Curtain', f: bezier(.77, 0, .175, 1), code: 'cubic-bezier(.77, 0, .175, 1)', use: 'The loader lifting like a noren curtain.', css: 1 },
  { n: 'Stamp', f: bezier(.3, 1.4, .5, 1), code: 'cubic-bezier(.3, 1.4, .5, 1)', use: 'The postmark and the seal. The only curve that overshoots: a thump.', css: 1 },
  { n: 'Glass', f: bezier(.2, .8, .2, 1), code: 'cubic-bezier(.2, .8, .2, 1)', use: 'The nav rim’s light following the cursor.', css: 1 },
];
const easeEls = [];
(function easeCards() {
  const host = $('#eases');
  if (!host) return;
  host.innerHTML = `<div class="ledger"><small class="mono">Eleven curves</small><h4 class="serif">Seven in code, four in CSS</h4><p>Scroll-driven moves read their progress through a curve from <span class="code">E</span> in core.js; CSS transitions use four cubic-béziers. The dot on each card runs its curve; the bar below shows the motion it makes.</p></div>` +
    EASES.map((e, i) => {
      const N = 64, pts = [];
      for (let k = 0; k <= N; k++) { const x = k / N; pts.push([x, e.f(x)]); }
      const P = ([x, y]) => `${(10 + x * 180).toFixed(2)},${(150 - y * 120).toFixed(2)}`;
      return `<div class="ease"><div class="top"><b>${e.n}</b><span class="mono">${e.css ? 'CSS' : 'E.' + e.n}</span></div><code>${e.code}</code><p>${e.use}</p>
        <svg viewBox="0 0 200 170" aria-hidden="true"><rect x="10" y="30" width="180" height="120" fill="none" stroke="#dacab6" stroke-width="1" vector-effect="non-scaling-stroke"/>
        <line x1="10" y1="150" x2="190" y2="30" stroke="#dacab6" stroke-dasharray="3 4" stroke-width="1" vector-effect="non-scaling-stroke"/>
        <polyline points="${pts.map(P).join(' ')}" fill="none" stroke="#4c2806" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" vector-effect="non-scaling-stroke"/>
        <circle r="4.5" fill="#e5482f" cx="10" cy="150"/></svg><div class="track"><i></i></div></div>`;
    }).join('');
  $$('.ease', host).forEach((el, i) => easeEls.push({ el, f: EASES[i].f, dot: $('circle', el), bar: $('.track i', el), off: i * .09 }));
})();
function updateEases(t) {
  const P = 2.6;
  for (const e of easeEls) {
    if (!onScreen(e.el)) continue;
    const ph = ((t - e.off) % P + P) % P, x = reduce ? 1 : clamp((ph - .5) / 1.6);
    const y = e.f(x);
    e.dot.setAttribute('cx', (10 + x * 180).toFixed(2)); e.dot.setAttribute('cy', (150 - y * 120).toFixed(2));
    e.bar.style.left = (clamp(y, -.1, 1.15) * 100).toFixed(2) + '%';
  }
}

/* ------------------------------------------------------------------ heading hand-off (dom.js USPM), scrubbed */
const HAND = (() => {
  const box = $('#handoff'), scrub = $('#handoffScrub'), pct = $('#handoffP');
  if (!box) return { update() {} };
  const heads = $$('.hd', box), layer = $('.fly', box);
  const STYLE = ['fontFamily', 'fontSize', 'fontWeight', 'fontStyle', 'letterSpacing', 'color', 'textTransform', 'fontFeatureSettings', 'fontVariationSettings'];
  let W = 0, T = null, lastP = -1, dirty = true, touched = -99, P = 0;
  document.fonts && document.fonts.ready.then(() => { dirty = true; });
  scrub.addEventListener('input', () => { touched = performance.now() / 1000; P = scrub.value / 1000; });
  function glyphs(el, base) {
    const out = [], up = getComputedStyle(el).textTransform === 'uppercase', r = document.createRange();
    const tw = document.createTreeWalker(el, NodeFilter.SHOW_TEXT);
    for (let nd; (nd = tw.nextNode());) for (let i = 0; i < nd.data.length; i++) {
      const ch = nd.data[i]; if (/\s/.test(ch)) continue;
      r.setStart(nd, i); r.setEnd(nd, i + 1);
      const b = r.getBoundingClientRect(); if (!b.width) continue;
      const k = box.offsetWidth / base.width;              // layout px, in case the box is scaled
      out.push({ ch, key: up ? ch.toUpperCase() : ch, x: (b.left - base.left) * k, y: (b.top - base.top) * k, h: b.height * k, w: b.width * k });
    }
    return out;
  }
  function lcs(a, b) {
    const L = Array.from({ length: a.length + 1 }, () => new Uint16Array(b.length + 1));
    for (let i = a.length - 1; i >= 0; i--) for (let j = b.length - 1; j >= 0; j--) L[i][j] = a[i] === b[j] ? L[i + 1][j + 1] + 1 : Math.max(L[i + 1][j], L[i][j + 1]);
    const m = [];
    for (let i = 0, j = 0; i < a.length && j < b.length;) { if (a[i] === b[j]) { m.push([i, j]); i++; j++; } else if (L[i + 1][j] >= L[i][j + 1]) i++; else j++; }
    return m;
  }
  function span(g, cs) {
    const e = document.createElement('fx-i'); e.textContent = g.ch;
    for (const k of STYLE) e.style[k] = cs[k];
    e.style.left = g.x + 'px'; e.style.top = g.y + 'px'; e.style.lineHeight = g.h + 'px';
    layer.appendChild(e); return e;
  }
  function build() {
    const base = box.getBoundingClientRect();
    layer.textContent = '';
    const t = { fly: [], out: [], in: [], gOut: [], gIn: [] };
    const parts = heads.map(h => [$('.mono', h), $('h4', h)]);
    for (let q = 0; q < 2; q++) {
      const ea = parts[0][q], eb = parts[1][q];
      const A = glyphs(ea, base), B = glyphs(eb, base), ca = getComputedStyle(ea), cb = getComputedStyle(eb);
      const m = lcs(A.map(g => g.key), B.map(g => g.key)), to = new Map(m), taken = new Set(m.map(x => x[1]));
      const fly = [];
      A.forEach((g, i) => {
        const e = span(g, ca), o = i / Math.max(1, A.length - 1);
        if (to.has(i)) { const h = B[to.get(i)]; fly.push({ e, o, g, h, dx: h.x - g.x, dy: h.y - g.y }); t.gOut.push(span(g, ca)); t.gIn.push(span(h, cb)); }
        else t.out.push({ e, o });
      });
      if (fly.length) {
        const tw = fly.reduce((s, f) => s + f.g.w, 0) * 1.08;
        const sx = fly.reduce((s, f) => s + f.g.x + f.g.w / 2, 0) / fly.length, sy = fly.reduce((s, f) => s + f.g.y, 0) / fly.length;
        const ex = fly.reduce((s, f) => s + f.h.x + f.h.w / 2, 0) / fly.length, ey = fly.reduce((s, f) => s + f.h.y, 0) / fly.length;
        let cx = -tw / 2;
        for (const f of fly) { const ox = cx + f.g.w * .04; cx += f.g.w * 1.08; f.ax = sx + ox - f.g.x; f.ay = sy - f.g.y; f.bx = ex + ox - f.g.x; f.by = ey - f.g.y; t.fly.push(f); }
      }
      B.forEach((g, j) => { if (!taken.has(j)) t.in.push({ e: span(g, cb), o: j / Math.max(1, B.length - 1) }); });
    }
    T = t; lastP = -1;
  }
  function show(t, p) {
    const s = .02, pf = inv(.22, .78, p);
    for (const f of t.fly) {
      const u = inv(s * f.o, s * f.o + 1 - s, pf);
      let x, y;
      if (u < .28) { const k = E.inOutCubic(u / .28); x = f.ax * k; y = f.ay * k; }
      else if (u < .6) { const k = E.inOutCubic((u - .28) / .32); x = lerp(f.ax, f.bx, k); y = lerp(f.ay, f.by, k) - Math.sin(Math.PI * k) * 26; }
      else { const k = E.inOutCubic((u - .6) / .4); x = lerp(f.bx, f.dx, k); y = lerp(f.by, f.dy, k); }
      f.e.style.transform = `translate3d(${x.toFixed(2)}px,${y.toFixed(2)}px,0)`;
    }
    const GO = .2 * (1 - smooth(.5, .7, p)), GI = .2 * smooth(.3, .5, p);
    for (const f of t.out) { const a = smooth(.04 + .06 * f.o, .14 + .06 * f.o, p); f.e.style.opacity = (1 - a + GO * a).toFixed(3); }
    for (const g of t.gOut) g.style.opacity = (Math.min(smooth(0, .06, p), 1) * GO).toFixed(3);
    for (const f of t.in) { const a = smooth(.8 + .08 * f.o, .9 + .08 * f.o, p); f.e.style.opacity = (GI + (1 - GI) * a).toFixed(3); }
    for (const g of t.gIn) g.style.opacity = (GI * (1 - smooth(.9, 1, p))).toFixed(3);
  }
  return {
    update(t) {
      if (!onScreen(box)) return;
      const w = box.offsetWidth; if (!w) return;
      if (dirty || w !== W) { W = w; dirty = false; build(); }
      if (t - touched > 4) {                                  // left alone, it plays: hold, cross, hold, cross back
        const c = 8, ph = (t % c) / c;
        P = ph < .15 ? 0 : ph < .5 ? E.inOutSine(inv(.15, .5, ph)) : ph < .65 ? 1 : 1 - E.inOutSine(inv(.65, 1, ph));
        if (reduce) P = ph < .5 ? 0 : 1;
        scrub.value = Math.round(P * 1000);
      }
      scrub.style.setProperty('--f', (P * 100).toFixed(1) + '%');
      pct.textContent = Math.round(P * 100) + '%';
      if (Math.abs(P - lastP) < 1e-4) return;
      lastP = P;
      const flying = P > 0 && P < 1 && !reduce;
      heads[0].style.opacity = flying ? 0 : P < .5 ? 1 : 0;
      heads[1].style.opacity = flying ? 0 : P >= .5 ? 1 : 0;
      layer.style.display = flying ? 'block' : 'none';
      if (flying) show(T, P);
    }
  };
})();

/* ------------------------------------------------------------------ colour: contrast measured here */
function lum([r, g, b]) { const f = c => c <= .04045 ? c / 12.92 : ((c + .055) / 1.055) ** 2.4; return .2126 * f(r) + .7152 * f(g) + .0722 * f(b); }
function parseCol(s) {
  s = s.trim();
  if (s[0] === '#') { const h = s.length === 4 ? s.slice(1).split('').map(c => c + c).join('') : s.slice(1); return [...hex3('#' + h), 1]; }
  const m = s.match(/rgba?\(([^)]+)\)/); const a = m[1].split(',').map(Number); return [a[0] / 255, a[1] / 255, a[2] / 255, a[3] ?? 1];
}
function ratio(fg, bg) {
  const b = parseCol(bg), f = parseCol(fg), a = f[3];
  const mix = [0, 1, 2].map(i => f[i] * a + b[i] * (1 - a));
  const L1 = lum(mix), L2 = lum(b); return (Math.max(L1, L2) + .05) / (Math.min(L1, L2) + .05);
}
const grade = (r, min) => min === 0 ? 'Rules only' : min === 3 ? (r >= 3 ? 'Large · marks' : 'Too low') : r >= 7 ? 'AAA' : r >= 4.5 ? 'AA' : r >= 3 ? 'AA large' : 'Fails';
$$('#swatches .sw').forEach(sw => {
  const c = sw.dataset.hex, host = $('.cr', sw);
  host.innerHTML = sw.dataset.vs.split(',').map(o => `<span><i style="--s:${o}"></i>${ratio(o, c).toFixed(1)} : 1</span>`).join('');
});
$$('#pairs li').forEach(li => {
  const r = ratio(li.dataset.f, li.dataset.b), min = +li.dataset.min, g = grade(r, min);
  $('.rt', li).innerHTML = `<b>${r.toFixed(2)}</b><span class="mono${min === 0 || g === 'Fails' ? ' no' : ''}">${g}</span>`;
});

/* ------------------------------------------------------------------ grid: measured in this window */
const GRID = (() => {
  const schem = $('#schem'), tile = $('#schemTile');
  if (!schem) return { update() {} };
  let lastW = -1;
  function update() {
    const W = document.documentElement.clientWidth || VP.w;
    const sw = schem.clientWidth;
    if (W === lastW && sw) return; lastW = W;
    const mv = getComputedStyle(document.documentElement).getPropertyValue('--margin').trim();
    const margin = mv.endsWith('vw') ? parseFloat(mv) * W / 100 : parseFloat(mv);
    $('#mW').innerHTML = `${W}<i>px</i>`; $('#mC').innerHTML = `${(W / 3).toFixed(0)}<i>px</i>`;
    $('#mR').innerHTML = `${(W * 4 / 9).toFixed(0)}<i>px</i>`; $('#mM').innerHTML = `${margin.toFixed(0)}<i>px</i>`;
    const k = sw / W, sh = Math.round(sw * 4 / 9);
    schem.style.height = sh + 'px';
    schem.style.setProperty('--mgw', Math.max(2, margin * k) + 'px');
    tile.style.left = Math.max(2, margin * k) + 'px'; tile.style.top = '0'; tile.style.height = sh + 'px'; tile.style.width = (sw / 3 - margin * k) + 'px'; tile.style.aspectRatio = 'auto';
    const pad = parseFloat(getComputedStyle($('.cell')).paddingLeft);
    const pv = $('#padVal'); if (pv) pv.textContent = `clamp(28, 3.3vw, 64) · ${pad.toFixed(0)} px here`;
  }
  const tg = $('#gridToggle'), ov = $('#gridOverlay');
  tg.addEventListener('click', () => { const on = tg.getAttribute('aria-pressed') !== 'true'; tg.setAttribute('aria-pressed', on); ov.classList.toggle('on', on); });
  return { update };
})();

/* ------------------------------------------------------------------ the sunset in Kyoto tonight (NOAA's approximation) */
(function kyotoSunset() {
  const el = $('#kyotoSunset'); if (!el) return;
  const now = new Date(), lat = 35.0116 * Math.PI / 180, lon = 135.7681;
  const jst = new Date(now.getTime() + 9 * 3600e3);
  const y0 = Date.UTC(jst.getUTCFullYear(), 0, 1), doy = Math.floor((Date.UTC(jst.getUTCFullYear(), jst.getUTCMonth(), jst.getUTCDate()) - y0) / 864e5) + 1;
  const g = 2 * Math.PI / 365 * (doy - 1 + (18 - 9 - 12) / 24);
  const eq = 229.18 * (.000075 + .001868 * Math.cos(g) - .032077 * Math.sin(g) - .014615 * Math.cos(2 * g) - .040849 * Math.sin(2 * g));
  const dec = .006918 - .399912 * Math.cos(g) + .070257 * Math.sin(g) - .006758 * Math.cos(2 * g) + .000907 * Math.sin(2 * g) - .002697 * Math.cos(3 * g) + .00148 * Math.sin(3 * g);
  const ha = Math.acos(Math.cos(90.833 * Math.PI / 180) / (Math.cos(lat) * Math.cos(dec)) - Math.tan(lat) * Math.tan(dec)) * 180 / Math.PI;
  const m = 720 - 4 * (lon - ha) - eq + 9 * 60;              // minutes after local midnight, JST
  el.textContent = `${String(Math.floor(m / 60)).padStart(2, '0')}:${String(Math.floor(m % 60)).padStart(2, '0')}`;
})();

/* ------------------------------------------------------------------ where we are, in the nav */
const WHERE = (() => {
  const secs = $$('[data-ch]'), where = $('#where'), links = $$('#header nav a');
  let cur = null;
  return {
    update() {
      let s = secs[0];
      for (const e of secs) if (e.getBoundingClientRect().top <= VP.h * .4) s = e;
      if (s === cur) return; cur = s;
      where.innerHTML = `<b>${s.dataset.ch}</b><span>${s.dataset.name}</span>`;
      links.forEach(a => a.setAttribute('aria-current', a.getAttribute('href') === '#' + s.id ? 'true' : 'false'));
    }
  };
})();

/* line-mask replay */
$('#revealReplay')?.addEventListener('click', () => {
  const els = $$('#revealDemo .rv');
  els.forEach(e => { e.classList.remove('in'); e.style.transitionDelay = '0s'; });
  void $('#revealDemo').offsetWidth;
  els.forEach((e, i) => { e.style.transitionDelay = (i * .09) + 's'; e.classList.add('in'); });
});

/* ------------------------------------------------------------------ loop */
let t0 = performance.now(), last = t0, lastTick = t0;
function frame(now, force) {
  const dt = Math.min(.05, Math.max(0, (now - last) / 1000)); last = now; lastTick = now;
  const t = (now - t0) / 1000;
  readViewport();
  checkReveals(); checkStamps();
  GLASS.update(t); WHERE.update(); GRID.update();
  updateChart(t, dt); pricingTick(dt); updateEases(t); HAND.update(t);
  PRINT.frame(t, dt, force);
}
function loop(now) { frame(now); requestAnimationFrame(loop); }
frame(performance.now(), true);                               // the first frame is painted before any rAF, so a background tab is never blank
requestAnimationFrame(loop);
setInterval(() => { if (performance.now() - lastTick > 400) frame(performance.now()); }, 500);
document.addEventListener('visibilitychange', () => { last = performance.now(); });
document.fonts && document.fonts.ready.then(() => frame(performance.now(), true));
if (document.readyState === 'complete') revealIntro(); else addEventListener('load', revealIntro);
window.__guide = { PRINT, frame: () => frame(performance.now(), true), PRICE, DUSK, CH };
})();
