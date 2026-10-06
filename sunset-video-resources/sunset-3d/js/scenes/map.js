// Coverage — Japan at night as a thin urushi relief on the page's own night. The land is a lifted plum-ink fill with a
// gold hairline coast and a faint population layer along coasts, plains and roads (a night-lights map); Sunset cities
// glow brighter, their clusters ∝ √homes, and the Tōkaidō corridor reads as one ribbon. Arcs between neighbouring
// cities carry soft pulses of shared evening energy. A faint 5° graticule lies on the sea; the Ryukyu chain sits in a
// hairline inset. The camera is fitted into the space the DOM leaves, drifts slowly, follows the pointer a little, and
// eases toward the city the postal-code form resolves (STATE.city).
import { THREE, canvasTexture, makeCanvas, rng, clamp, damp, lerp, STATE, REDUCED } from '../core.js';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';
import { LineSegments2 } from 'three/addons/lines/LineSegments2.js';
import { LineSegmentsGeometry } from 'three/addons/lines/LineSegmentsGeometry.js';
import { LineMaterial } from 'three/addons/lines/LineMaterial.js';

const U = 1 / 100, CX = 416, CY = 420;             // data px -> world units; map centre
const LAND_H = .02, BEV = .0032;
// invented homes on the plan (the ten regional hubs match the postal-code answers in main.js)
const HOMES = { tokyo: 640, osaka: 571, yokohama: 512, nagoya: 388, fukuoka: 298, kyoto: 244, sendai: 212, hiroshima: 196, sapporo: 184, matsuyama: 121,
  kobe: 118, shizuoka: 96, okayama: 74, kumamoto: 71, niigata: 64, kanazawa: 58, nagasaki: 44, kagoshima: 52, takamatsu: 41, kochi: 38, toyama: 36,
  nagano: 42, fukushima: 33, morioka: 28, akita: 24, aomori: 26, hakodate: 31, asahikawa: 22, kushiro: 18, matsue: 27, miyazaki: 34, naha: 52 };
const LONLAT = { sapporo: [141.35, 43.06], asahikawa: [142.37, 43.77], kushiro: [144.38, 42.98], hakodate: [140.73, 41.77], aomori: [140.74, 40.82],
  morioka: [141.15, 39.70], akita: [140.10, 39.72], sendai: [140.87, 38.27], niigata: [139.02, 37.92], fukushima: [140.47, 37.76], tokyo: [139.69, 35.69],
  yokohama: [139.64, 35.44], nagano: [138.19, 36.65], kanazawa: [136.63, 36.56], toyama: [137.21, 36.70], shizuoka: [138.38, 34.98], nagoya: [136.91, 35.18],
  kyoto: [135.77, 35.01], osaka: [135.50, 34.69], kobe: [135.19, 34.69], okayama: [133.92, 34.66], hiroshima: [132.46, 34.39], matsue: [133.05, 35.47],
  takamatsu: [134.05, 34.34], matsuyama: [132.77, 33.84], kochi: [133.53, 33.56], fukuoka: [130.40, 33.59], nagasaki: [129.87, 32.75], kumamoto: [130.71, 32.80],
  miyazaki: [131.42, 31.91], kagoshima: [130.56, 31.60] };
// the Ryukyu inset (lon, lat): Okinawa Hontō, Miyako-jima, Ishigaki and Iriomote
const RYUKYU = [
  [[128.26, 26.87], [128.33, 26.80], [128.29, 26.72], [128.24, 26.66], [128.17, 26.62], [128.10, 26.57], [128.05, 26.53], [127.99, 26.49], [127.95, 26.44],
   [127.97, 26.40], [128.00, 26.34], [127.96, 26.30], [127.88, 26.28], [127.84, 26.23], [127.86, 26.18], [127.80, 26.14], [127.72, 26.09], [127.66, 26.08],
   [127.65, 26.12], [127.67, 26.18], [127.68, 26.22], [127.72, 26.26], [127.75, 26.31], [127.73, 26.37], [127.71, 26.43], [127.76, 26.47], [127.83, 26.52],
   [127.90, 26.56], [127.95, 26.59], [127.92, 26.62], [127.86, 26.66], [127.87, 26.71], [127.94, 26.70], [128.00, 26.69], [128.07, 26.71], [128.13, 26.75],
   [128.18, 26.80], [128.22, 26.85]],
  [[125.28, 24.88], [125.35, 24.85], [125.42, 24.78], [125.47, 24.73], [125.43, 24.71], [125.33, 24.72], [125.26, 24.74], [125.24, 24.80], [125.26, 24.85]],
  [[124.29, 24.60], [124.33, 24.55], [124.30, 24.48], [124.28, 24.43], [124.23, 24.36], [124.16, 24.33], [124.10, 24.35], [124.12, 24.42], [124.20, 24.47], [124.24, 24.55]],
  [[123.75, 24.43], [123.88, 24.42], [123.95, 24.36], [123.93, 24.27], [123.80, 24.24], [123.70, 24.28], [123.67, 24.36]],
];
const NAHA = [127.68, 26.21];
const CORRIDOR = ['tokyo', 'yokohama', 'shizuoka', 'nagoya', 'kyoto', 'osaka', 'kobe'];
// label directions (screen space) toward open sea
const LABEL_DIR = { sapporo: [-1, -.55], tokyo: [1, .45], osaka: [-.15, 1], fukuoka: [-1, -.5] };
const LABEL_DIR_N = { sapporo: [-1, -.35], tokyo: [1, .4], osaka: [-.05, 1], fukuoka: [-1, -.1] };
const LABEL_GAP = { osaka: 62 };

