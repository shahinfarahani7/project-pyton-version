/* Plan card 1 — "Buy outright": 5-yen coins on a black lacquer tray, on washi, photographed against a plum wall
   lit by a low sunset pool. Also exports the plan-card kit (lit wall + real surface, one key, one lens, card
   environment) shared with soroban.js and risingsun.js. Units: cm. */
import { THREE, pbrSet, canvasTexture, makeCanvas, rng, clamp, lerp, damp, REDUCED } from '../core.js';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';

/* ================================================================== plan-card kit */
export const CARD_FOV = 26;
/** Shared card output: ACES as on the direct path, no grade, 1.5× supersampled (thin rods and bead edges stay clean). */
export const CARD_POST = { exposure: 1, tone: 'aces', hue: 0, sat: 1, contrast: 1, vignette: 0, grain: .004, ss: 1.5, bloom: null };
export const KEY_DIR = new THREE.Vector3(-1, 1.3, .8).normalize();   // the shared key: upper left, shadows to the lower right
export const KEY_COL = 0xFFE0BC;
const TAU = Math.PI * 2;
const hexRGB = h => [1, 3, 5].map(i => parseInt(h.slice(i, i + 2), 16) / 255);
const lin = c => c <= .04045 ? c / 12.92 : ((c + .055) / 1.055) ** 2.4;

/** Reflection environment for the cards: a dusk room, the plum-to-sunset wall behind, a warm key softbox upper left,
    a pale surface below. Built once with PMREM from a tiny scene. */
let envTex = null;
export function cardEnv(renderer) {
  if (envTex) return envTex;
  const sc = new THREE.Scene(), col = (h, k) => new THREE.Color(h).multiplyScalar(k);
  const room = new THREE.Mesh(new THREE.BoxGeometry(40, 20, 40), new THREE.MeshBasicMaterial({ color: col(0x4a3440, .7), side: THREE.BackSide })); room.position.y = 6; sc.add(room);
  const wc = makeCanvas(4, 256), g = wc.getContext('2d'), gr = g.createLinearGradient(0, 0, 0, 256);
  gr.addColorStop(0, '#3a2440'); gr.addColorStop(.55, '#7a3a45'); gr.addColorStop(1, '#e08050'); g.fillStyle = gr; g.fillRect(0, 0, 4, 256);
  const wt = new THREE.CanvasTexture(wc); wt.colorSpace = THREE.SRGBColorSpace;
  const wall = new THREE.Mesh(new THREE.PlaneGeometry(40, 14), new THREE.MeshBasicMaterial({ map: wt })); wall.position.set(0, 3, -19.9); sc.add(wall);
  const floor = new THREE.Mesh(new THREE.PlaneGeometry(40, 40), new THREE.MeshBasicMaterial({ color: col(0xE9DCC6, .55) })); floor.rotation.x = -Math.PI / 2; floor.position.y = -3.99; sc.add(floor);
  const box = (w, h, c, k, pos) => { const m = new THREE.Mesh(new THREE.PlaneGeometry(w, h), new THREE.MeshBasicMaterial({ color: col(c, k), side: THREE.DoubleSide })); m.position.set(...pos); m.lookAt(0, 0, 0); sc.add(m); };
  box(9, 6, KEY_COL, 9, KEY_DIR.clone().multiplyScalar(15).toArray());   // key softbox, along the key direction
  box(14, 1.6, 0xFFF3E4, 2.2, [0, 15.5, -2]);                             // top strip
  box(18, 9, 0xFFEBD6, 1.0, [0, 11, -12]);                                // big overhead-back scrim: what flat metal faces see
  box(6, 5, 0xFFB080, 2.6, [9, 1, -16]);                                  // the warm pool behind, right
  box(6, 5, 0xFFF1E2, 1.2, [14, 3, 6]);                                   // dim fill, right front
  const pm = new THREE.PMREMGenerator(renderer); envTex = pm.fromScene(sc, .03).texture; pm.dispose();
  sc.traverse(o => { o.geometry?.dispose(); o.material?.map?.dispose(); o.material?.dispose(); });
  return envTex;
}

/** Reflection environment for small metal/lacquer props on the paper sweep: the same studio (key softbox upper left,
    top strip, warm fill), but with dark flags round the set so metal keeps its contrast instead of mirroring a bright room. */
