/* Shared procedural woods.
   hinokiTextures(): quarter-sawn hinoki — pale cream-ivory with a faint pink, fine straight grain, low contrast.
   Tiles seamlessly in both directions. The grain runs along v (texture y). One repeat covers `metres` of wood
   (default 0.3 m), so for UVs in metres set texture.repeat = 1 / metres (or use `perMetre(set, uvUnitsPerMetre)`).
   hinokiEndTextures(): the end grain (growth rings round a pith well off the piece) for end faces.

   const h = hinokiTextures({ seed: 3 });
   const mat = new THREE.MeshPhysicalMaterial({ map: h.map, normalMap: h.normalMap, roughnessMap: h.roughnessMap,
     roughness: 1, normalScale: new THREE.Vector2(.4, .4), clearcoat: .1, clearcoatRoughness: .5 });
   perMetre(h, 1);   // UVs in metres
   Maps are cached per option set; the returned textures are clones, so repeat/offset/rotation are yours to change. */
import { THREE, makeCanvas, rng, MAX_ANISO } from '../core.js';

const cache = new Map();
const srgbToLin = c => c <= .04045 ? c / 12.92 : ((c + .055) / 1.055) ** 2.4;

/** Periodic value noise on a W×H torus (lattice cells cx × cy). */
function periodicNoise(R, cx, cy) {
  const g = new Float32Array(cx * cy); for (let i = 0; i < g.length; i++) g[i] = R();
  return (u, v) => {   // u, v in [0,1)
    const x = u * cx, y = v * cy, x0 = Math.floor(x), y0 = Math.floor(y), fx = x - x0, fy = y - y0;
    const sx = fx * fx * (3 - 2 * fx), sy = fy * fy * (3 - 2 * fy);
    const i00 = g[((y0 % cy + cy) % cy) * cx + ((x0 % cx + cx) % cx)], i10 = g[((y0 % cy + cy) % cy) * cx + (((x0 + 1) % cx + cx) % cx)];
    const i01 = g[(((y0 + 1) % cy + cy) % cy) * cx + ((x0 % cx + cx) % cx)], i11 = g[(((y0 + 1) % cy + cy) % cy) * cx + (((x0 + 1) % cx + cx) % cx)];
    return (i00 * (1 - sx) + i10 * sx) * (1 - sy) + (i01 * (1 - sx) + i11 * sx) * sy;
  };
}

function finish(albedo, height, rough, size, { normalStrength }) {
  const mk = (data, srgb) => {
    const cv = makeCanvas(size, size), g = cv.getContext('2d'), img = g.createImageData(size, size); img.data.set(data); g.putImageData(img, 0, 0);
    const t = new THREE.CanvasTexture(cv); t.colorSpace = srgb ? THREE.SRGBColorSpace : THREE.NoColorSpace;
    t.wrapS = t.wrapT = THREE.RepeatWrapping; t.anisotropy = MAX_ANISO; t.generateMipmaps = true; t.minFilter = THREE.LinearMipmapLinearFilter;
    return t;
  };
  const n = new Uint8ClampedArray(size * size * 4), r = new Uint8ClampedArray(size * size * 4);
  for (let y = 0; y < size; y++) for (let x = 0; x < size; x++) {
    const i = y * size + x, H = (xx, yy) => height[((yy + size) % size) * size + ((xx + size) % size)];
    const dx = (H(x + 1, y) - H(x - 1, y)) * normalStrength, dy = (H(x, y + 1) - H(x, y - 1)) * normalStrength, l = Math.hypot(dx, dy, 1);
    n[i * 4] = (-dx / l * .5 + .5) * 255; n[i * 4 + 1] = (dy / l * .5 + .5) * 255; n[i * 4 + 2] = (1 / l * .5 + .5) * 255; n[i * 4 + 3] = 255;
    r[i * 4] = 255; r[i * 4 + 1] = rough[i] * 255; r[i * 4 + 2] = 0; r[i * 4 + 3] = 255;   // R = AO (none), G = roughness (pbrSet convention)
  }
  return { map: mk(albedo, true), normalMap: mk(n, false), roughnessMap: mk(r, false) };
}
const clone = s => { const o = {}; for (const k in s) o[k] = s[k]?.isTexture ? s[k].clone() : s[k]; for (const k in o) if (o[k]?.isTexture) o[k].needsUpdate = true; return o; };