/* ---------------------------------------------------------------- helpers */
const mercY = lat => Math.log(Math.tan(Math.PI / 4 + lat * Math.PI / 360));
function fitAffine(data) {           // least squares x = a*lon + b*m + c, y = d*lon + e*m + f
  const rows = Object.entries(LONLAT).filter(([k]) => data.cities[k]).map(([k, [lo, la]]) => [lo, mercY(la), ...data.cities[k]]);
  const solve = (col) => {
    const A = [[0, 0, 0], [0, 0, 0], [0, 0, 0]], b = [0, 0, 0];
    for (const r of rows) { const v = [r[0], r[1], 1]; for (let i = 0; i < 3; i++) { b[i] += v[i] * r[col]; for (let j = 0; j < 3; j++) A[i][j] += v[i] * v[j]; } }
    for (let i = 0; i < 3; i++) { let p = i; for (let k = i + 1; k < 3; k++) if (Math.abs(A[k][i]) > Math.abs(A[p][i])) p = k; [A[i], A[p]] = [A[p], A[i]]; [b[i], b[p]] = [b[p], b[i]]; for (let k = i + 1; k < 3; k++) { const f = A[k][i] / A[i][i]; for (let j = i; j < 3; j++) A[k][j] -= f * A[i][j]; b[k] -= f * b[i]; } }
    const x = [0, 0, 0]; for (let i = 2; i >= 0; i--) { let s = b[i]; for (let j = i + 1; j < 3; j++) s -= A[i][j] * x[j]; x[i] = s / A[i][i]; }
    return x;
  };
  return { X: solve(2), Y: solve(3) };
}
function smoothPoly(p) {             // relax the raster trace's half-pixel stairs, once
  const n = p.length; if (n < 8) return p;
  return p.map((_, i) => { const a = p[(i - 1 + n) % n], c = p[(i + 1) % n], b = p[i]; return [(a[0] + 4 * b[0] + c[0]) / 6, (a[1] + 4 * b[1] + c[1]) / 6]; });
}
function hash2(x, y) { let h = (x * 374761393 + y * 668265263) | 0; h = (h ^ (h >>> 13)) * 1274126177 | 0; return ((h ^ (h >>> 16)) >>> 0) / 4294967296; }
function vnoise(x, y) {
  const xi = Math.floor(x), yi = Math.floor(y), xf = x - xi, yf = y - yi, u = xf * xf * (3 - 2 * xf), v = yf * yf * (3 - 2 * yf);
  const a = hash2(xi, yi), b = hash2(xi + 1, yi), c = hash2(xi, yi + 1), d = hash2(xi + 1, yi + 1);
  return a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v;
}
/** Soft relief (inland domes + broad ranges) as a normal map, and a lacquer albedo. */
function reliefMaps(polys, W, H, K = 2) {
  const w = Math.round(W * K), h = Math.round(H * K);
  const mask = makeCanvas(w, h), mg = mask.getContext('2d');
  mg.fillStyle = '#000'; mg.fillRect(0, 0, w, h); mg.fillStyle = '#fff';
  for (const p of polys) { mg.beginPath(); p.forEach(([x, y], i) => i ? mg.lineTo(x * K, y * K) : mg.moveTo(x * K, y * K)); mg.closePath(); mg.fill(); }
  const blurred = (r) => { const c = makeCanvas(w, h), g = c.getContext('2d'); g.fillStyle = '#000'; g.fillRect(0, 0, w, h); g.filter = `blur(${r}px)`; g.drawImage(mask, 0, 0); return g.getImageData(0, 0, w, h).data; };
  const m0 = mg.getImageData(0, 0, w, h).data, b3 = blurred(14 * K), b4 = blurred(28 * K);
  const hf = new Float32Array(w * h), land = new Uint8Array(w * h);
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    const i = y * w + x; if (m0[i * 4] < 128) continue; land[i] = 1;
    const n = .6 * vnoise(x / K * .018, y / K * .018) + .4 * vnoise(x / K * .04 + 7, y / K * .04 - 3);
    hf[i] = (.45 * b3[i * 4] / 255 + .6 * b4[i * 4] / 255) * (.5 + .9 * n);
  }
  const nc = makeCanvas(w, h), ng = nc.getContext('2d'), nd = ng.createImageData(w, h);
  const ac = makeCanvas(w, h), ag = ac.getContext('2d'), ad = ag.createImageData(w, h);
  const S = 2.6;
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    const i = y * w + x;
    const hl = hf[y * w + Math.max(0, x - 1)], hr = hf[y * w + Math.min(w - 1, x + 1)], hu = hf[Math.max(0, y - 1) * w + x], hd = hf[Math.min(h - 1, y + 1) * w + x];
    let nx = -(hr - hl) * S * K, ny = -(hu - hd) * S * K, nz = 1; const l = Math.hypot(nx, ny, nz); nx /= l; ny /= l; nz /= l;
    nd.data[i * 4] = (nx * .5 + .5) * 255; nd.data[i * 4 + 1] = (ny * .5 + .5) * 255; nd.data[i * 4 + 2] = (nz * .5 + .5) * 255; nd.data[i * 4 + 3] = 255;
    const t = clamp(hf[i] * 1.4);
    ad.data[i * 4] = 34 + t * 12; ad.data[i * 4 + 1] = 26 + t * 9; ad.data[i * 4 + 2] = 27 + t * 9; ad.data[i * 4 + 3] = 255;
  }
  ng.putImageData(nd, 0, 0); ag.putImageData(ad, 0, 0);
  // hillshade (light from the north-west), baked as an emissive modulation of 0.92–1.0
  const hc = makeCanvas(w, h), hg = hc.getContext('2d'), hd = hg.createImageData(w, h);
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    const i = y * w + x, gx = (hf[y * w + Math.min(w - 1, x + 1)] - hf[y * w + Math.max(0, x - 1)]) * K * 40, gy = (hf[Math.min(h - 1, y + 1) * w + x] - hf[Math.max(0, y - 1) * w + x]) * K * 40;
    const sh = clamp(.5 + (-gx - gy) * .5), v = (.9 + .1 * sh) * 255;
    hd.data[i * 4] = hd.data[i * 4 + 1] = hd.data[i * 4 + 2] = v; hd.data[i * 4 + 3] = 255;
  }
  hg.putImageData(hd, 0, 0);
  return { normal: canvasTexture(nc, { srgb: false }), albedo: canvasTexture(ac), hill: canvasTexture(hc, { srgb: false }), hf, land, w, h, K };
}
function radialTex(size = 128, stops = [[0, 1], [.25, .45], [.6, .1], [1, 0]]) {
  const c = makeCanvas(size, size), g = c.getContext('2d');
  g.fillStyle = '#000'; g.fillRect(0, 0, size, size);
  const gr = g.createRadialGradient(size / 2, size / 2, 0, size / 2, size / 2, size / 2);
  for (const [o, v] of stops) gr.addColorStop(o, `rgb(${v * 255 | 0},${v * 255 | 0},${v * 255 | 0})`);
  g.fillStyle = gr; g.fillRect(0, 0, size, size);
  return canvasTexture(c, { srgb: false });
}
function gaussian(r) { let u = 0; while (u === 0) u = r(); const v = r(); return Math.sqrt(-2 * Math.log(u)) * Math.cos(2 * Math.PI * v); }