let metalEnvTex = null;
export function metalEnv(renderer) {
  if (metalEnvTex) return metalEnvTex;
  const sc = new THREE.Scene(), col = (h, k) => new THREE.Color(h).multiplyScalar(k);
  const room = new THREE.Mesh(new THREE.BoxGeometry(40, 20, 40), new THREE.MeshBasicMaterial({ color: col(0x3a2f28, .55), side: THREE.BackSide })); room.position.y = 6; sc.add(room);
  const floor = new THREE.Mesh(new THREE.PlaneGeometry(40, 40), new THREE.MeshBasicMaterial({ color: col(0xEFE4D2, .75) })); floor.rotation.x = -Math.PI / 2; floor.position.y = -3.99; sc.add(floor);
  const wc = makeCanvas(4, 256), g = wc.getContext('2d'), gr = g.createLinearGradient(0, 0, 0, 256);
  gr.addColorStop(0, '#221a16'); gr.addColorStop(.6, '#6a5646'); gr.addColorStop(1, '#d8c8b0'); g.fillStyle = gr; g.fillRect(0, 0, 4, 256);
  const wt = new THREE.CanvasTexture(wc); wt.colorSpace = THREE.SRGBColorSpace;
  const back = new THREE.Mesh(new THREE.PlaneGeometry(40, 16), new THREE.MeshBasicMaterial({ map: wt })); back.position.set(0, 4, -19.9); sc.add(back);
  const box = (w, h, c, k, pos) => { const m = new THREE.Mesh(new THREE.PlaneGeometry(w, h), new THREE.MeshBasicMaterial({ color: col(c, k), side: THREE.DoubleSide })); m.position.set(...pos); m.lookAt(0, 0, 0); sc.add(m); };
  box(9, 6, KEY_COL, 10, KEY_DIR.clone().multiplyScalar(15).toArray());
  box(14, 1.4, 0xFFF3E4, 2.4, [0, 15.5, -2]);
  box(5, 6, 0xFFF1E2, 1.3, [15, 3, 5]);
  box(6, 3, 0xFFC99A, 1.6, [3, 4, -17]);
  // strip softboxes overhead-behind, with feathered but defined edges: flat coin faces sweep across them → broad light/dark bands
  { const c = makeCanvas(64, 64), g2 = c.getContext('2d'), lg = g2.createLinearGradient(0, 0, 0, 64); lg.addColorStop(0, '#000'); lg.addColorStop(.18, '#fff'); lg.addColorStop(.82, '#fff'); lg.addColorStop(1, '#000'); g2.fillStyle = lg; g2.fillRect(0, 0, 64, 64);
    const t = new THREE.CanvasTexture(c);
    const strip = (w, h, k, pos) => { const m = new THREE.Mesh(new THREE.PlaneGeometry(w, h), new THREE.MeshBasicMaterial({ color: col(0xFFE8CC, k), map: t, side: THREE.DoubleSide })); m.position.set(...pos); m.lookAt(0, 0, 0); sc.add(m); };
    strip(26, 5, 1.6, [-1, 13, -9]);     // wide strip high behind
    strip(26, 3, .9, [0, 6.5, -15]);     // lower strip behind: a second band
    strip(4, 12, 1.2, [-12, 9, -6]); }   // vertical strip back-left: edges and rims
  const pm = new THREE.PMREMGenerator(renderer); metalEnvTex = pm.fromScene(sc, .02).texture; pm.dispose();
  sc.traverse(o => { o.geometry?.dispose(); o.material?.map?.dispose(); o.material?.dispose(); });
  return metalEnvTex;
}

/** Washi (kozo paper): warm white with long fibres, soft cloud and a few inclusions. Returns { map, normalMap }. */
let washiP = null;
export function washiMaps() {
  if (washiP) return washiP;
  const S = 1024, R = rng(71), c = makeCanvas(S, S), g = c.getContext('2d'), h = makeCanvas(S, S), hg = h.getContext('2d');
  g.fillStyle = '#ece2d0'; g.fillRect(0, 0, S, S); hg.fillStyle = '#808080'; hg.fillRect(0, 0, S, S);
  const wrap = (fn) => { for (const ox of [-S, 0, S]) for (const oy of [-S, 0, S]) fn(ox, oy); };
  for (let i = 0; i < 60; i++) {   // cloud (uneven pulp)
    const x = R() * S, y = R() * S, r = 40 + R() * 160, v = R() < .5 ? 'rgba(255,250,240,' : 'rgba(200,184,160,';
    wrap((ox, oy) => { const gr = g.createRadialGradient(x + ox, y + oy, 0, x + ox, y + oy, r); gr.addColorStop(0, v + (.05 + R() * .06) + ')'); gr.addColorStop(1, v + '0)'); g.fillStyle = gr; g.fillRect(x + ox - r, y + oy - r, r * 2, r * 2); });
  }
  for (let i = 0; i < 2600; i++) {   // kozo fibres
    const x = R() * S, y = R() * S, len = 30 + R() ** 2 * 220, a = R() * TAU, bend = (R() - .5) * .9, w = .5 + R() * 1.1;
    const light = R() < .75, col = light ? `rgba(255,252,246,${.1 + R() * .2})` : `rgba(150,128,100,${.05 + R() * .08})`;
    const cx = x + Math.cos(a + bend) * len * .5, cy = y + Math.sin(a + bend) * len * .5, ex = x + Math.cos(a) * len, ey = y + Math.sin(a) * len;
    wrap((ox, oy) => {
      g.strokeStyle = col; g.lineWidth = w; g.beginPath(); g.moveTo(x + ox, y + oy); g.quadraticCurveTo(cx + ox, cy + oy, ex + ox, ey + oy); g.stroke();
      hg.strokeStyle = `rgba(255,255,255,${light ? .22 : .1})`; hg.lineWidth = w * 1.4; hg.beginPath(); hg.moveTo(x + ox, y + oy); hg.quadraticCurveTo(cx + ox, cy + oy, ex + ox, ey + oy); hg.stroke();
    });
  }
  for (let i = 0; i < 140; i++) { const x = R() * S, y = R() * S; g.fillStyle = `rgba(110,90,70,${.12 + R() * .2})`; g.beginPath(); g.ellipse(x, y, .6 + R() * 1.6, .5 + R(), R() * 3, 0, TAU); g.fill(); }
  // normal from the fibre height
  const hd = hg.getImageData(0, 0, S, S).data, nC = makeCanvas(S, S), nd = nC.getContext('2d').createImageData(S, S);
  for (let y = 0; y < S; y++) for (let x = 0; x < S; x++) {
    const i = y * S + x, H = (xx, yy) => hd[(((yy + S) % S) * S + ((xx + S) % S)) * 4] / 255;
    const dx = (H(x + 1, y) - H(x - 1, y)) * 1.6, dy = (H(x, y + 1) - H(x, y - 1)) * 1.6, l = Math.hypot(dx, dy, 1);
    nd.data[i * 4] = (-dx / l * .5 + .5) * 255; nd.data[i * 4 + 1] = (dy / l * .5 + .5) * 255; nd.data[i * 4 + 2] = (1 / l * .5 + .5) * 255; nd.data[i * 4 + 3] = 255;
  }
  nC.getContext('2d').putImageData(nd, 0, 0);
  washiP = { map: canvasTexture(c, { repeat: [1, 1] }), normalMap: canvasTexture(nC, { srgb: false, repeat: [1, 1] }) };
  return washiP;
}

/** The photographed set: a seamless paper-toned sweep (≈ #EFE4D2, the page's paper under warm light) with no horizon,
    the shared warm key from the upper left (soft PCF shadows falling lower-right) and the warm bounce. Units: cm.
    opts: { box: [w, d] shadow fit, center: [x, z], keyI, back: z where the sweep starts to curve up, radius } */
