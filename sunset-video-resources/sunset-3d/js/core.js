/* Sunset — shared engine.
   One fixed WebGL canvas (#gl) sits behind the DOM and is the page ground. Every [data-scene] host is a
   window into its own THREE.Scene, drawn each frame with viewport + scissor onto the same canvas.
   Scene modules (js/scenes/<name>.js) export `async function create(ctx)`; see BRIEF.md for the contract. */
import * as THREE from 'three';
import { HDRLoader } from 'three/addons/loaders/HDRLoader.js';

export { THREE };

/* ------------------------------------------------------------------ math */
export const clamp = (v, a = 0, b = 1) => Math.min(b, Math.max(a, v));
export const lerp = (a, b, t) => a + (b - a) * t;
export const inv = (a, b, v) => clamp((v - a) / (b - a));
export const smooth = (a, b, v) => { const t = inv(a, b, v); return t * t * (3 - 2 * t); };
export const damp = (a, b, lambda, dt) => lerp(a, b, 1 - Math.exp(-lambda * dt));
export const E = {
  outCubic: t => 1 - (1 - t) ** 3, outQuart: t => 1 - (1 - t) ** 4, outExpo: t => t >= 1 ? 1 : 1 - 2 ** (-10 * t),
  inOutCubic: t => t < .5 ? 4 * t ** 3 : 1 - (-2 * t + 2) ** 3 / 2, inOutSine: t => -(Math.cos(Math.PI * t) - 1) / 2,
  outBack: t => 1 + 2.2 * (t - 1) ** 3 + 1.2 * (t - 1) ** 2,
};
/** Deterministic PRNG: const r = rng(7); r() -> [0,1). Never use Math.random in scene builds. */
export function rng(seed = 1) { let s = seed >>> 0 || 1; return () => { s = (s + 0x6D2B79F5) >>> 0; let t = s; t = Math.imul(t ^ t >>> 15, t | 1); t ^= t + Math.imul(t ^ t >>> 7, t | 61); return ((t ^ t >>> 14) >>> 0) / 4294967296; }; }

/* ------------------------------------------------------------------ viewport, pointer */
export const VP = { w: 1440, h: 900, dpr: 0, maxDpr: 2, mobile: false };   // dpr 0: first read starts at the device ratio
export function readViewport() {
  const w = document.documentElement.clientWidth || window.innerWidth || 1440;
  const h = window.innerHeight || document.documentElement.clientHeight || 900;
  VP.w = w; VP.h = h; VP.mobile = w < 820;
  const q = new URLSearchParams(location.search);
  VP.maxDpr = q.has('dpr') ? +q.get('dpr') : Math.min(window.devicePixelRatio || 1, 2);
  if (!VP.dpr || VP.dpr > VP.maxDpr) VP.dpr = VP.maxDpr;
  return VP;
}
readViewport();
export const PTR = { x: VP.w / 2, y: VP.h / 2, nx: 0, ny: 0, active: false };
addEventListener('pointermove', e => { PTR.x = e.clientX; PTR.y = e.clientY; PTR.nx = e.clientX / VP.w * 2 - 1; PTR.ny = e.clientY / VP.h * 2 - 1; PTR.active = true; }, { passive: true });
export const REDUCED = matchMedia('(prefers-reduced-motion: reduce)').matches;

/* ------------------------------------------------------------------ shared state (calculator, map lookups) */
export const STATE = {
  bill: 15000,
  listeners: new Set(),
  set(k, v) { this[k] = v; this.listeners.forEach(f => f(k, v)); },
  on(f) { this.listeners.add(f); return () => this.listeners.delete(f); },
};
/** 25-year cost model shared by the DOM readouts and the 3-D chart (yen). */
export function costs(bill) {
  const esc = 1.03, yrs = 25;
  let grid = 0; for (let y = 0; y < yrs; y++) grid += 12 * bill * esc ** y;
  const solar = grid * 0.5 + 1.5e6;                  // own panels, no battery: ~half the bill + ¥1.5M upfront
  const sunset = yrs * 12 * Math.max(6800, bill * .58) + grid * .08;  // flat plan (58% of today's bill, from ¥6,800) + a little residual grid
  return { grid, solar, sunset, save: grid - sunset };
}