/** Quarter-sawn hinoki side grain. ringSpacing: mean latewood-line spacing in mm. contrast: 0..1 (latewood darkening). */
export function hinokiTextures({ seed = 1, size = 1024, metres = .3, ringSpacing = 2.6, contrast = .32, tint = [238, 219, 200], late = [205, 170, 140], normalStrength = 1.4 } = {}) {
  const key = JSON.stringify(['side', seed, size, metres, ringSpacing, contrast, tint, late, normalStrength]);
  if (!cache.has(key)) {
    const R = rng(seed * 7919 + 13), N = size, pxPerMm = N / (metres * 1000);
    // ring boundaries across x: variable widths (narrow and wide growth years), rescaled to tile exactly
    const widths = []; let tot = 0;
    while (tot < N) { const w = ringSpacing * pxPerMm * (.55 + R() * .9) * (R() < .12 ? 1.6 : 1); widths.push(w); tot += w; }
    const k = N / tot; let acc = 0; const bounds = widths.map(w => (acc += w * k));   // right edge of each ring
    const lateW = widths.map(() => .16 + R() * .14), lateK = widths.map(() => .6 + R() * .4);
    const wobA = periodicNoise(R, 3, 2), wobB = periodicNoise(R, 7, 5);
    const fibA = periodicNoise(R, Math.round(N / 2.2), Math.round(N / 60)), fibB = periodicNoise(R, Math.round(N / 6), Math.round(N / 150));
    const band = periodicNoise(R, 6, 2), pinkN = periodicNoise(R, 4, 3);
    const E = tint.map(c => srgbToLin(c / 255)), L = late.map(c => srgbToLin(c / 255));
    const albedo = new Uint8ClampedArray(N * N * 4), height = new Float32Array(N * N), rough = new Float32Array(N * N);
    for (let y = 0; y < N; y++) {
      const v = y / N;
      for (let x = 0; x < N; x++) {
        const u = x / N;
        // the grain drifts gently along its length (straight, not cathedral)
        let xs = x + (wobA(u, v) - .5) * 7 * pxPerMm + (wobB(u, v) - .5) * 1.2 * pxPerMm;
        xs = ((xs % N) + N) % N;
        let ri = 0; while (ri < bounds.length - 1 && bounds[ri] < xs) ri++;
        const x0 = ri ? bounds[ri - 1] : 0, t = (xs - x0) / (bounds[ri] - x0);   // 0 earlywood start .. 1 latewood end
        const lw = lateW[ri], ramp = Math.min(1, Math.max(0, (t - (1 - lw)) / lw));
        const lat = (ramp * ramp * (3 - 2 * ramp)) * lateK[ri] * (t < .985 ? 1 : 1 - (t - .985) / .015);
        const fib = fibA(u, v) * .65 + fibB(u, v) * .35, bd = band(u, v), pk = pinkN(u, v);
        const m = lat * contrast * 2.2;
        const sh = .95 + (fib - .5) * .09 + (bd - .5) * .06;
        const i = y * N + x;
        const c = [0, 1, 2].map(j => (E[j] + (L[j] - E[j]) * Math.min(1, m)) * sh);
        c[0] *= 1 + (pk - .5) * .04; c[2] *= 1 - (pk - .5) * .03;   // a faint pink drift
        for (let j = 0; j < 3; j++) albedo[i * 4 + j] = Math.round(255 * Math.pow(Math.max(0, Math.min(1, c[j])), 1 / 2.2));
        albedo[i * 4 + 3] = 255;
        height[i] = -lat * .5 + (fib - .5) * .35;
        rough[i] = .62 - lat * .08 + (fib - .5) * .06;
      }
    }
    cache.set(key, finish(albedo, height, rough, N, { normalStrength }));
  }
  const out = clone(cache.get(key)); out.metres = metres; return out;
}

/** Hinoki end grain: growth rings round a pith well off the piece, fine pores. */
export function hinokiEndTextures({ seed = 1, size = 512, metres = .12, ringSpacing = 2.6, contrast = .45, tint = [226, 200, 176], late = [188, 150, 120], pith = null /* [x, y] in tile units, e.g. [-.4, 1.2] */ } = {}) {
  const key = JSON.stringify(['end', seed, size, metres, ringSpacing, contrast, tint, late, pith]);
  if (!cache.has(key)) {
    const R = rng(seed * 104729 + 7), N = size, pxPerMm = N / (metres * 1000);
    let px = -N * (.6 + R() * .5), py = N * (1.3 + R() * .5);
    if (pith) { px = pith[0] * N; py = pith[1] * N; }
    const wob = periodicNoise(R, 5, 5), pore = periodicNoise(R, N / 2, N / 2), fibA = periodicNoise(R, 24, 24);
    const E = tint.map(c => srgbToLin(c / 255)), L = late.map(c => srgbToLin(c / 255));
    const albedo = new Uint8ClampedArray(N * N * 4), height = new Float32Array(N * N), rough = new Float32Array(N * N);
    for (let y = 0; y < N; y++) for (let x = 0; x < N; x++) {
      const u = x / N, v = y / N, i = y * N + x;
      const r = Math.hypot(x - px, y - py) + (wob(u, v) - .5) * 4 * pxPerMm;
      const t = (r / (ringSpacing * pxPerMm)) % 1;
      const lat = t > .78 ? Math.min(1, (t - .78) / .16) * (t < .97 ? 1 : 1 - (t - .97) / .03) : 0;
      const p = pore(u, v), sh = .92 + (fibA(u, v) - .5) * .08 - (p > .8 ? (p - .8) * .6 : 0);
      for (let j = 0; j < 3; j++) albedo[i * 4 + j] = Math.round(255 * Math.pow(Math.max(0, Math.min(1, (E[j] + (L[j] - E[j]) * lat * contrast * 2) * sh)), 1 / 2.2));
      albedo[i * 4 + 3] = 255;
      height[i] = -lat * .3 - (p > .8 ? (p - .8) : 0);
      rough[i] = .78;
    }
    cache.set(key, finish(albedo, height, rough, N, { normalStrength: 1.2 }));
  }
  const out = clone(cache.get(key)); out.metres = metres; return out;
}

/** Set every map's repeat for UVs measured in `uvPerMetre` units per metre (1 for UVs in metres, 100 for cm). */
export function perMetre(set, uvPerMetre = 1, { rotation = 0, offset = null } = {}) {
  for (const k of ['map', 'normalMap', 'roughnessMap', 'aoMap']) {
    const t = set[k]; if (!t?.isTexture) continue;
    t.repeat.set(1 / (set.metres * uvPerMetre), 1 / (set.metres * uvPerMetre)); t.rotation = rotation; if (offset) t.offset.set(...offset); t.needsUpdate = true;
  }
  return set;
}