export function paperSweep(scene, { box = [16, 10], center = [0, 0], keyI = 3, back = -14, radius = 14, width = 160, reach = 60 } = {}) {
  const washi = washiMaps();
  const map = washi.map.clone(), nrm = washi.normalMap.clone();
  for (const t of [map, nrm]) { t.repeat.set(1 / 7, 1 / 7); t.needsUpdate = true; }   // fine kozo fibres at true scale
  const mat = new THREE.MeshStandardMaterial({ map, normalMap: nrm, normalScale: new THREE.Vector2(.18, .18), roughness: .95, color: new THREE.Color(0xEFE4D2).multiply(new THREE.Color(1, 1.03, 1.1)).multiplyScalar(1.02), envMapIntensity: .35 });
  mat.onBeforeCompile = sh => {   // soften the paper texture: a whisper of fibre, not a pattern
    sh.fragmentShader = sh.fragmentShader.replace('#include <map_fragment>', `#include <map_fragment>
      diffuseColor.rgb = mix(diffuse, diffuseColor.rgb / vec3(.83, .8, .74) * diffuse, .45);`);
  };
  mat.customProgramCacheKey = () => 'paper-sweep';
  falloff(mat, center, Math.max(box[0], box[1]) * 2.2, .95);   // barely: no card should read as vignetted
  // a floor that bends up into a wall on a large radius: no horizon line anywhere in frame
  const N = 120, L = reach + (Math.PI / 2) * radius + 60, geo = new THREE.PlaneGeometry(width, L, 1, N);
  const p = geo.attributes.position, uv = geo.attributes.uv;
  for (let i = 0; i < p.count; i++) {
    const s = (p.getY(i) + L / 2);            // arc length from the front edge
    let y = 0, z = reach - s;
    if (z < back) { const a = Math.min((back - z) / radius, Math.PI / 2); y = radius * (1 - Math.cos(a)); z = back - radius * Math.sin(a); if ((back - (reach - s)) / radius > Math.PI / 2) { const extra = (back - (reach - s)) - radius * Math.PI / 2; y = radius + extra; z = back - radius; } }
    const x = p.getX(i); p.setXYZ(i, x, y, z); uv.setXY(i, x, s);
  }
  geo.computeVertexNormals();
  const sweep = new THREE.Mesh(geo, mat); sweep.receiveShadow = true; scene.add(sweep);
  const key = new THREE.DirectionalLight(new THREE.Color(KEY_COL), keyI);
  key.position.copy(KEY_DIR).multiplyScalar(60).add(new THREE.Vector3(center[0], 0, center[1])); key.target.position.set(center[0], 0, center[1]);
  key.castShadow = true; key.shadow.mapSize.set(2048, 2048);
  const r = Math.max(box[0], box[1]) * .62;
  Object.assign(key.shadow.camera, { left: -r, right: r, top: r, bottom: -r, near: 20, far: 110 }); key.shadow.camera.updateProjectionMatrix();
  key.shadow.bias = -.0002; key.shadow.normalBias = .02; key.shadow.radius = 5;
  scene.add(key, key.target);
  const bounce = new THREE.HemisphereLight(new THREE.Color(0xFFF3E4), new THREE.Color(0xE7D6BC), .4); scene.add(bounce);
  // a warm low rim from behind right (the evening sun past the subject): edges and bevels catch it
  const rim = new THREE.DirectionalLight(new THREE.Color(0xFFC08A), 1.6);
  rim.position.set(center[0] + 30, 16, center[1] - 40); rim.target.position.set(center[0], 0, center[1]); scene.add(rim, rim.target);
  return { sweep, key, bounce, rim, mat };
}

/** Photographic light falloff on a surface: full near the subject, dimmer toward the frame edges. */
export function falloff(mat, c, r, floor = .62) {
  const prev = mat.onBeforeCompile;
  mat.onBeforeCompile = (sh, rd) => {
    prev?.(sh, rd);
    sh.vertexShader = sh.vertexShader.replace('#include <common>', '#include <common>\nvarying vec3 vFoW;').replace('#include <begin_vertex>', '#include <begin_vertex>\nvFoW = (modelMatrix * vec4(transformed, 1.)).xyz;');
    sh.fragmentShader = sh.fragmentShader.replace('#include <common>', '#include <common>\nvarying vec3 vFoW;')
      .replace('#include <map_fragment>', `#include <map_fragment>
        { vec2 fo = (vFoW.xz - vec2(${c[0].toFixed(2)}, ${c[1].toFixed(2)})) / ${r.toFixed(2)}; diffuseColor.rgb *= mix(${floor.toFixed(2)}, 1., exp(-dot(fo, fo))); }`);
  };
  mat.customProgramCacheKey = () => 'falloff' + c + r;
}

/** Soft contact shadow (alpha texture) for under objects. */
export function contactBlob(w, d, opacity = .6, color = 0x1a0e08) {
  const cv = makeCanvas(128, 128), g = cv.getContext('2d');
  const gr = g.createRadialGradient(64, 64, 0, 64, 64, 64);
  gr.addColorStop(0, '#fff'); gr.addColorStop(.35, '#999'); gr.addColorStop(.7, '#2a2a2a'); gr.addColorStop(1, '#000');   // alphaMap reads the green channel: paint grey, not alpha
  g.fillStyle = '#000'; g.fillRect(0, 0, 128, 128); g.fillStyle = gr; g.fillRect(0, 0, 128, 128);
  const m = new THREE.Mesh(new THREE.PlaneGeometry(w, d), new THREE.MeshBasicMaterial({ color, alphaMap: canvasTexture(cv, { srgb: false }), transparent: true, opacity, depthWrite: false, toneMapped: false, polygonOffset: true, polygonOffsetFactor: -2, polygonOffsetUnits: -4 }));
  m.rotation.x = -Math.PI / 2; m.position.y = .004; m.renderOrder = 1;
  return m;
}

