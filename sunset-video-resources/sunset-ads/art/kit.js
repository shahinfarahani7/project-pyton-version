/* Sunseto ad kit: the mark as vector, the lockup, the keyed seal, and the site's woodblock sunset print
   (sunset-assets/src/wave.js) re-rendered at print resolution. Artboards import this and call ready()
   when every font, image and canvas is in place; tools/render.mjs waits for window.__ready. */

export const Q = new URLSearchParams(location.search);
if (Q.has('guides')) document.documentElement.classList.add('guides');
export const DPR = window.devicePixelRatio || 1;

/* ------------------------------------------------------------------ the mark */
let MARK = null;
export async function loadMark() {
  if (!MARK) MARK = await (await fetch('../assets/img/mark.json')).json();
  return MARK;
}
const pathOf = pts => 'M' + pts.map(([x, y]) => `${x} ${y}`).join('L') + 'Z';
let gid = 0;
/* sun: a vertical bokashi (top→bottom colours) or flat; sea: one colour for the three waves.
   The viewBox is the drawn extent (2.101..41.899 × 5..31.52), so the SVG box is the ink box. */
export function markSVG({ sunTop = 'var(--sun-top)', sunBot = 'var(--sun-bot)', sea = 'var(--sea-ink)', steps = 0, cls = '' } = {}) {
  const id = 'sg' + (gid++);
  let fill;
  let defs = '';
  if (sunTop === sunBot) fill = sunTop;
  else if (steps > 1) {
    // stepped bokashi: flat bands, for screen and letterpress
    const bands = [];
    for (let i = 0; i < steps; i++) bands.push(`<stop offset="${i / steps}" stop-color="${mixHex(sunTop, sunBot, i / (steps - 1))}"/><stop offset="${(i + 1) / steps}" stop-color="${mixHex(sunTop, sunBot, i / (steps - 1))}"/>`);
    defs = `<linearGradient id="${id}" x1="0" y1="5" x2="0" y2="18.7" gradientUnits="userSpaceOnUse">${bands.join('')}</linearGradient>`;
    fill = `url(#${id})`;
  } else {
    defs = `<linearGradient id="${id}" x1="0" y1="5" x2="0" y2="18.7" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="${sunTop}"/><stop offset="1" stop-color="${sunBot}"/></linearGradient>`;
    fill = `url(#${id})`;
  }
  return `<svg class="mk ${cls}" viewBox="2.101 5 39.798 26.52" preserveAspectRatio="xMidYMid meet" xmlns="http://www.w3.org/2000/svg"><defs>${defs}</defs>` +
    `<path fill="${fill}" d="${pathOf(MARK.sun)}"/>` + MARK.waves.map(w => `<path fill="${sea}" d="${pathOf(w)}"/>`).join('') + `</svg>`;
}
export function mixHex(a, b, t) {
  const pa = hex(a), pb = hex(b);
  return '#' + pa.map((v, i) => Math.round(v + (pb[i] - v) * t).toString(16).padStart(2, '0')).join('');
}
export function hex(h) { h = h.replace('#', ''); return [0, 2, 4].map(i => parseInt(h.slice(i, i + 2), 16)); }

/* lockup: <span class="lockup" data-lockup="ink|cream" data-seal> → mark + wordmark (+ seal) */
export function buildLockups(root = document) {
  root.querySelectorAll('[data-lockup]').forEach(el => {
    const cream = el.dataset.lockup === 'cream';
    const o = { sea: el.dataset.sea || (cream ? 'var(--sea-cream)' : 'var(--sea-ink)') };
    if (el.dataset.sun) { const [a, b] = el.dataset.sun.split(','); o.sunTop = a; o.sunBot = b || a; }
    if (el.dataset.steps) o.steps = +el.dataset.steps;
    el.classList.add('lockup');
    el.innerHTML = markSVG(o) + `<span class="wm">sunseto</span>` + ('seal' in el.dataset ? `<span class="hk"><img src="../assets/img/hanko_vermilion.png" alt=""></span>` : '');
    if (cream) el.style.setProperty('--word', el.dataset.word || '#fff3e4');
    else if (el.dataset.word) el.style.setProperty('--word', el.dataset.word);
  });
}
export function buildMarks(root = document) {
  root.querySelectorAll('[data-mark]').forEach(el => {
    const o = {};
    if (el.dataset.sun) { const [a, b] = el.dataset.sun.split(','); o.sunTop = a; o.sunBot = b || a; }
    if (el.dataset.sea) o.sea = el.dataset.sea;
    if (el.dataset.steps) o.steps = +el.dataset.steps;
    el.innerHTML = markSVG(o);
  });
}

/* ------------------------------------------------------------------ the sunset print
   wave.js's bokashi sky, low sun, kasumi bands and stroked sea, with the print-time changes:
   no glitter path and no sparks (the owner's no-glint rule), clouds placed by hand instead of drifting,
   the sky ramp scaled to each format (uSkyK), and a grain whose cell is a physical size. */