/* ---------------------------------------------------------------- the post chain's tone curve, inverted
   The sea is the page itself; the land must land on an exact colour after ACES (whose toe crushes darks), so solve
   the scene-linear value that the composite (exposure, ACES + hue-preserving blend) maps to a target sRGB colour. */
const EXPO = 1.05, HUE = .45;
function acesJS([r, g, b]) {
  const I = [[.59719, .35458, .04823], [.07600, .90834, .01566], [.02840, .13383, .83777]], O = [[1.60475, -.53108, -.07367], [-.10208, 1.10813, -.00605], [-.00327, -.07276, 1.07602]];
  const mul = (M, v) => M.map(row => row[0] * v[0] + row[1] * v[1] + row[2] * v[2]);
  const f = v => (v * (v + .0245786) - .000090537) / (v * (.983729 * v + .432951) + .238081);
  return mul(O, mul(I, [r / .6, g / .6, b / .6]).map(f)).map(x => clamp(x));
}
const luma = c => .2126 * c[0] + .7152 * c[1] + .0722 * c[2];
function toneJS(rgb) {
  const h = rgb.map(x => x * EXPO), a = acesJS(h), L = luma(h), tl = luma(acesJS([L, L, L])), hp = h.map(x => clamp(x * tl / Math.max(L, 1e-4)));
  return a.map((x, i) => x + (hp[i] - x) * HUE);
}
function sceneFor(hex) {       // scene-linear rgb that renders as `hex`
  const c = new THREE.Color(hex), t = [c.r, c.g, c.b];   // (linear, from the sRGB hex)
  let x = t.map(v => v * 2);
  for (let i = 0; i < 40; i++) { const y = toneJS(x); x = x.map((v, k) => v * clamp(t[k] / Math.max(y[k], 1e-6), .5, 2)); }
  return new THREE.Color(x[0], x[1], x[2]);
}