/* ------------------------------------------------------------------ renderer (the page ground) */
export const canvas = document.getElementById('gl');
export const renderer = new THREE.WebGLRenderer({ canvas, antialias: true, alpha: false, powerPreference: 'high-performance', stencil: false });
renderer.setPixelRatio(VP.dpr);
renderer.setSize(VP.w, VP.h, false);
renderer.outputColorSpace = THREE.SRGBColorSpace;
renderer.toneMapping = THREE.ACESFilmicToneMapping;
renderer.shadowMap.enabled = true;
renderer.shadowMap.type = THREE.PCFShadowMap;   // r186: PCF is the soft path (PCFSoft was removed); widen with light.shadow.radius
renderer.autoClear = false;
renderer.setClearColor(0xF3EADB, 1);
export const MAX_ANISO = renderer.capabilities.getMaxAnisotropy();
document.documentElement.classList.add('gl');

/* ------------------------------------------------------------------ textures */
const texLoader = new THREE.TextureLoader();
const baseCache = new Map();
/** Load (once) and return a base texture. srgb for colour maps, linear for data maps. */
export function loadTexture(url, { srgb = false } = {}) {
  const key = url + (srgb ? '#s' : '#l');
  if (!baseCache.has(key)) baseCache.set(key, new Promise(res => {
    texLoader.load(url, t => {
      t.colorSpace = srgb ? THREE.SRGBColorSpace : THREE.NoColorSpace;
      t.wrapS = t.wrapT = THREE.RepeatWrapping;
      t.anisotropy = MAX_ANISO;
      t.generateMipmaps = true; t.minFilter = THREE.LinearMipmapLinearFilter;
      res(t);
    }, undefined, () => { console.warn('texture failed', url); res(null); });
  }));
  return baseCache.get(key);
}
const withRepeat = (t, rep, rot, off) => {
  if (!t) return null;
  const c = t.clone(); c.repeat.set(rep[0], rep[1]); if (rot) c.rotation = rot; if (off) c.offset.set(off[0], off[1]); c.needsUpdate = true; return c;
};
/** Scanned PBR set from assets/tex/<name>_{c,n,r}.webp. Returns { map, normalMap, roughnessMap, aoMap }.
    _r packs R = AO, G = roughness. Sets without _r return roughnessMap = aoMap = null. */
const HAS_ORM = new Set(['sugi', 'mahogany', 'darkwood', 'hinoki', 'deck', 'plaster']);
export async function pbrSet(name, { repeat = [1, 1], rotation = 0, offset = null } = {}) {
  const base = `assets/tex/${name}`;
  const [c, n, r] = await Promise.all([
    loadTexture(`${base}_c.webp`, { srgb: true }), loadTexture(`${base}_n.webp`),
    HAS_ORM.has(name) ? loadTexture(`${base}_r.webp`) : Promise.resolve(null),
  ]);
  return { map: withRepeat(c, repeat, rotation, offset), normalMap: withRepeat(n, repeat, rotation, offset), roughnessMap: withRepeat(r, repeat, rotation, offset), aoMap: withRepeat(r, repeat, rotation, offset) };
}
/** Convenience: a MeshStandardMaterial (or Physical with {physical:true}) from a scanned set.
    tint multiplies the albedo; roughness scales the packed map; normal is the normalScale. */
export async function pbrMaterial(name, { repeat = [1, 1], rotation = 0, tint = 0xffffff, roughness = 1, normal = 1, ao = 1, metalness = 0, envMapIntensity = 1, physical = false, ...extra } = {}) {
  const s = await pbrSet(name, { repeat, rotation });
  const M = physical ? THREE.MeshPhysicalMaterial : THREE.MeshStandardMaterial;
  const m = new M({ color: tint, map: s.map, normalMap: s.normalMap, normalScale: new THREE.Vector2(normal, normal), roughness, roughnessMap: s.roughnessMap, aoMap: s.aoMap, aoMapIntensity: s.aoMap ? ao : 0, metalness, envMapIntensity, ...extra });
  return m;
}