/** One camera for the plan row (as the hardware row): same lens, 30° elevation, 12° yaw; the object's bounds fill
    ~65 % of the card width, centred. box: THREE.Box3 of the object (world). Returns a view for cardCamera. */
export const CARD_VIEW = { el: .52, az: .21, fill: .65, aspect: 16 / 11 };
export function frameView(box, { el = CARD_VIEW.el, az = CARD_VIEW.az, fill = CARD_VIEW.fill, aspect = CARD_VIEW.aspect } = {}) {
  const cam = new THREE.PerspectiveCamera(CARD_FOV, aspect, .1, 1000), T = box.getCenter(new THREE.Vector3()), v = new THREE.Vector3();
  const corners = []; for (const x of [box.min.x, box.max.x]) for (const y of [box.min.y, box.max.y]) for (const z of [box.min.z, box.max.z]) corners.push(new THREE.Vector3(x, y, z));
  const place = d => { cam.position.set(T.x + Math.sin(az) * Math.cos(el) * d, T.y + Math.sin(el) * d, T.z + Math.cos(az) * Math.cos(el) * d); cam.lookAt(T); cam.updateMatrixWorld(); };
  const ext = () => { let x0 = 1, x1 = -1, y0 = 1, y1 = -1; for (const c of corners) { v.copy(c).project(cam); x0 = Math.min(x0, v.x); x1 = Math.max(x1, v.x); y0 = Math.min(y0, v.y); y1 = Math.max(y1, v.y); } return { x0, x1, y0, y1 }; };
  let d = 30;
  for (let it = 0; it < 6; it++) {
    let lo = 1, hi = 500;
    for (let k = 0; k < 30; k++) { const mid = (lo + hi) / 2; place(mid); const e = ext(); (e.x1 - e.x0) / 2 > fill ? lo = mid : hi = mid; }
    d = hi; place(d);
    const e = ext(), right = new THREE.Vector3().setFromMatrixColumn(cam.matrixWorld, 0), up = new THREE.Vector3().setFromMatrixColumn(cam.matrixWorld, 1);
    const wpn = d * Math.tan(THREE.MathUtils.degToRad(CARD_FOV) / 2);   // world per NDC unit (vertical) at the target
    T.addScaledVector(right, (e.x0 + e.x1) / 2 * wpn * aspect).addScaledVector(up, (e.y0 + e.y1) / 2 * wpn);
  }
  return { el, az, dist: d, target: T.clone(), shift: null };
}

/** Shared lens and camera behaviour: pointer parallax, hover lean-in, idle drift. */
export function cardCamera(camera, view, s, st, dt, t) {
  if (!REDUCED) {
    st.px = damp(st.px ?? 0, clamp(s.pointer.x, -1, 1) * (s.hover ? 1 : .35), 3, dt);
    st.py = damp(st.py ?? 0, clamp(s.pointer.y, -1, 1) * (s.hover ? 1 : .35), 3, dt);
    st.hv = damp(st.hv ?? 0, s.hover ? 1 : 0, 3.5, dt);
  } else { st.px = st.py = st.hv = 0; }
  const az = view.az + st.px * .06 + (REDUCED ? 0 : Math.sin(t * .31) * .012);
  const el = view.el - st.py * .03 + (REDUCED ? 0 : Math.sin(t * .23 + 1.3) * .006);
  const d = view.dist * (1 - st.hv * .035), T = view.target;
  camera.position.set(T.x + Math.sin(az) * Math.cos(el) * d, T.y + Math.sin(el) * d, T.z + Math.cos(az) * Math.cos(el) * d);
  camera.lookAt(T);
  if (view.shift) camera.setViewOffset(1000, 1000 / camera.aspect, -view.shift[0] * 1000, -view.shift[1] * 1000 / camera.aspect, 1000, 1000 / camera.aspect);
  return st.hv;
}

/* ================================================================== the 5-yen coin */
const R5 = 1.1, HALF = .05, FIELD = .042, RIM = .055, HOLE = .25, BEV = .005;   // 22 mm : 1.0 mm, rim 0.55 mm wide