const FRAG = `
precision highp float;
uniform vec2 uRes, uTile;
uniform float uHz, uSunR, uSunX, uSunY, uSkyK, uSeaK, uGlow, uStrokes, uStrokeAmt, uDusk, uMoon, uGrain, uGrainCell, uHzLine, uClAmt, uSunDeep;
uniform vec3 uC0, uC1, uC2;
uniform vec4 uCl[4];
uniform vec3 uMoonP;
float hash12(vec2 p){ vec3 p3 = fract(vec3(p.xyx)*.1031); p3 += dot(p3, p3.yzx+33.33); return fract((p3.x+p3.y)*p3.z); }
float vnoise(vec2 p){ vec2 i=floor(p), f=fract(p); vec2 u=f*f*(3.-2.*f);
  return mix(mix(hash12(i),hash12(i+vec2(1.,0.)),u.x), mix(hash12(i+vec2(0.,1.)),hash12(i+vec2(1.,1.)),u.x), u.y); }
float band(vec2 p, vec2 c, float halfLen, float th){
  vec2 q = p - c; q.x = max(abs(q.x) - halfLen, 0.0);
  return length(q) - th * (1.0 + 0.12 * sin(p.x * 9.0 + c.y * 40.0));
}
void main(){
  vec2 px = gl_FragCoord.xy + uTile;
  float S = max(uRes.x, uRes.y);
  vec2 p = (px - 0.5*uRes)/S*2.0;
  float fw = 2.0 / S * 1.2;
  float h = p.y - uHz;
  float hk = h * uSkyK;
  vec3 gold = vec3(1.0, .82, .45), orange = vec3(.98, .55, .24), coral = uC2, rose = uC1, indigo = uC0;
  vec3 col = mix(gold, orange, smoothstep(0.0, 0.16, hk));
  col = mix(col, coral, smoothstep(0.1, 0.38, hk));
  col = mix(col, rose, smoothstep(0.32, 0.72, hk));
  col = mix(col, indigo, smoothstep(0.66, 1.45, hk));
  vec2 sc = vec2(uSunX, uSunY > -9.0 ? uSunY : uHz + uSunR * 0.35);
  float d = length(p - sc);
  col += vec3(1.0, .6, .3) * exp(-max(d - uSunR, 0.0) * 4.0 * uSkyK) * uGlow * step(0.0, h);
  float disc = (1.0 - smoothstep(uSunR - fw, uSunR + fw, d)) * smoothstep(-fw, fw, h);
  vec3 sunCol = mix(vec3(1.0, .6, .28), vec3(1.0, .95, .74), smoothstep(-0.2, 1.0, (p.y - sc.y) / uSunR));
  sunCol = mix(sunCol, mix(vec3(.86, .24, .15), vec3(.98, .47, .22), smoothstep(-1.0, 1.0, (p.y - sc.y) / uSunR)), uSunDeep);
  col = mix(col, sunCol, disc);
  for (int i = 0; i < 4; i++) {
    vec4 c = uCl[i];
    if (c.w <= 0.0) continue;
    float sd = band(p, c.xy, c.z, c.w);
    float a = (1.0 - smoothstep(-fw, fw, sd)) * uClAmt;
    float lit = smoothstep(0.0, -c.w * 1.6, p.y - c.y) * exp(-abs(p.x - uSunX) * 1.4);
    vec3 cc = mix(mix(col, vec3(1.0, .8, .78), 0.28), vec3(1.0, .76, .46), lit * 0.7);
    col = mix(col, cc, a * (0.7 - float(i) * 0.08));
  }
  if (h < 0.0) {
    float dn = -h;
    vec3 sea = mix(mix(coral, rose, 0.5) * 0.85, mix(rose, indigo, 0.75) * 0.8, smoothstep(0.0, 0.5, dn * uSeaK));
    float rowc = pow(dn * uSeaK, 0.62) * uStrokes;
    float fr = fract(rowc);
    float stroke = smoothstep(0.5, 0.0, abs(fr - 0.5) * 2.0 - 0.35);
    sea = mix(sea, sea * 1.18 + 0.02, stroke * uStrokeAmt);
    col = mix(col, sea, smoothstep(0.0, fw, -h));
  }
  col += vec3(1.0, .8, .55) * (1.0 - smoothstep(0.0, fw * 1.5 + uHzLine * 0.0, abs(h))) * 0.25 * (1.0 - uDusk);
  if (uDusk > 0.0) {
    float lum = dot(col, vec3(0.299, 0.587, 0.114));
    vec3 night = mix(uC0 * 0.55, vec3(0.12, 0.1, 0.24), 0.35) + lum * vec3(0.3, 0.27, 0.44);
    col = mix(col, night, uDusk);
  }
  if (uMoon > 0.0) {
    vec2 mc = uMoonP.xy; float r = uMoonP.z;
    float md = length(p - mc) - r, mo = length(p - mc - vec2(0.43, 0.24) * r) - r * 0.914;
    float mk = (1.0 - smoothstep(-fw, fw, md)) * smoothstep(-fw, fw, mo) * step(0.0, h);
    col = mix(col, vec3(1.0, 0.93, 0.8), mk * uMoon);
  }
  // paper: a fine tooth at a fixed physical cell, plus a slow mottle, so a flat field reads as a printed sheet
  vec2 gp = floor(px / uGrainCell);
  col += (hash12(gp) - 0.5) * uGrain + (vnoise(px / (uGrainCell * 40.0)) - 0.5) * uGrain * 0.6;
  gl_FragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}`;