/* ------------------------------------------------------------------ environment (real sunset HDRI, PMREM) */
let envPromise = null;
/** Poly Haven belfast_sunset_puresky, prefiltered. Returns { texture (PMREM), equirect, sunDir }.
    sunDir is the direction toward the HDRI's sun in its native orientation (+x right, +y up, -z forward). */
export function loadEnv() {
  if (!envPromise) envPromise = new Promise(res => {
    new HDRLoader().setDataType(THREE.HalfFloatType).load('assets/hdr/belfast_sunset_puresky_2k.hdr', eq => {
      eq.mapping = THREE.EquirectangularReflectionMapping;
      const pm = new THREE.PMREMGenerator(renderer);
      const texture = pm.fromEquirectangular(eq).texture;
      pm.dispose();
      res({ texture, equirect: eq });
    }, undefined, () => { console.warn('hdr failed'); res({ texture: null, equirect: null }); });
  });
  return envPromise;
}

/* ------------------------------------------------------------------ warm paper studio (for product scenes on the page)
   The sunset HDRI is right outdoors, but on the paper it fills every shadow side lavender. Product scenes use this
   instead: a warm room the colour of the page, a big warm softbox upper-left (the key's direction), a dim warm
   fill right, a soft top strip and a peach rim behind. Prefiltered once and shared. */
let studioTex = null;
export function studioEnv() {
  if (studioTex) return studioTex;
  const sc = new THREE.Scene();
  const col = (hex, k = 1) => new THREE.Color(hex).multiplyScalar(k);
  const room = new THREE.Mesh(new THREE.BoxGeometry(20, 12, 20), new THREE.MeshBasicMaterial({ color: col(0xE9DCC6, .55), side: THREE.BackSide }));
  room.position.y = 4; sc.add(room);
  const floor = new THREE.Mesh(new THREE.PlaneGeometry(20, 20), new THREE.MeshBasicMaterial({ color: col(0xF3EADB, .8) }));
  floor.rotation.x = -Math.PI / 2; floor.position.y = -1.99; sc.add(floor);
  const box = (w, h, c, k, pos, look) => { const m = new THREE.Mesh(new THREE.PlaneGeometry(w, h), new THREE.MeshBasicMaterial({ color: col(c, k), side: THREE.DoubleSide })); m.position.set(...pos); m.lookAt(...look); sc.add(m); };
  box(7, 5, 0xFFE2C0, 9, [-6, 6, 5], [0, 0, 0]);      // key softbox, upper left front
  box(4, 6, 0xFFF1E2, 2.2, [8, 2.5, 3], [0, 0, 0]);   // fill, right
  box(12, 1.4, 0xFFF6EC, 3, [0, 9.8, 0], [0, 0, 0]);  // top strip
  box(8, 3, 0xFFC99A, 3.2, [2, 3, -9], [0, 0, 0]);    // peach rim behind
  const pm = new THREE.PMREMGenerator(renderer);
  studioTex = pm.fromScene(sc, .02).texture; pm.dispose();
  sc.traverse(o => { o.geometry?.dispose(); o.material?.dispose(); });
  return studioTex;
}

/* ------------------------------------------------------------------ small helpers for scene authors */
/** Canvas → texture. */
export function canvasTexture(cv, { srgb = true, repeat = null, aniso = true } = {}) {
  const t = new THREE.CanvasTexture(cv);
  t.colorSpace = srgb ? THREE.SRGBColorSpace : THREE.NoColorSpace;
  if (repeat) { t.wrapS = t.wrapT = THREE.RepeatWrapping; t.repeat.set(...repeat); }
  if (aniso) t.anisotropy = MAX_ANISO;
  return t;
}
export function makeCanvas(w, h) { const c = document.createElement('canvas'); c.width = w; c.height = h; return c; }
/** Yield to the event loop without waiting for a frame (rAF stalls in background tabs). */
export const yieldTask = (() => { const ch = new MessageChannel(), q = []; ch.port1.onmessage = () => q.shift()?.(); return () => new Promise(r => { q.push(r); ch.port2.postMessage(0); }); })();