/** Paint a height map with draw(g, S) (S = px per face radius, origin at the centre) → normal / albedo / roughness maps. */
function reliefMaps(size, draw, { strength = 2.2, base, seed = 1 }) {
  const hc = makeCanvas(size, size), g = hc.getContext('2d'), S = size / 2;
  g.fillStyle = '#5a5a5a'; g.fillRect(0, 0, size, size);
  g.save(); g.translate(S, S); draw(g, S * .985); g.restore();
  const hs = makeCanvas(size, size), gs = hs.getContext('2d'); gs.filter = `blur(${(size / 800).toFixed(2)}px)`; gs.drawImage(hc, 0, 0);
  const hb = makeCanvas(size, size), gb = hb.getContext('2d'); gb.filter = `blur(${(size / 110).toFixed(1)}px)`; gb.drawImage(hc, 0, 0);
  const A = gs.getImageData(0, 0, size, size).data, B = gb.getImageData(0, 0, size, size).data;
  const nC = makeCanvas(size, size), aC = makeCanvas(size, size), rC = makeCanvas(size, size);
  const nD = nC.getContext('2d').createImageData(size, size), aD = aC.getContext('2d').createImageData(size, size), rD = rC.getContext('2d').createImageData(size, size);
  const R = rng(seed), k = strength * size / 512;
  // tarnish: soft patches of darker, browner brass, heavier in the recesses; the raised relief stays bright from handling
  const tq = 12, tg = new Float32Array(tq * tq); for (let i = 0; i < tg.length; i++) tg[i] = R();
  const tn = (x, y) => { const u = x / size * (tq - 1), v = y / size * (tq - 1), x0 = Math.floor(u), y0 = Math.floor(v), fx = u - x0, fy = v - y0, sx = fx * fx * (3 - 2 * fx), sy = fy * fy * (3 - 2 * fy), g = (a, b) => tg[Math.min(tq - 1, b) * tq + Math.min(tq - 1, a)];
    return (g(x0, y0) * (1 - sx) + g(x0 + 1, y0) * sx) * (1 - sy) + (g(x0, y0 + 1) * (1 - sx) + g(x0 + 1, y0 + 1) * sx) * sy; };
  for (let y = 0; y < size; y++) for (let x = 0; x < size; x++) {
    const i = y * size + x, h = A[i * 4] / 255, xl = Math.max(0, x - 1), xr = Math.min(size - 1, x + 1), yu = Math.max(0, y - 1), yd = Math.min(size - 1, y + 1);
    const dx = (A[(y * size + xr) * 4] - A[(y * size + xl) * 4]) / 510 * k, dy = (A[(yd * size + x) * 4] - A[(yu * size + x) * 4]) / 510 * k;
    const l = Math.hypot(dx, dy, 1);
    nD.data[i * 4] = (-dx / l * .5 + .5) * 255; nD.data[i * 4 + 1] = (dy / l * .5 + .5) * 255; nD.data[i * 4 + 2] = (1 / l * .5 + .5) * 255; nD.data[i * 4 + 3] = 255;
    const cav = clamp((B[i * 4] / 255 - h) * 4), relief = clamp((h - .36) * 2.4), n = R();
    const dark = 1 - cav * .5 + relief * .05 + (n - .5) * .025;
    const tar = cav * .3;   // one clean brass: only the recesses darken
    const tc = [1 - tar * .32, 1 - tar * .42, 1 - tar * .6];   // tarnish browns the brass
    aD.data[i * 4] = clamp(base[0] * dark * tc[0]) * 255; aD.data[i * 4 + 1] = clamp(base[1] * dark * tc[1]) * 255; aD.data[i * 4 + 2] = clamp(base[2] * dark * tc[2]) * 255; aD.data[i * 4 + 3] = 255;
    rD.data[i * 4] = (1 - cav * .45) * 255; rD.data[i * 4 + 1] = clamp(.3 + cav * .22 + tar * .22 - relief * .1 + (n - .5) * .05) * 255; rD.data[i * 4 + 2] = 0; rD.data[i * 4 + 3] = 255;
  }
  nC.getContext('2d').putImageData(nD, 0, 0); aC.getContext('2d').putImageData(aD, 0, 0); rC.getContext('2d').putImageData(rD, 0, 0);
  const t = (c, cs) => { const tx = new THREE.CanvasTexture(c); tx.colorSpace = cs; tx.anisotropy = 8; return tx; };
  return { map: t(aC, THREE.LinearSRGBColorSpace), normalMap: t(nC, THREE.NoColorSpace), roughnessMap: t(rC, THREE.NoColorSpace), aoMap: t(rC, THREE.NoColorSpace) };
}

/* obverse: the gear around the hole, an ear of rice arching over, water lines below */
function drawObverse(g, S) {
  const hi = '#e6e6e6', mid = '#bdbdbd', hole = HOLE / (R5 - RIM);
  g.save(); g.beginPath(); g.arc(0, 0, S * .92, 0, TAU); g.clip();
  g.fillStyle = mid; for (let k = 0; k < 6; k++) g.fillRect(-S, S * (.36 + k * .088), 2 * S, S * .032);
  g.fillStyle = '#5a5a5a'; g.beginPath(); g.arc(0, 0, S * .45, 0, TAU); g.fill();
  g.restore();
  g.fillStyle = hi; g.beginPath();
  const teeth = 16, r0 = S * .335, r1 = S * .405;
  for (let i = 0; i < teeth; i++) {
    const a0 = i / teeth * TAU, a1 = (i + .28) / teeth * TAU, a2 = (i + .5) / teeth * TAU, a3 = (i + .78) / teeth * TAU;
    g.lineTo(Math.cos(a0) * r0, Math.sin(a0) * r0); g.lineTo(Math.cos(a1) * r1, Math.sin(a1) * r1); g.lineTo(Math.cos(a2) * r1, Math.sin(a2) * r1); g.lineTo(Math.cos(a3) * r0, Math.sin(a3) * r0);
  }
  g.closePath(); g.fill();
  g.fillStyle = '#6a6a6a'; g.beginPath(); g.arc(0, 0, S * .3, 0, TAU); g.fill();
  g.strokeStyle = mid; g.lineWidth = S * .018; g.beginPath(); g.arc(0, 0, S * hole * 1.1, 0, TAU); g.stroke();
  const bez = (p0, p1, p2) => t => { const u = 1 - t; return [(u * u * p0[0] + 2 * u * t * p1[0] + t * t * p2[0]) * S, (u * u * p0[1] + 2 * u * t * p1[1] + t * t * p2[1]) * S]; };
  const stalk = bez([-.5, .34], [-.8, -.74], [.44, -.64]), ear = bez([.02, -.73], [.62, -.8], [.72, -.12]);
  g.strokeStyle = hi; g.lineCap = 'round'; g.lineWidth = S * .03; g.beginPath(); for (let i = 0; i <= 48; i++) { const [x, y] = stalk(i / 48); i ? g.lineTo(x, y) : g.moveTo(x, y); } g.stroke();
  const leaf = (x0, y0, cx, cy, x1, y1, w) => { g.fillStyle = mid; g.beginPath(); g.moveTo(x0 * S, y0 * S); g.quadraticCurveTo(cx * S, cy * S, x1 * S, y1 * S); g.quadraticCurveTo((cx + w) * S, (cy + w * .4) * S, x0 * S, y0 * S); g.fill(); };
  leaf(-.46, .36, -.9, -.1, -.66, -.52, .16); leaf(-.44, .34, -.62, -.2, -.18, -.5, .1);
  g.lineWidth = S * .016; g.beginPath(); for (let i = 0; i <= 36; i++) { const [x, y] = ear(i / 36); i ? g.lineTo(x, y) : g.moveTo(x, y); } g.stroke();
  // the ear: plump grains in pairs along the drooping stem, each a raised kernel with a sunken outline
  for (let i = 0; i < 11; i++) {
    const t = .05 + i / 11 * .9, [x, y] = ear(t), [x2, y2] = ear(Math.min(1, t + .01)), a = Math.atan2(y2 - y, x2 - x);
    for (const side of [-1, 1]) {
      const sz = S * (.07 - t * .02);
      g.save(); g.translate(x + Math.cos(a + side * 1.57) * sz * .72, y + Math.sin(a + side * 1.57) * sz * .72); g.rotate(a + side * .6);
      g.fillStyle = '#4a4a4a'; g.beginPath(); g.ellipse(0, 0, sz * 1.16, sz * .66, 0, 0, TAU); g.fill();   // the groove round each kernel
      const kg = g.createRadialGradient(-sz * .2, -sz * .15, 0, 0, 0, sz); kg.addColorStop(0, '#f4f4f4'); kg.addColorStop(1, '#bdbdbd');
      g.fillStyle = kg; g.beginPath(); g.ellipse(0, 0, sz, sz * .52, 0, 0, TAU); g.fill();                 // domed kernel
      g.strokeStyle = '#8a8a8a'; g.lineWidth = S * .005; g.beginPath(); g.moveTo(-sz * .7, 0); g.lineTo(sz * .7, 0); g.stroke();   // the kernel's seam
      g.restore();
    }
  }
}
/* reverse: 日本國 above the hole, the year below, futaba sprouts either side — set in type, struck in relief */
function drawReverse(g, S, font) {
  const hi = '#e2e2e2';
  g.fillStyle = hi; g.textAlign = 'center'; g.textBaseline = 'middle';
  g.font = `500 ${Math.round(S * .25)}px ${font}`;
  const kan = ['日', '本', '國'];
  kan.forEach((c, i) => g.fillText(c, (i - 1) * S * .29, -S * .56));
  g.font = `500 ${Math.round(S * .14)}px ${font}`;
  ['令', '和', '五', '年'].forEach((c, i) => g.fillText(c, (i - 1.5) * S * .165, S * .6));
  for (const sx of [-1, 1]) {
    g.save(); g.translate(sx * S * .6, S * .08); g.scale(sx, 1);
    g.strokeStyle = hi; g.lineWidth = S * .024; g.lineCap = 'round'; g.beginPath(); g.moveTo(0, S * .22); g.quadraticCurveTo(S * .02, S * .04, 0, -S * .06); g.stroke();
    g.fillStyle = hi;
    g.beginPath(); g.ellipse(-S * .095, -S * .13, S * .1, S * .05, .55, 0, TAU); g.fill();
    g.beginPath(); g.ellipse(S * .095, -S * .13, S * .1, S * .05, -.55, 0, TAU); g.fill();
    g.restore();
  }
}