export async function create(ctx) {
  const { env, host, renderer } = ctx;
  const data = await fetch('assets/data/jpmap.json').then(r => r.json());
  const scene = new THREE.Scene();
  scene.environment = env.texture; scene.environmentIntensity = .1;
  const camera = new THREE.PerspectiveCamera(30, 1.6, .1, 80);
  const aff = fitAffine(data);
  const pxPerDegLat = Math.abs(aff.Y[1]) * Math.PI / 180 / Math.cos(35 * Math.PI / 180);
  const polys = data.outer.split('|').map(p => p.trim().split(/\s+/).map(q => q.split(',').map(Number))).filter(p => p.length >= 3).map(smoothPoly);
  const toW = ([x, y], yv = 0) => new THREE.Vector3((x - CX) * U, yv, (y - CY) * U);

  /* ---------- the Ryukyu inset: Hontō, Miyako and Yaeyama, offsets drawn in (a conventional inset), chain centred */
  const ryC = [127.9, 26.45], lonK = Math.cos(26 * Math.PI / 180) * pxPerDegLat;
  const toRy = ([lo, la]) => [(lo - ryC[0]) * lonK, -(la - ryC[1]) * pxPerDegLat];
  const PULL = .32;                                                         // groups pulled toward Okinawa
  const ryPolys = RYUKYU.map((p, gi) => {
    const pts = p.map(toRy); if (gi === 0) return pts;
    const cx = pts.reduce((s, q) => s + q[0], 0) / pts.length, cy = pts.reduce((s, q) => s + q[1], 0) / pts.length;
    return pts.map(([x, y]) => [x - cx * (1 - PULL), y - cy * (1 - PULL)]);
  });
  let bx0 = 1e9, bx1 = -1e9, by0 = 1e9, by1 = -1e9; for (const p of ryPolys) for (const [x, y] of p) { bx0 = Math.min(bx0, x); bx1 = Math.max(bx1, x); by0 = Math.min(by0, y); by1 = Math.max(by1, y); }
  const IC = [(bx0 + bx1) / 2, (by0 + by1) / 2];
  for (const p of ryPolys) for (const q of p) { q[0] -= IC[0]; q[1] -= IC[1]; }
  const INSET = { w: bx1 - bx0 + 16, h: by1 - by0 + 16 };
  const toWl = ([x, y], yv = 0) => new THREE.Vector3(x * U, yv, y * U);
  const nahaPx = (() => { const q = toRy(NAHA); return [q[0] - IC[0], q[1] - IC[1]]; })();

  /* ---------- light */
  const moon = new THREE.DirectionalLight(new THREE.Color(0xa99cc4), .35); moon.position.set(-3, 5, -2); scene.add(moon);
  scene.environmentRotation.set(0, 1.2, 0);

  /* ---------- land: a lifted plum-ink fill (#1C1622 after the tone curve), soft relief, a gold hairline coast */
  const rel = reliefMaps(polys, data.W, data.H);
  for (const t of [rel.normal, rel.albedo, rel.hill]) { t.wrapS = t.wrapT = THREE.ClampToEdgeWrapping; t.repeat.set(1 / U / data.W, 1 / U / data.H); t.offset.set(CX / data.W, 1 - CY / data.H); }
  const slab = (ps, x0 = CX, y0 = CY) => {
    const g = new THREE.ExtrudeGeometry(ps.map(p => new THREE.Shape(p.map(([x, y]) => new THREE.Vector2((x - x0) * U, -(y - y0) * U)))), { depth: LAND_H, bevelEnabled: true, bevelThickness: BEV, bevelSize: BEV * .8, bevelSegments: 2, curveSegments: 1 });
    g.rotateX(-Math.PI / 2); g.translate(0, BEV, 0); return g;
  };
  const TOP = LAND_H + BEV * 2;
  const fillCol = sceneFor(0x1b1521);
  const lacquer = new THREE.MeshStandardMaterial({ color: 0x3a3036, map: rel.albedo, normalMap: rel.normal, roughness: .62, emissive: fillCol.clone().multiplyScalar(1.06), emissiveMap: rel.hill, envMapIntensity: .7 });
  const lacquerPlain = new THREE.MeshStandardMaterial({ color: 0x3a3036, roughness: .62, emissive: fillCol, envMapIntensity: .7 });
  const edge = new THREE.MeshStandardMaterial({ color: 0x1a1412, roughness: .45, emissive: fillCol.clone().multiplyScalar(.6) });
  edge.onBeforeCompile = (sh) => {
    sh.vertexShader = sh.vertexShader.replace('#include <common>', '#include <common>\nvarying float vUp;').replace('#include <beginnormal_vertex>', '#include <beginnormal_vertex>\nvUp = normalize(mat3(modelMatrix) * objectNormal).y;');
    sh.fragmentShader = sh.fragmentShader.replace('#include <common>', '#include <common>\nvarying float vUp;')
      .replace('#include <opaque_fragment>', '  outgoingLight += vec3(.5, .33, .16) * smoothstep(.25, .75, vUp) * (1. - smoothstep(.9, .99, vUp)) * .45;\n#include <opaque_fragment>');
  };
  scene.add(new THREE.Mesh(slab(polys), [lacquer, edge]));
  const inset = new THREE.Group(); scene.add(inset);
  inset.add(new THREE.Mesh(slab(ryPolys, 0, 0), [lacquerPlain, edge]));

  /* ---------- the sea is the page's own night: only a faint 5° graticule is drawn on it */
  const inv = (() => { const [a, b] = aff.X, [d, e] = aff.Y, det = a * e - b * d; return new THREE.Matrix3().set(e / det, -b / det, 0, -d / det, a / det, 0, 0, 0, 1); })();
  const seaMat = new THREE.ShaderMaterial({
    transparent: true, depthWrite: false,
    uniforms: {
      uLine: { value: new THREE.Color(.5, .42, .38) }, uCenter: { value: new THREE.Vector2() }, uBottom: { value: .5 },
      uInv: { value: inv }, uOff: { value: new THREE.Vector2(aff.X[2], aff.Y[2]) }, uUC: { value: new THREE.Vector3(U, CX, CY) },
      uInset: { value: new THREE.Vector4() }, uInsetRot: { value: 0 },
    },
    vertexShader: `varying vec3 vW; varying vec4 vC; void main(){ vec4 w = modelMatrix * vec4(position,1.); vW = w.xyz; vC = projectionMatrix * viewMatrix * w; gl_Position = vC; }`,
    fragmentShader: /* glsl */`
      uniform vec3 uLine, uUC; uniform vec2 uCenter, uOff; uniform mat3 uInv; uniform vec4 uInset; uniform float uInsetRot, uBottom; varying vec3 vW; varying vec4 vC;
      float grat(float v, float step){ float f = v / step; float w = fwidth(f); return 1. - smoothstep(0., 1.2, abs(fract(f - .5) - .5) / max(w, 1e-5)); }
      void main(){
        vec2 n = vC.xy / vC.w;
        float fade = smoothstep(1., .7, abs(n.x)) * smoothstep(1., .75, n.y) * smoothstep(uBottom - .02, uBottom + .3, n.y);
        vec2 px = vW.xz / uUC.x + uUC.yz;
        vec3 ll = uInv * vec3(px - uOff, 0.);
        float lat = degrees(atan(sinh(ll.y))), lon = ll.x;
        vec2 w = vW.xz - uInset.xy, ca = vec2(cos(uInsetRot), sin(uInsetRot));
        vec2 q = abs(vec2(w.x * ca.x - w.y * ca.y, w.x * ca.y + w.y * ca.x)) - uInset.zw;
        float g = max(grat(lon, 5.), grat(lat, 5.)) * step(0., max(q.x, q.y)) * smoothstep(3.6, 1., length((vW.xz - uCenter) * vec2(.8, 1.)));
        gl_FragColor = vec4(uLine, g * .11 * fade);
      }`,
  });
  const sea = new THREE.Mesh(new THREE.PlaneGeometry(40, 40), seaMat); sea.rotation.x = -Math.PI / 2; sea.position.y = -.002; sea.renderOrder = -1; scene.add(sea);
  const iw = INSET.w * U / 2, ih = INSET.h * U / 2, fy = .002;
  const frameGeo = new LineSegmentsGeometry().setPositions([-iw, fy, -ih, iw, fy, -ih, iw, fy, -ih, iw, fy, ih, iw, fy, ih, -iw, fy, ih, -iw, fy, ih, -iw, fy, -ih]);
  const frameMat = new LineMaterial({ color: new THREE.Color(.62, .52, .4), linewidth: .8, transparent: true, opacity: .22, depthWrite: false });
  inset.add(new LineSegments2(frameGeo, frameMat));

  /* ---------- lights: a faint population layer along coasts, plains and roads; brighter clusters for Sunset cities */
  const names = [...Object.keys(data.cities), 'naha'];
  const NAHA_I = names.length - 1;
  const homes = names.map(k => HOMES[k] || 30);
  const pos = names.map(k => k === 'naha' ? new THREE.Vector3() : toW(data.cities[k], TOP));
  const nahaLocal = toWl(nahaPx, TOP);
  const landAt = ([x, y]) => { const i = Math.round(y * rel.K) * rel.w + Math.round(x * rel.K); return rel.land[i] === 1; };
  const inside = (p, x, y) => { let c = false; for (let i = 0, j = p.length - 1; i < p.length; j = i++) if (((p[i][1] > y) !== (p[j][1] > y)) && (x < (p[j][0] - p[i][0]) * (y - p[i][1]) / (p[j][1] - p[i][1]) + p[i][0])) c = !c; return c; };
  const onRyukyu = (x, y) => ryPolys.some(p => inside(p, x, y));
  const R = rng(77), A = { P: [], SZ: [], BR: [], CI: [] }, B = { P: [], SZ: [], BR: [], CI: [] };
  const push = (T, v, size, br, ci) => { T.P.push(v.x, v.y, v.z); T.SZ.push(size); T.BR.push(br); T.CI.push(ci); };
  // population: near cities and near coasts, never on the high interior
  const coast = (() => { const c = makeCanvas(rel.w, rel.h), g = c.getContext('2d'); g.filter = `blur(${7 * rel.K}px)`; const m = makeCanvas(rel.w, rel.h), mg = m.getContext('2d'), im = mg.createImageData(rel.w, rel.h); for (let i = 0; i < rel.land.length; i++) { const v = rel.land[i] * 255; im.data[i * 4] = im.data[i * 4 + 1] = im.data[i * 4 + 2] = v; im.data[i * 4 + 3] = 255; } mg.putImageData(im, 0, 0); g.drawImage(m, 0, 0); return g.getImageData(0, 0, rel.w, rel.h).data; })();
  const cityPx = names.slice(0, NAHA_I).map(k => data.cities[k]);
  for (let i = 0, tries = 0; i < 2200 && tries < 120000; tries++) {
    const x = R() * data.W, y = R() * data.H; if (!landAt([x, y])) continue;
    const ci = Math.round(y * rel.K) * rel.w + Math.round(x * rel.K), nearCoast = 1 - coast[ci * 4] / 255;
    let near = 0, best = 0; cityPx.forEach(([cx, cy], k) => { const d2 = (x - cx) ** 2 + (y - cy) ** 2, v = Math.exp(-d2 / (2 * 26 * 26)) * Math.sqrt(homes[k] / 640); if (v > near) { near = v; best = k; } });
    const alt = rel.hf[ci];
    if (alt > .55 && near < .35) continue;                    // the Alps and the Hokkaido interior stay dark
    if (R() > (.03 + nearCoast * .5 + near * .9) * (1 - clamp(alt * 1.1, 0, .85))) continue;
    const wgt = .5 + R() * .5;
    push(A, toW([x, y], TOP + .002), 2.2 + wgt * 2, (.05 + near * .08) * wgt, best); i++;
  }
  // roads: towns strung along the main lines, the Tōkaidō densest
  const ROADS = [[CORRIDOR, 3.4], [['tokyo', 'fukushima', 'sendai', 'morioka', 'aomori'], .8], [['kobe', 'okayama', 'hiroshima', 'fukuoka', 'kumamoto', 'kagoshima'], .9], [['niigata', 'toyama', 'kanazawa', 'kyoto'], .6], [['sapporo', 'asahikawa'], .6]];
  for (const [line, dens] of ROADS) for (let s = 0; s < line.length - 1; s++) {
    const a = data.cities[line[s]], b = data.cities[line[s + 1]], len = Math.hypot(b[0] - a[0], b[1] - a[1]), n = Math.round(len * dens);
    for (let i = 0, tries = 0; i < n && tries < n * 10; tries++) {
      const t = R(), x = lerp(a[0], b[0], t) + gaussian(R) * 1.8, y = lerp(a[1], b[1], t) + gaussian(R) * 1.8;
      if (!landAt([x, y])) continue;
      push(A, toW([x, y], TOP + .002), 1.2 + R() * 1.2, (dens > 2 ? .22 : .13) + R() * .2, names.indexOf(line[t < .5 ? s : s + 1])); i++;
    }
  }
  // Sunset cities: count ∝ homes, spread ∝ √homes, round dots of varied size
  names.forEach((k, ci) => {
    const h = homes[ci], n = Math.round(8 + h * .3), sigma = 1 + 5 * Math.sqrt(h / 640);
    const [cx, cy] = k === 'naha' ? nahaPx : data.cities[k];
    for (let i = 0, tries = 0; i < n && tries < n * 16; tries++) {
      const core = i < n * .3, s = core ? sigma * .45 : sigma;
      const x = cx + gaussian(R) * s, y = cy + gaussian(R) * s * .85;
      if (k === 'naha' ? !onRyukyu(x, y) : !landAt([x, y])) continue;
      const size = (core ? 2 + R() * 1.6 : 1.3 + R() * 1.4) * (R() < .06 ? 1.6 : 1), br = core ? .7 + R() * .3 : .3 + R() * .35;
      if (k === 'naha') push(B, toWl([x, y], TOP + .002), size, br, ci); else push(A, toW([x, y], TOP + .002), size, br, ci);
      i++;
    }
  });
  const pointsGeo = (T) => {
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.Float32BufferAttribute(T.P, 3)); g.setAttribute('aSize', new THREE.Float32BufferAttribute(T.SZ, 1));
    g.setAttribute('aBr', new THREE.Float32BufferAttribute(T.BR, 1)); g.setAttribute('aCity', new THREE.Float32BufferAttribute(T.CI, 1));
    return g;
  };
  const lightsMat = new THREE.ShaderMaterial({
    transparent: true, depthWrite: false, blending: THREE.AdditiveBlending,
    uniforms: { uPx: { value: 2 }, uTime: { value: 0 }, uFocus: { value: -1 }, uBoost: { value: 0 } },
    vertexShader: /* glsl */`
      attribute float aSize, aBr, aCity; uniform float uPx, uTime, uFocus, uBoost; varying float vB;
      void main(){
        float f = abs(aCity - uFocus) < .5 ? 1. : 0.;
        float tw = .92 + .08 * sin(uTime * (1.3 + fract(aCity * .37) * 2.) + position.x * 91. + position.z * 57.);
        vB = min(aBr * tw * (1. + f * uBoost), 1.2);
        gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.);
        gl_PointSize = max(aSize * uPx * (1. + f * uBoost * .3), 4.);
      }`,
    fragmentShader: /* glsl */`
      varying float vB;
      void main(){ vec2 d = gl_PointCoord - .5; float r2 = dot(d, d) * 4.; float a = exp(-r2 * 3.) * (1. - smoothstep(.75, 1., r2));
        gl_FragColor = vec4(vec3(1., .45, .13) * vB * a * 1.3, 1.); }`,
  });
  scene.add(new THREE.Points(pointsGeo(A), lightsMat));
  inset.add(new THREE.Points(pointsGeo(B), lightsMat));
  // the warm light each Sunset city throws on the lacquer, ∝ √homes
  const halo = radialTex(128, [[0, 1], [.15, .45], [.4, .12], [.75, .02], [1, 0]]);
  const poolMat = new THREE.MeshBasicMaterial({ color: 0xffffff, alphaMap: halo, transparent: true, blending: THREE.AdditiveBlending, depthWrite: false });
  const pools = new THREE.InstancedMesh(new THREE.PlaneGeometry(1, 1).rotateX(-Math.PI / 2), poolMat, NAHA_I);
  const m4 = new THREE.Matrix4(), q = new THREE.Quaternion(), sc = new THREE.Vector3(), c = new THREE.Color();
  for (let i = 0; i < NAHA_I; i++) {
    const k = Math.sqrt(homes[i] / 640), s = .08 + .36 * k;
    m4.compose(pos[i].clone().setY(TOP + .001), q.identity(), sc.set(s, 1, s)); pools.setMatrixAt(i, m4);
    c.setRGB(.3, .09, .02).multiplyScalar(.35 + .65 * k); pools.setColorAt(i, c);
  }
  if (false) { const k = Math.sqrt(homes[NAHA_I] / 640), s = .08 + .36 * k; const pm = new THREE.Mesh(new THREE.PlaneGeometry(s, s).rotateX(-Math.PI / 2), new THREE.MeshBasicMaterial({ color: new THREE.Color(.3, .09, .02).multiplyScalar(.35 + .65 * k), alphaMap: halo, transparent: true, blending: THREE.AdditiveBlending, depthWrite: false })); pm.position.copy(nahaLocal).setY(TOP + .001); inset.add(pm); }

  /* ---------- arcs: a minimum spanning tree plus near neighbours; pulses in the arc's own colour, ≤ 1.5× */
  const arcMat = new THREE.ShaderMaterial({
    transparent: true, depthWrite: false, blending: THREE.AdditiveBlending,
    uniforms: { uTime: { value: 0 }, uWarm: { value: new THREE.Vector3(1, .38, .1) }, uBase: { value: .12 }, uPulse: { value: .06 } },
    vertexShader: `attribute vec3 aArc; varying float vT; varying vec3 vA; void main(){ vT = uv.x; vA = aArc; gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.); }`,
    fragmentShader: /* glsl */`
      uniform float uTime, uBase, uPulse; uniform vec3 uWarm; varying float vT; varying vec3 vA;
      void main(){
        float t = vA.z > 0. ? vT : 1. - vT;
        float head = fract(uTime * vA.y + vA.x) * 1.5 - .25, d = head - t;
        float pulse = d > 0. ? exp(-d * 6.) : exp(d * 40.);
        float ends = smoothstep(0., .12, vT) * smoothstep(1., .88, vT);
        gl_FragColor = vec4(uWarm * ends * (uBase + pulse * uPulse), 1.);
      }`,
  });
  const edgesSet = new Map(), dist = (a, b) => pos[a].distanceTo(pos[b]);
  const addE = (a, b) => { const k = a < b ? `${a}-${b}` : `${b}-${a}`; if (!edgesSet.has(k)) edgesSet.set(k, [Math.min(a, b), Math.max(a, b)]); };
  const main = names.map((k, i) => i).filter(i => i !== NAHA_I);
  { const inT = new Set([main[0]]); while (inT.size < main.length) { let best = null; for (const a of inT) for (const b of main) if (!inT.has(b)) { const d = dist(a, b); if (!best || d < best[2]) best = [a, b, d]; } addE(best[0], best[1]); inT.add(best[1]); } }
  for (const a of main) { const near = main.filter(b => b !== a).map(b => [b, dist(a, b)]).sort((x, y) => x[1] - y[1]).slice(0, 2); for (const [b, d] of near) if (d < 1.1) addE(a, b); }
  { const r = rng(31), geos = [];
    for (const [a, b] of edgesSet.values()) {
      const p0 = pos[a].clone().setY(TOP + .006), p2 = pos[b].clone().setY(TOP + .006), d = p0.distanceTo(p2);
      const mid = p0.clone().add(p2).multiplyScalar(.5); mid.y += .04 + d * .28;
      const g = new THREE.TubeGeometry(new THREE.QuadraticBezierCurve3(p0, mid, p2), 48, .0022, 5);
      const n = g.attributes.position.count, arc = new Float32Array(n * 3);
      const seed = r(), speed = .1 + r() * .08, dir = r() < .5 ? 1 : -1;
      for (let i = 0; i < n; i++) { arc[i * 3] = seed; arc[i * 3 + 1] = speed / Math.max(.4, d); arc[i * 3 + 2] = dir; }
      g.setAttribute('aArc', new THREE.BufferAttribute(arc, 3)); g.deleteAttribute('normal'); geos.push(g);
    }
    scene.add(new THREE.Mesh(mergeGeometries(geos), arcMat)); geos.forEach(g => g.dispose()); }

  /* ---------- focus ring (postal-code answer) */
  const ringMat = new THREE.MeshBasicMaterial({ color: new THREE.Color(1.2, .4, .08), transparent: true, blending: THREE.AdditiveBlending, depthWrite: false, opacity: 0 });
  const ring = new THREE.Mesh(new THREE.RingGeometry(.96, 1, 96).rotateX(-Math.PI / 2), ringMat); ring.visible = false; scene.add(ring);

  /* ---------- layout: the inset's place, and a camera fitted into the space the DOM leaves */
  const INSET_AT = { wide: toW([640, 590], 0), narrow: toW([470, 650], 0) };
  const layout = { key: '', tx: 0, tz: 0, d: 8, az: .12, el: .74 };
  const AZ = { wide: .12, narrow: -.64 };
  const coastPts = []; for (const p of polys) for (let i = 0; i < p.length; i += 6) coastPts.push(toW(p[i], 0));
  const _v = new THREE.Vector3(), Rr = new THREE.Vector3(), Uu = new THREE.Vector3();
  const place = (az, el, d, tx, tz) => { camera.position.set(tx + Math.sin(az) * Math.cos(el) * d, Math.sin(el) * d, tz + Math.cos(az) * Math.cos(el) * d); camera.lookAt(tx, 0, tz); camera.updateMatrixWorld(); };
  function fitLayout(s, narrow) {
    const key = `${Math.round(s.w)}x${Math.round(s.h)}`; if (key === layout.key) return; layout.key = key;
    const mode = narrow ? 'narrow' : 'wide'; layout.az = AZ[mode]; layout.el = narrow ? .62 : .74;
    inset.position.copy(INSET_AT[mode]); inset.rotation.y = layout.az; inset.updateMatrixWorld(true);
    pos[NAHA_I].copy(nahaLocal).applyMatrix4(inset.matrixWorld);
    seaMat.uniforms.uInset.value.set(inset.position.x, inset.position.z, iw, ih); seaMat.uniforms.uInsetRot.value = layout.az;
    const pts = [...coastPts]; for (const [x, z] of [[-iw, -ih], [iw, -ih], [-iw, ih], [iw, ih]]) pts.push(new THREE.Vector3(x, 0, z).applyMatrix4(inset.matrixWorld));
    // the rectangle the map may use (css px): clear of the heading/postal bar and of the stats strip
    const m = narrow ? { l: 16, r: 16, t: 64, b: 236 } : { l: s.w * .07, r: s.w * .07, t: 70, b: 160 };
    const rx0 = -1 + 2 * m.l / s.w, rx1 = 1 - 2 * m.r / s.w, ry0 = -1 + 2 * m.b / s.h, ry1 = 1 - 2 * m.t / s.h;
    camera.aspect = s.w / s.h; camera.updateProjectionMatrix();
    let d = 8, tx = .1, tz = .8;
    for (let it = 0; it < 16; it++) {
      place(layout.az, layout.el, d, tx, tz);
      let x0 = 1e9, x1 = -1e9, y0 = 1e9, y1 = -1e9; for (const p of pts) { _v.copy(p).project(camera); x0 = Math.min(x0, _v.x); x1 = Math.max(x1, _v.x); y0 = Math.min(y0, _v.y); y1 = Math.max(y1, _v.y); }
      const k = Math.max((x1 - x0) / (rx1 - rx0), (y1 - y0) / (ry1 - ry0));
      d *= k;
      Rr.setFromMatrixColumn(camera.matrixWorld, 0); Uu.setFromMatrixColumn(camera.matrixWorld, 1);
      const h = Math.tan(THREE.MathUtils.degToRad(camera.fov / 2)) * d;
      const ox = ((x0 + x1) / 2 / k - (rx0 + rx1) / 2) * h * camera.aspect, oy = ((y0 + y1) / 2 / k - (ry0 + ry1) / 2) * h;
      // slide the ground target: along screen-right for x, along the ground's forward direction for y
      tx += Rr.x * ox - Math.sin(layout.az) * oy / Math.sin(layout.el); tz += Rr.z * ox - Math.cos(layout.az) * oy / Math.sin(layout.el);
    }
    Object.assign(layout, { tx, tz, d });
    seaMat.uniforms.uBottom.value = -1 + 2 * (m.b - (narrow ? 40 : 30)) / s.h;
  }

  /* ---------- labels: off land, with short hairline leaders */
  const anchors = {}, labelW = {};
  names.forEach((k) => { anchors[k] = new THREE.Vector3(); });
  const readLabels = () => { for (const el of host.querySelectorAll('.gl-anchor')) { const t = el.firstElementChild; if (t) labelW[el.dataset.anchor] = [t.offsetWidth, t.offsetHeight || 22]; } };
  let labelKey = '';
  document.fonts?.ready.then(readLabels); readLabels();
  const leaderGeo = new LineSegmentsGeometry().setPositions(new Array(names.length * 6).fill(0));
  const leaderMat = new LineMaterial({ color: new THREE.Color(.85, .7, .5), linewidth: .8, transparent: true, opacity: .5, depthWrite: false, depthTest: false });
  const leaders = new LineSegments2(leaderGeo, leaderMat); leaders.frustumCulled = false; leaders.renderOrder = 10; scene.add(leaders);
  const _a = new THREE.Vector3(), _b = new THREE.Vector3(), segs = new Float32Array(names.length * 6);
  const toWorldAt = (sx, sy, z, s, out) => out.set(sx / s.w * 2 - 1, -(sy / s.h * 2 - 1), z).unproject(camera);
  function placeLabels(s, narrow) {
    const lk = `${Math.round(s.w)}`; if (lk !== labelKey) { labelKey = lk; readLabels(); }
    segs.fill(0);
    for (let i = 0; i < names.length; i++) {
      const k = names[i]; if (!labelW[k] || !labelW[k][0]) { anchors[k].copy(pos[i]); continue; }
      const [lw, lh] = labelW[k];
      _a.copy(pos[i]).project(camera);
      const sx = (_a.x * .5 + .5) * s.w, sy = (-_a.y * .5 + .5) * s.h;
      let bx, by;
      if (k === 'naha') {                                // above the inset's frame, clear of it
        _b.set(0, 0, -ih).applyMatrix4(inset.matrixWorld).project(camera);
        if (narrow) { _b.set(-iw, 0, 0).applyMatrix4(inset.matrixWorld).project(camera); bx = (_b.x * .5 + .5) * s.w - lw / 2 - 10; by = sy; }
        else { bx = sx + lw * .1; by = (-_b.y * .5 + .5) * s.h - lh / 2 - 8; }
      } else {
        const dir = (narrow ? LABEL_DIR_N : LABEL_DIR)[k] || [1, 0], dl = Math.hypot(dir[0], dir[1]), dx = dir[0] / dl, dy = dir[1] / dl;
        const gap = (LABEL_GAP[k] || (narrow ? 20 : 26)) * (narrow ? .7 : 1) + 10 * Math.sqrt(homes[i] / 640);
        bx = sx + dx * (gap + lw / 2); by = sy + dy * (gap + lh / 2);
      }
      bx = clamp(bx, lw / 2 + 16, s.w - lw / 2 - 16);
      toWorldAt(bx - lw / 2 - 12, by, _a.z, s, anchors[k]);
      // leader: from just off the dot to the nearest point of the label box
      const ex = clamp(sx, bx - lw / 2, bx + lw / 2), ey = clamp(sy, by - lh / 2, by + lh / 2), L = Math.hypot(ex - sx, ey - sy);
      if (L > 6) {
        const st = 5 / L; toWorldAt(sx + (ex - sx) * st, sy + (ey - sy) * st, _a.z, s, _b); segs.set([_b.x, _b.y, _b.z], i * 6);
        toWorldAt(ex, ey, _a.z, s, _b); segs.set([_b.x, _b.y, _b.z], i * 6 + 3);
      }
    }
    leaderGeo.setPositions(segs);
  }

  /* ---------- camera */
  const cur = { az: .12, el: .74, dist: 8, tx: .1, tz: .8 };
  let focus = -1, focusAt = -10, first = true;
  STATE.on((k, v) => { if (k === 'city') { const i = names.indexOf(v); if (i >= 0) { focus = i; focusAt = -1; } } });

  return {
    scene, camera, anchors,
    post: { exposure: EXPO, tone: 'aces', hue: HUE, sat: 1, contrast: 1, vignette: 0, grain: .012, ss: 1.25, bloom: { strength: .5, radius: .8, threshold: 1, knee: .5 } },
    update(dt, t, s) {
      const narrow = s.w < 700, m = REDUCED ? 0 : 1;
      fitLayout(s, narrow);
      let tx = layout.tx, tz = layout.tz, dd = layout.d, az = layout.az + m * Math.sin(t * .05) * .025, el = layout.el;
      if (focus >= 0) { if (focusAt < 0) focusAt = s.age; tx = lerp(tx, pos[focus].x, .55); tz = lerp(tz, pos[focus].z, .55) + .25; dd *= .82; }
      az += clamp(s.pointer.x, -1.2, 1.2) * .035 * m; el += clamp(s.pointer.y, -1.2, 1.2) * .02 * m;
      const snap = first; first = false;
      const k = snap ? 1e3 : 1.6, ka = snap ? 1e3 : 2;
      cur.tx = damp(cur.tx, tx, k, dt); cur.tz = damp(cur.tz, tz, k, dt); cur.dist = damp(cur.dist, dd, k, dt);
      cur.az = damp(cur.az, az, ka, dt); cur.el = damp(cur.el, el, ka, dt);
      place(cur.az, cur.el, cur.dist, cur.tx, cur.tz);
      const pulseAge = focus >= 0 ? s.age - focusAt : 99;
      const scale = clamp(s.w / 1300, .6, 1.1);
      lightsMat.uniforms.uTime.value = REDUCED ? 0 : t; lightsMat.uniforms.uPx.value = renderer.getPixelRatio() * 1.25 * scale;
      lightsMat.uniforms.uFocus.value = focus; lightsMat.uniforms.uBoost.value = focus >= 0 ? .4 + .6 * Math.exp(-pulseAge * .9) : 0;
      if (this.post?.o?.bloom) { this.post.o.bloom.strength = .5 * clamp(s.w / 1100, .35, 1); this.post.o.bloom.radius = narrow ? .55 : .8; }
      arcMat.uniforms.uTime.value = REDUCED ? 3.3 : t;
      if (focus >= 0 && pulseAge < 4 && !REDUCED) {
        const p = (pulseAge % 1.6) / 1.6; ring.visible = true; ring.position.copy(pos[focus]).setY(TOP + .004);
        ring.scale.setScalar(.05 + p * .4); ringMat.opacity = (1 - p) * (1 - pulseAge / 4) * .8;
      } else ring.visible = false;
      frameMat.resolution.set(s.w, s.h); leaderMat.resolution.set(s.w, s.h);
      seaMat.uniforms.uCenter.value.set(cur.tx, cur.tz);
      placeLabels(s, narrow);
    },
    anchorOn(name) { return names.includes(name); },
  };
}