const VERT = 'attribute vec2 a; void main(){ gl_Position = vec4(a, 0.0, 1.0); }';
let GLX = null;
function gl() {
  if (GLX) return GLX;
  const c = document.createElement('canvas');
  const g = c.getContext('webgl', { preserveDrawingBuffer: true, antialias: false, premultipliedAlpha: false });
  const sh = (t, s) => { const o = g.createShader(t); g.shaderSource(o, s); g.compileShader(o); if (!g.getShaderParameter(o, g.COMPILE_STATUS)) throw new Error(g.getShaderInfoLog(o)); return o; };
  const pr = g.createProgram(); g.attachShader(pr, sh(g.VERTEX_SHADER, VERT)); g.attachShader(pr, sh(g.FRAGMENT_SHADER, FRAG)); g.linkProgram(pr);
  if (!g.getProgramParameter(pr, g.LINK_STATUS)) throw new Error(g.getProgramInfoLog(pr));
  g.useProgram(pr);
  const b = g.createBuffer(); g.bindBuffer(g.ARRAY_BUFFER, b); g.bufferData(g.ARRAY_BUFFER, new Float32Array([-1, -1, 3, -1, -1, 3]), g.STATIC_DRAW);
  const loc = g.getAttribLocation(pr, 'a'); g.enableVertexAttribArray(loc); g.vertexAttribPointer(loc, 2, g.FLOAT, false, 0, 0);
  GLX = { c, g, pr, U: n => g.getUniformLocation(pr, n) };
  return GLX;
}
const rgb = h => hex(h).map(v => v / 255);
export const PRINT = { c0: '#2c1d55', c1: '#b0406c', c2: '#ea5f4a' };
/* renders into a 2D canvas at its current pixel size, in tiles read back with readPixels
   (headless Chrome can hand back stale drawImage copies of a WebGL canvas) */
export function renderSunset(canvas, o = {}) {
  const { c, g, U } = gl();
  const W = canvas.width, H = canvas.height, T = 2048;
  c.width = T; c.height = T; g.viewport(0, 0, T, T);
  const P = Object.assign({ hz: -0.3, sunR: 0.3, sunX: 0, sunY: -10, skyK: 1, seaK: 1, glow: 0.2, strokes: 70, strokeAmt: 0.35, dusk: 0, moon: 0, moonP: [0.3, 0.6, 0.07], grain: 0.03, grainCell: 1, clAmt: 1, clouds: [], sunDeep: 0 }, PRINT, o);
  g.uniform2f(U('uRes'), W, H);
  for (const [k, v] of Object.entries({ uHz: P.hz, uSunR: P.sunR, uSunX: P.sunX, uSunY: P.sunY, uSkyK: P.skyK, uSeaK: P.seaK, uGlow: P.glow, uStrokes: P.strokes, uStrokeAmt: P.strokeAmt, uDusk: P.dusk, uMoon: P.moon, uGrain: P.grain, uGrainCell: P.grainCell, uHzLine: 0, uClAmt: P.clAmt, uSunDeep: P.sunDeep })) g.uniform1f(U(k), v);
  g.uniform3fv(U('uC0'), rgb(P.c0)); g.uniform3fv(U('uC1'), rgb(P.c1)); g.uniform3fv(U('uC2'), rgb(P.c2));
  g.uniform3fv(U('uMoonP'), P.moonP);
  const cl = new Float32Array(16); P.clouds.slice(0, 4).forEach((q, i) => cl.set(q, i * 4));
  g.uniform4fv(U('uCl[0]'), cl);
  const ctx = canvas.getContext('2d');
  const buf = new Uint8Array(T * T * 4);
  for (let ty = 0; ty < H; ty += T) for (let tx = 0; tx < W; tx += T) {
    const tw = Math.min(T, W - tx), th = Math.min(T, H - ty);
    // tile origin in bottom-up pixel coordinates
    g.uniform2f(U('uTile'), tx, H - ty - th);
    g.drawArrays(g.TRIANGLES, 0, 3);
    g.readPixels(0, 0, tw, th, g.RGBA, g.UNSIGNED_BYTE, buf);
    const img = ctx.createImageData(tw, th), row = tw * 4;
    for (let y = 0; y < th; y++) img.data.set(buf.subarray((th - 1 - y) * row, (th - y) * row), y * row);
    ctx.putImageData(img, tx, ty);
  }
}
/* size a canvas to its CSS box at device resolution */
export function fitCanvas(cv, scale = 1) {
  const r = cv.getBoundingClientRect();
  cv.width = Math.round(r.width * DPR * scale); cv.height = Math.round(r.height * DPR * scale);
  return cv;
}

/* ------------------------------------------------------------------ ready */
export async function ready(extra = []) {
  await document.fonts.ready;
  await Promise.all([...document.images].map(i => i.decode().catch(() => {})));
  await Promise.all(extra);
  await new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r)));
  window.__ready = true;
}