/** One coin geometry, three groups: 0 obverse field, 1 reverse field, 2 plain metal (crisp flat rims, walls, hole). */
function coinGeometry() {
  const faceR = R5 - RIM;
  const top = new THREE.RingGeometry(HOLE, faceR, 128, 2); top.rotateX(-Math.PI / 2); top.translate(0, FIELD, 0);
  const bot = new THREE.RingGeometry(HOLE, faceR, 128, 2); bot.rotateX(Math.PI / 2); bot.translate(0, -FIELD, 0);
  const L = pts => new THREE.LatheGeometry(pts.map(([r, y]) => new THREE.Vector2(r, y)), 128);
  const metal = mergeGeometries([
    L([[faceR, HALF], [faceR, FIELD]]),                  // rim step, top (faces the centre)
    L([[R5 - BEV, HALF], [faceR, HALF]]),                // rim top, flat
    L([[R5, HALF - BEV], [R5 - BEV, HALF]]),             // arris
    L([[R5, -HALF + BEV], [R5, HALF - BEV]]),            // edge, smooth
    L([[R5 - BEV, -HALF], [R5, -HALF + BEV]]),
    L([[faceR, -HALF], [R5 - BEV, -HALF]]),
    L([[faceR, -FIELD], [faceR, -HALF]]),
  ].map(g => { g.deleteAttribute('uv'); g.setAttribute('uv', new THREE.Float32BufferAttribute(new Float32Array(g.attributes.position.count * 2), 2)); return g; }));
  const hole = L([[HOLE, FIELD], [HOLE, -FIELD]]); hole.deleteAttribute('uv'); hole.setAttribute('uv', new THREE.Float32BufferAttribute(new Float32Array(hole.attributes.position.count * 2), 2));
  const ni = g => g.index ? g.toNonIndexed() : g;
  const geo = mergeGeometries([ni(top), ni(bot), ni(metal), ni(hole)], true);   // groups: obverse, reverse, rim/edge, bore
  return geo;
}

async function loadFont() {
  const fam = '"Shippori Mincho", "Hiragino Mincho ProN", "Yu Mincho", serif';
  try { await Promise.race([document.fonts.load('500 120px "Shippori Mincho"', '日本國令和五年'), new Promise(r => setTimeout(r, 2500))]); } catch (e) { }
  return fam;
}

export async function create(ctx) {
  const { renderer, env: pageEnv } = ctx;
  const scene = new THREE.Scene();
  const env = pageEnv.studio || cardEnv(renderer);
  scene.environment = env; scene.environmentIntensity = .45;
  const camera = new THREE.PerspectiveCamera(CARD_FOV, 1.45, 4, 400);
  const R = rng(5);
  const menv = metalEnv(renderer);
  const stage = paperSweep(scene, { box: [14, 13], center: [0, 0], keyI: 3.1, back: -16, radius: 16 });

  /* the tray: a round black urushi obon (maru-bon), Ø 14 cm, with a thick built-up, rolled rim */
  const TR = 6, FLOOR = .3, RIMH = 1.0, RIMW = .52;
  const prof = [[0, FLOOR], [TR - RIMW - .15, FLOOR], [TR - RIMW, FLOOR + .06]];               // floor, then a soft cove into the wall
  for (let i = 0; i <= 10; i++) { const a = i / 10 * Math.PI; prof.push([TR - RIMW / 2 - Math.cos(a) * RIMW / 2, RIMH - RIMW / 2 + Math.sin(a) * RIMW / 2]); }   // rolled lip
  prof.push([TR, RIMH * .5], [TR - .04, .06], [TR - .12, 0], [0, 0]);
  const trayGeo = new THREE.LatheGeometry(prof.map(([r, y]) => new THREE.Vector2(r, y)).reverse(), 160);
  const urushi = new THREE.Color('#1a1210').convertSRGBToLinear();
  const lacquer = new THREE.MeshPhysicalMaterial({ color: urushi, roughness: .3, clearcoat: 1, clearcoatRoughness: .15, envMap: menv, envMapIntensity: .8 });   // envMap set: r163+ ignores envMapIntensity without it
  const tray = new THREE.Mesh(trayGeo, lacquer); tray.castShadow = tray.receiveShadow = true; scene.add(tray);
  // the floor mirrors the coins, softly: a reflection pass of layer 1 sampled from a blurred mip
  const reflRT = new THREE.WebGLRenderTarget(512, 352, { type: THREE.HalfFloatType, generateMipmaps: true, minFilter: THREE.LinearMipmapLinearFilter, samples: 0 });
  const RU = { uRefl: { value: reflRT.texture }, uTexMat: { value: new THREE.Matrix4() } };
  const floorMat = lacquer.clone(); floorMat.envMapIntensity = .45; floorMat.roughness = .22;
  floorMat.onBeforeCompile = sh => {
    Object.assign(sh.uniforms, RU);
    sh.vertexShader = sh.vertexShader.replace('#include <common>', '#include <common>\nuniform mat4 uTexMat; varying vec4 vRefl;')
      .replace('#include <begin_vertex>', '#include <begin_vertex>\nvRefl = uTexMat * modelMatrix * vec4(transformed, 1.);');
    sh.fragmentShader = sh.fragmentShader.replace('#include <common>', '#include <common>\nuniform sampler2D uRefl; varying vec4 vRefl;')
      .replace('#include <opaque_fragment>', `
        { vec2 ruv = vRefl.xy / vRefl.w;
          vec3 rc = texture(uRefl, ruv, 2.4).rgb * .6 + texture(uRefl, ruv, 3.6).rgb * .4;
          float nv = clamp(dot(normalize(vViewPosition), normal), 0., 1.);
          outgoingLight += rc * (.05 + .95 * pow(1. - nv, 5.)) * 1.5; }
        #include <opaque_fragment>`);
  };
  const floor = new THREE.Mesh(new THREE.CircleGeometry(TR - RIMW - .12, 96).rotateX(-Math.PI / 2).translate(0, FLOOR + .002, 0), floorMat); floor.receiveShadow = true; scene.add(floor);
  const reflCam = new THREE.PerspectiveCamera(); reflCam.layers.set(1);
  const _cp = new THREE.Vector3(), _la = new THREE.Vector3(), _up = new THREE.Vector3(), _rm = new THREE.Matrix4();
  const bias = new THREE.Matrix4().set(.5, 0, 0, .5, 0, .5, 0, .5, 0, 0, .5, .5, 0, 0, 0, 1);
  function reflect(cam, hPlane) {
    cam.updateMatrixWorld();
    _cp.setFromMatrixPosition(cam.matrixWorld); _rm.extractRotation(cam.matrixWorld);
    _la.set(0, 0, -1).applyMatrix4(_rm).add(_cp); _up.set(0, 1, 0).applyMatrix4(_rm);
    reflCam.position.set(_cp.x, 2 * hPlane - _cp.y, _cp.z); reflCam.up.set(_up.x, -_up.y, _up.z);
    reflCam.lookAt(_la.x, 2 * hPlane - _la.y, _la.z); reflCam.updateMatrixWorld();
    reflCam.projectionMatrix.copy(cam.projectionMatrix); reflCam.projectionMatrixInverse.copy(cam.projectionMatrixInverse);
    RU.uTexMat.value.copy(bias).multiply(reflCam.projectionMatrix).multiply(reflCam.matrixWorldInverse);
    const prevT = renderer.getRenderTarget(), prevSc = renderer.getScissorTest();
    renderer.setRenderTarget(reflRT); renderer.setScissorTest(false); renderer.setViewport(0, 0, reflRT.width, reflRT.height);
    renderer.setClearColor(0x000000, 0); renderer.clear(true, true, false); renderer.setClearColor(0xF3EADB, 1);
    renderer.render(scene, reflCam);
    renderer.setRenderTarget(prevT); renderer.setScissorTest(prevSc);
  }
  const trayAO = contactBlob(TR * 2.25, TR * 2.25, .5); scene.add(trayAO);

  /* coins: paler brass with soft tarnish; five per-coin variants of tint and polish */
  const font = await loadFont();
  const B = [.86, .68, .38];
  const obv = reliefMaps(1536, drawObverse, { strength: 2.3, base: B, seed: 3 });
  const rev = reliefMaps(1536, (g, S) => drawReverse(g, S, font), { strength: 2.1, base: B, seed: 4 });
  const variants = [[1, 1, .3], [.94, .95, .4], [1.03, 1.02, .26], [.9, .9, .46], [.98, .96, .34]].map(([k, sat, rough]) => {
    const tint = new THREE.Color(k, k * (.99 + (sat - 1) * .5), k * sat);
    const face = m => new THREE.MeshStandardMaterial({ map: m.map, normalMap: m.normalMap, roughnessMap: m.roughnessMap, aoMap: m.aoMap, aoMapIntensity: .9, roughness: rough / .32, metalness: 1, color: tint, envMap: menv, envMapIntensity: 1.3 });
    const plain = new THREE.MeshStandardMaterial({ color: new THREE.Color(...B).multiply(tint).multiplyScalar(.92), roughness: rough + .05, metalness: 1, envMap: menv, envMapIntensity: 1.3 });
    const bore = new THREE.MeshStandardMaterial({ color: new THREE.Color(...B).multiplyScalar(.25), roughness: .6, metalness: 1, envMap: menv, envMapIntensity: .25 });
    return [face(obv), face(rev), plain, bore];
  });
  const coinGeo = coinGeometry();
  const coin = () => { const m = new THREE.Mesh(coinGeo, variants[Math.floor(R() * variants.length)]); m.castShadow = m.receiveShadow = true; m.layers.enable(1); return m; };
  const onTray = new THREE.Group(); onTray.position.y = FLOOR; scene.add(onTray);
  const blobAt = (x, z, s, o = .5) => { const b = contactBlob(s, s, o); b.position.set(x, .004, z); onTray.add(b); };

  // one neat stack (≈ 0.5 mm of play: the bore stays a clear tube)
  const SX = -1.9, SZ = -1.0, SN = 9;
  for (let i = 0; i < SN; i++) { const c = coin(); c.position.set(SX + (R() - .5) * .05, HALF + i * HALF * 2, SZ + (R() - .5) * .05); c.rotation.y = R() * TAU; onTray.add(c); }
  blobAt(SX, SZ, 3.1, .55);
  // one coin leaning on the stack: its lower edge on the tray, its face resting on the top coin's rim
  { const D = 2.75, dir = new THREE.Vector3(.55, 0, .83).normalize(), top = SN * HALF * 2;
    const alpha = Math.atan2(top, D - R5);
    const pivot = new THREE.Group(); pivot.position.set(SX + dir.x * D, 0, SZ + dir.z * D); pivot.rotation.y = Math.atan2(-dir.z, dir.x); onTray.add(pivot);
    const tilt = new THREE.Group(); tilt.rotation.z = -alpha; pivot.add(tilt);
    const c = coin(); c.position.set(-R5, HALF, 0); c.rotation.y = 1.3; tilt.add(c);
    blobAt(SX + dir.x * (D - .9), SZ + dir.z * (D - .9), 2.4, .35); }

  // go-en: five coins threaded on a red mizuhiki cord, shingled in a row, the cord's ends curling away
  const row = [], N5 = 5, RX = 1.3, RZ = 1.2, step = 1.0, ang = -.45;
  const rdir = new THREE.Vector3(Math.cos(ang), 0, Math.sin(ang));
  for (let i = 0; i < N5; i++) {
    const c = coin(); const p = new THREE.Vector3(RX, 0, RZ).addScaledVector(rdir, (i - (N5 - 1) / 2) * step);
    const lean = .32;   // each coin rests on the one before: shingled
    const g = new THREE.Group(); g.position.set(p.x, HALF + Math.sin(lean) * R5 * .55, p.z); g.rotation.y = -ang; onTray.add(g);
    c.rotation.set(0, R() * TAU, 0); const tiltG = new THREE.Group(); tiltG.rotation.z = lean; tiltG.add(c); g.add(tiltG);
    row.push(g.position.clone());
  }
  blobAt(RX, RZ, 6.2, .3);
  {
    // the cord runs through the bores (centre line), then out both ends in loose curls lying on the tray
    const a = row[0], z = row[N5 - 1];
    const pts = [
      new THREE.Vector3(a.x - 3.2 * rdir.x + .6, .1, a.z - 3.2 * rdir.z + 1.2), new THREE.Vector3(a.x - 2.2 * rdir.x + .2, .08, a.z - 2.2 * rdir.z + .9),
      new THREE.Vector3(a.x - 1.1 * rdir.x, .12, a.z - 1.1 * rdir.z + .15),
      ...row.map(p => new THREE.Vector3(p.x, p.y, p.z)),
      new THREE.Vector3(z.x + 1.1 * rdir.x, .12, z.z + 1.1 * rdir.z - .1), new THREE.Vector3(z.x + 1.9 * rdir.x - .3, .08, z.z + 1.9 * rdir.z + .7),
      new THREE.Vector3(z.x + 1.4 * rdir.x - .9, .08, z.z + 1.4 * rdir.z + 1.5), new THREE.Vector3(z.x + .4 * rdir.x - .8, .08, z.z + .4 * rdir.z + 1.9),
    ];
    const curve = new THREE.CatmullRomCurve3(pts, false, 'centripetal', .5);
    const cordMat = new THREE.MeshPhysicalMaterial({ color: new THREE.Color('#B0141C').convertSRGBToLinear(), roughness: .38, clearcoat: .6, clearcoatRoughness: .3, sheen: .4, sheenColor: new THREE.Color(1, .4, .4), envMap: menv, envMapIntensity: .7 });
    const goldMat = new THREE.MeshStandardMaterial({ color: new THREE.Color(.9, .7, .36), roughness: .3, metalness: 1, envMap: menv, envMapIntensity: 1.2 });
    // three strands side by side (mizuhiki is bundled paper cord): red, gold, red
    const frames = curve.computeFrenetFrames(240, false);
    [-1, 0, 1].forEach(k => {
      const off = curve.getSpacedPoints(240).map((p, i) => p.clone().addScaledVector(frames.binormals[i], k * .115).setY(Math.max(p.y + (k === 0 ? .01 : 0), .05)));
      const g = new THREE.TubeGeometry(new THREE.CatmullRomCurve3(off), 360, .06, 8, false);
      const m = new THREE.Mesh(g, k === 0 ? goldMat : cordMat); m.castShadow = m.receiveShadow = true; m.layers.enable(1); onTray.add(m);
    });
  }

  for (const l of [stage.key, stage.bounce, stage.rim]) l.layers.enable(1);
  stage.key.shadow.autoUpdate = false; stage.key.shadow.needsUpdate = true;
  const view = { az: .1, el: .72, dist: 28, target: new THREE.Vector3(0, .3, .2), shift: [0, .03] };
  const st = {};
  return {
    scene, camera, post: CARD_POST,
    update(dt, t, s) {
      cardCamera(camera, view, s, st, dt, t);
      reflect(camera, FLOOR);
    },
  };
}

