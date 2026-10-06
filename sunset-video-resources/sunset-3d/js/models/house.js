/* Sunset — the house (agent A). A modern Japanese minka, ~11 m wide with its eaves, ridge ~6 m, front (+z), ground y = 0.
   Two-tier roof: a kirizuma main roof in smoked ibushi kawara (instanced tiles, noshi ridge, onigawara) carrying the solar
   array flush on the front slope, and a standing-seam hisashi over a hinoki engawa with glowing shoji behind it.
   Granite plinth, dark timber frame, silver-grey sugi board-and-batten, warm shikkui plaster, a hinoki battery cabinet.

   export async function buildHouse({ env, detail:'high'|'mid', panels:true, glow:0, seed:1, apron:true })
     -> { group, panels[], rails, setGlow(v), anchors:{ roof, battery, meter }, bounds, sunCatchers[], dims }

   Also exports a small geometry kit (K) and stone/moss materials that garden.js and the scenes reuse.
   Every textured piece carries UVs in metres (texel density from the material's metres-per-repeat), a per-vertex
   albedo tint and a per-vertex `ao` attribute that only darkens indirect light (sky fill), so contact and eave
   occlusion never fight the sun's shadow map. */
import { THREE, pbrMaterial, canvasTexture, makeCanvas, rng, clamp, lerp } from '../core.js';
import { mergeGeometries, mergeVertices } from 'three/addons/utils/BufferGeometryUtils.js';
import { RoundedBoxGeometry } from 'three/addons/geometries/RoundedBoxGeometry.js';

const deg = Math.PI / 180;
const _m = new THREE.Matrix4(), _q = new THREE.Quaternion(), _e = new THREE.Euler(), _v = new THREE.Vector3(), _s = new THREE.Vector3(1, 1, 1);

/* =================================================================== geometry kit */
/** UVs in metres from local position, grain (texture v) along `grain` when that axis lies in the face. */
export function metreUV(g, grain = 'y', off = [0, 0]) {
  const P = g.attributes.position, N = g.attributes.normal, n = P.count;
  const uv = new Float32Array(n * 2), gi = 'xyz'.indexOf(grain);
  for (let i = 0; i < n; i++) {
    const ax = Math.abs(N.getX(i)), ay = Math.abs(N.getY(i)), az = Math.abs(N.getZ(i));
    const a = ax > ay ? (ax > az ? 0 : 2) : (ay > az ? 1 : 2);
    const o = [0, 1, 2].filter(k => k !== a);
    let ua, va;
    if (o.includes(gi)) { va = gi; ua = o[0] === gi ? o[1] : o[0]; } else { ua = o[0]; va = o[1]; }
    const p = [P.getX(i), P.getY(i), P.getZ(i)];
    uv[i * 2] = p[ua] + off[0]; uv[i * 2 + 1] = p[va] + off[1];
  }
  g.setAttribute('uv', new THREE.BufferAttribute(uv, 2));
  return g;
}
/** Centred box with metre UVs. o: { grain, off, seg:[sx,sy,sz] } */
export function box(w, h, d, o = {}) {
  const s = o.seg || [1, 1, 1];
  const g = new THREE.BoxGeometry(w, h, d, s[0], s[1], s[2]);
  return metreUV(g, o.grain || 'y', o.off || [0, 0]);
}
/** Transform in place: position, euler rotation (radians), optional scale. */
export function place(g, p = [0, 0, 0], r = [0, 0, 0], s = null, order = 'XYZ') {
  _e.set(r[0], r[1], r[2], order); _q.setFromEuler(_e);
  _m.compose(_v.set(p[0], p[1], p[2]), _q, s ? _s.set(s[0], s[1], s[2]) : _s.set(1, 1, 1));
  g.applyMatrix4(_m); return g;
}
/** Per-vertex albedo tint (linear rgb) and sky-occlusion `ao` from a field fn(x,y,z,nx,ny,nz) evaluated where it now sits. */
export function paint(g, col = [1, 1, 1], ao = null, mtx = null) {
  const P = g.attributes.position, N = g.attributes.normal, n = P.count;
  const c = new Float32Array(n * 3), a = new Float32Array(n);
  const p = new THREE.Vector3(), q = new THREE.Vector3(), nm = mtx ? new THREE.Matrix3().getNormalMatrix(mtx) : null;
  for (let i = 0; i < n; i++) {
    c[i * 3] = col[0]; c[i * 3 + 1] = col[1]; c[i * 3 + 2] = col[2];
    if (ao) {
      p.fromBufferAttribute(P, i); q.fromBufferAttribute(N, i);
      if (mtx) { p.applyMatrix4(mtx); q.applyMatrix3(nm).normalize(); }
      a[i] = clamp(ao(p.x, p.y, p.z, q.x, q.y, q.z), .05, 1);
    } else a[i] = 1;
  }
  g.setAttribute('color', new THREE.BufferAttribute(c, 3));
  g.setAttribute('ao', new THREE.BufferAttribute(a, 1));
  return g;
}
const KEEP = ['position', 'normal', 'uv', 'color', 'ao'];
/** Collects geometries per material key and merges them into one mesh each. */
export class Bucket {
  constructor() { this.m = new Map(); }
  add(key, g) {
    if (!g.index) { const n = g.attributes.position.count; g.setIndex(Array.from({ length: n }, (_, i) => i)); }
    if (!g.attributes.uv) g.setAttribute('uv', new THREE.BufferAttribute(new Float32Array(g.attributes.position.count * 2), 2));
    if (!g.attributes.color || !g.attributes.ao) paint(g);
    for (const k of Object.keys(g.attributes)) if (!KEEP.includes(k)) g.deleteAttribute(k);
    g.clearGroups();
    if (!this.m.has(key)) this.m.set(key, []);
    this.m.get(key).push(g); return g;
  }
  mesh(key, mat, { cast = true, receive = true, name = key } = {}) {
    const list = this.m.get(key); if (!list || !list.length) return null;
    const g = mergeGeometries(list); g.computeBoundingSphere(); g.computeBoundingBox();
    const mesh = new THREE.Mesh(g, mat); mesh.castShadow = cast; mesh.receiveShadow = receive; mesh.name = name;
    return mesh;
  }
}

/* seeded 3-D value noise for shaping rocks */
export function noise3(seed) {
  const h = (x, y, z) => { let n = (x * 374761393 + y * 668265263 + z * 1274126177 + seed * 2654435761) | 0; n = Math.imul(n ^ (n >>> 13), 1274126177); return ((n ^ (n >>> 16)) >>> 0) / 4294967296; };
  const sm = t => t * t * (3 - 2 * t);
  const vn = (x, y, z) => {
    const xi = Math.floor(x), yi = Math.floor(y), zi = Math.floor(z), xf = sm(x - xi), yf = sm(y - yi), zf = sm(z - zi);
    const L = (a, b, t) => a + (b - a) * t;
    return L(L(L(h(xi, yi, zi), h(xi + 1, yi, zi), xf), L(h(xi, yi + 1, zi), h(xi + 1, yi + 1, zi), xf), yf),
             L(L(h(xi, yi, zi + 1), h(xi + 1, yi, zi + 1), xf), L(h(xi, yi + 1, zi + 1), h(xi + 1, yi + 1, zi + 1), xf), yf), zf);
  };
  return (x, y, z, oct = 3) => { let a = 0, w = .5, f = 1, s = 0; for (let i = 0; i < oct; i++) { a += w * vn(x * f, y * f, z * f); s += w; w *= .5; f *= 2.03; } return a / s; };
}

/** A flat-topped natural slab (stepping stone, shoe stone, post pad): an irregular outline, a slightly domed and
    pitted top, rounded arrises, sides that flare into the ground. Top at y = 0, `h` deep. */
export function flatStone(seed, r, h = .16, stretch = [1.15, .9]) {
  let g = new THREE.IcosahedronGeometry(1, 4); g.deleteAttribute('normal'); g.deleteAttribute('uv'); g = mergeVertices(g);
  const n = noise3(seed), P = g.attributes.position, v = new THREE.Vector3();
  for (let i = 0; i < P.count; i++) {
    v.fromBufferAttribute(P, i);
    const a = Math.atan2(v.z, v.x), wob = 1 + (n(Math.cos(a) * 1.4 + 2, Math.sin(a) * 1.4, 0, 3) - .5) * .55;
    const top = v.y > 0, y = top ? (1 - Math.pow(1 - v.y, 5)) : v.y;                      // flatten the upper cap into a table
    const rr = Math.hypot(v.x, v.z) * wob;
    const pit = (n(v.x * 6, v.y * 6, v.z * 6, 2) - .5) * .012;
    P.setXYZ(i, v.x / Math.max(1e-4, Math.hypot(v.x, v.z)) * rr * r * stretch[0] * Math.min(1, Math.hypot(v.x, v.z) * 1.4),
      top ? .025 * (1 - Math.pow(Math.hypot(v.x, v.z), 4)) + pit : y * h,
      v.z / Math.max(1e-4, Math.hypot(v.x, v.z)) * rr * r * stretch[1] * Math.min(1, Math.hypot(v.x, v.z) * 1.4));
  }
  g.computeVertexNormals();
  return g;
}


/* =================================================================== materials */
const GLSL_NOISE = /* glsl */`
float kh13(vec3 p){ p = fract(p * .1031); p += dot(p, p.zyx + 31.32); return fract((p.x + p.y) * p.z); }
float kvn(vec3 p){ vec3 i = floor(p), f = fract(p); f = f * f * (3. - 2. * f);
  return mix(mix(mix(kh13(i), kh13(i + vec3(1,0,0)), f.x), mix(kh13(i + vec3(0,1,0)), kh13(i + vec3(1,1,0)), f.x), f.y),
             mix(mix(kh13(i + vec3(0,0,1)), kh13(i + vec3(1,0,1)), f.x), mix(kh13(i + vec3(0,1,1)), kh13(i + vec3(1,1,1)), f.x), f.y), f.z); }
float kfbm(vec3 p){ float a = 0., w = .5; for (int i = 0; i < 4; i++) { a += w * kvn(p); p = p * 2.07 + 13.7; w *= .5; } return a / .9375; }`;


/** Warm rim light from the key (the first, shadow-casting directional light): silhouette edges seen against the light
    glow, as they do when the sun is behind a subject. `u` is a { value: Vector2(strength, power) } uniform that a scene
    can drive (0 = off). Uses the key's own shadow, so edges in cast shadow stay dark. Call inside onBeforeCompile. */
export function rimGLSL(sh, u, { tint = [1, .82, .62], grey = .45 } = {}) {
  sh.uniforms.uRim = u;
  sh.fragmentShader = sh.fragmentShader.replace('#include <common>', '#include <common>\nuniform vec2 uRim;')
    .replace('#include <lights_fragment_end>', `#include <lights_fragment_end>
      #if NUM_DIR_LIGHTS > 0
      if (uRim.x > 0.) {
        vec3 rL = directionalLights[0].direction, rC = directionalLights[0].color;
        float rSh = 1.;
        #if defined(USE_SHADOWMAP) && NUM_DIR_LIGHT_SHADOWS > 0
          DirectionalLightShadow rS = directionalLightShadows[0];
          rSh = receiveShadow ? getShadow(directionalShadowMap[0], rS.shadowMapSize, rS.shadowIntensity, rS.shadowBias, rS.shadowRadius, vDirectionalShadowCoord[0]) : 1.;
        #endif
        float rEdge = pow(1. - clamp(dot(geometryNormal, geometryViewDir), 0., 1.), uRim.y);
        float rBack = pow(clamp(dot(-geometryViewDir, rL), 0., 1.), 1.5);
        float rFace = clamp(dot(geometryNormal, rL) + .35, 0., 1.);
        reflectedLight.directDiffuse += rC * rSh * mix(material.diffuseColor, vec3(.35), ${(+grey).toFixed(3)}) * vec3(${tint.map(v => (+v).toFixed(3)).join(',')}) * uRim.x * rEdge * rBack * rFace;
      }
      #endif`);
}
export const RIM_OFF = () => ({ value: new THREE.Vector2(0, 3) });
/** Set the rim strength/power on every material under `obj` that carries a rim uniform (0 turns it off). */
export function setRim(obj, k = 1, p = 3) {
  obj.traverse(o => { const ms = o.material ? (Array.isArray(o.material) ? o.material : [o.material]) : []; for (const m of ms) m.userData?.rim?.value.set(k, p); });
}


/** Alpha-tested foliage texture from a canvas or image: every transparent texel takes the alpha-weighted colour of its
    neighbourhood (so mip levels never pull black or key-colour into the cut-out edge, which reads as a pale or dark
    halo), green key spill is removed from the soft edge, and the result is uploaded as a mipmapped sRGB DataTexture
    (a canvas can't hold colour under zero alpha). v is up, as with a CanvasTexture. */
export function bledTexture(src, { radii = [2, 6, 16], despill = false } = {}) {
  const W = src.width, H = src.height, c = makeCanvas(W, H), g = c.getContext('2d', { willReadFrequently: true });
  g.drawImage(src, 0, 0); const base = g.getImageData(0, 0, W, H).data;
  const fills = radii.map(r => { g.clearRect(0, 0, W, H); g.filter = `blur(${r}px)`; g.drawImage(src, 0, 0); g.filter = 'none'; return g.getImageData(0, 0, W, H).data; });
  const out = new Uint8Array(W * H * 4);
  for (let y = 0; y < H; y++) {
    const row = (H - 1 - y) * W;
    for (let x = 0; x < W; x++) {
      const i = (row + x) * 4, o = (y * W + x) * 4, a = base[i + 3];
      let r = base[i], gg = base[i + 1], b = base[i + 2];
      if (a < 250) {
        let f = null; for (const F of fills) if (F[i + 3] > 2) { f = F; break; }
        const w = a / 255;
        if (f) { r = r * w + f[i] * (1 - w); gg = gg * w + f[i + 1] * (1 - w); b = b * w + f[i + 2] * (1 - w); }
        if (despill) gg = Math.min(gg, Math.max(r, b));
      }
      out[o] = r; out[o + 1] = gg; out[o + 2] = b; out[o + 3] = a;
    }
  }
  const t = new THREE.DataTexture(out, W, H, THREE.RGBAFormat);
  t.colorSpace = THREE.SRGBColorSpace; t.wrapS = t.wrapT = THREE.ClampToEdgeWrapping;
  t.generateMipmaps = true; t.minFilter = THREE.LinearMipmapLinearFilter; t.magFilter = THREE.LinearFilter; t.anisotropy = 4; t.needsUpdate = true;
  return t;
}

/** Adds: saturation/gain on the scanned albedo, the per-vertex `ao` on indirect light, optional custom hooks. */
export function tune(m, { sat = 1, gain = 1, key = '', vao = true, extra = null } = {}) {
  m.vertexColors = true;
  m.userData.rim = m.userData.rim || RIM_OFF();
  const prev = m.onBeforeCompile;
  m.onBeforeCompile = (sh, r) => {
    if (vao) {
      sh.vertexShader = sh.vertexShader.replace('#include <common>', '#include <common>\nattribute float ao; varying float vAO;')
        .replace('#include <begin_vertex>', '#include <begin_vertex>\nvAO = ao;');
      sh.fragmentShader = sh.fragmentShader.replace('#include <common>', '#include <common>\nvarying float vAO;')
        .replace('#include <aomap_fragment>', '#include <aomap_fragment>\nreflectedLight.indirectDiffuse *= vAO; reflectedLight.indirectSpecular *= mix(1., vAO, .85);');
    }
    if (sat !== 1 || gain !== 1) sh.fragmentShader = sh.fragmentShader.replace('#include <map_fragment>',
      `#include <map_fragment>\n diffuseColor.rgb = mix(vec3(dot(diffuseColor.rgb, vec3(.2126,.7152,.0722))), diffuseColor.rgb, ${sat.toFixed(3)}) * ${gain.toFixed(3)};`);
    rimGLSL(sh, m.userData.rim);
    extra?.(sh, r);
    prev?.(sh, r);
  };
  m.customProgramCacheKey = () => `tune:${key}:${sat}:${gain}:${vao}:rim`;
  return m;
}

/** Procedural granite / garden stone: speckled grey with lichen and optional moss on up-facing surfaces. */
export function stoneMaterial({ tint = [.19, .185, .175], moss = 0, lichen = .5, scale = 1, key = 'stone', rough = .82 } = {}) {
  const m = new THREE.MeshStandardMaterial({ color: new THREE.Color(1, 1, 1), roughness: rough, metalness: 0 });
  m.userData.u = { uMoss: { value: moss } };
  tune(m, {
    key: key + moss, extra: sh => {
      Object.assign(sh.uniforms, m.userData.u);
      sh.vertexShader = sh.vertexShader.replace('#include <common>', '#include <common>\nvarying vec3 vSP; varying vec3 vSN;')
        .replace('#include <begin_vertex>', `#include <begin_vertex>\n vSP = (modelMatrix * vec4(position, 1.)).xyz * ${scale.toFixed(3)}; vSN = normalize(mat3(modelMatrix) * normal);`);
      sh.fragmentShader = sh.fragmentShader.replace('#include <common>', `#include <common>\nvarying vec3 vSP; varying vec3 vSN; uniform float uMoss;\n${GLSL_NOISE}`)
        .replace('#include <map_fragment>', `#include <map_fragment>
          float big = kfbm(vSP * 1.3), mid = kfbm(vSP * 5.1 + 3.), fine = kvn(vSP * 55.), fine2 = kvn(vSP * 140. + 7.);
          vec3 base = vec3(${tint.map(v => v.toFixed(3)).join(',')});
          vec3 col = base * (.72 + .55 * big) * (.86 + .28 * mid);
          col *= mix(1., .72, smoothstep(.78, .93, fine)) * mix(1., 1.18, smoothstep(.82, .96, fine2));
          float li = smoothstep(.56, .7, kfbm(vSP * 2.3 + 11.)) * ${lichen.toFixed(3)};
          col = mix(col, vec3(.28, .27, .2), li * .55);
          float up = smoothstep(.35, .9, vSN.y);
          float ms = uMoss * up * smoothstep(.35, .6, kfbm(vSP * 1.7 + 5.) + up * .25);
          col = mix(col, vec3(.035, .055, .014) * (.7 + .6 * mid), ms);
          diffuseColor.rgb *= col;
          float sRough = mix(.95, .78, smoothstep(.72, .9, fine)) - li * .05 + ms * .1;`)
        .replace('#include <roughnessmap_fragment>', '#include <roughnessmap_fragment>\n roughnessFactor = clamp(sRough, .3, 1.);')
        .replace('#include <normal_fragment_maps>', `#include <normal_fragment_maps>
          { vec3 e = vec3(.012, 0., 0.); float h0 = kfbm(vSP * 6.), hx = kfbm((vSP + e.xyy) * 6.), hy = kfbm((vSP + e.yxy) * 6.), hz = kfbm((vSP + e.yyx) * 6.);
            vec3 gw = vec3(hx - h0, hy - h0, hz - h0) / e.x * .018;
            vec3 gv = mat3(viewMatrix) * gw; normal = normalize(normal - (gv - dot(gv, normal) * normal)); }`);
    },
  });
  return m;
}


/** Thin translucent foliage (petals, needles, leaves): every punctual light (sun, moon, lantern point/spot) also
    transmits through the card, strongest when the viewer looks toward the light. Wraps three's RE_Direct, so it is
    shadowed by the same shadow maps as the direct term. `floor` adds light scattered through the whole crown from the
    first directional light (unshadowed), scaled by an optional per-vertex `vShade` the host shader provides.
    Call from inside an onBeforeCompile with the shader object. */
export function translucencyGLSL(sh, { tint = [1, 1, 1], k = 1, floor = 0, warmCool = false, shade = false } = {}) {
  const T = `vec3(${tint.map(v => (+v).toFixed(3)).join(',')})`;
  sh.fragmentShader = sh.fragmentShader
    .replace('#include <lights_physical_pars_fragment>', `#include <lights_physical_pars_fragment>
      varying vec3 vTrW;
      void RE_Direct_Thin(const in IncidentLight directLight, const in vec3 geometryPosition, const in vec3 geometryNormal, const in vec3 geometryViewDir, const in vec3 geometryClearcoatNormal, const in PhysicalMaterial material, inout ReflectedLight reflectedLight) {
        RE_Direct_Physical(directLight, geometryPosition, geometryNormal, geometryViewDir, geometryClearcoatNormal, material, reflectedLight);
        vec3 L = directLight.direction;
        float back = max(dot(-geometryNormal, L), 0.) * .55 + .45;
        float fwd = pow(max(dot(-geometryViewDir, L), 0.), 3.);
        vec3 wc = ${warmCool ? 'mix(vec3(1.14, .94, .88), vec3(.93, .97, 1.07), clamp(vTrW.y * .5 + .5, 0., 1.))' : 'vec3(1.)'};
        reflectedLight.directDiffuse += directLight.color * material.diffuseColor * ${T} * wc * ${(+k).toFixed(3)} * back * (.18 + 1.1 * fwd) * RECIPROCAL_PI;
      }
      #undef RE_Direct
      #define RE_Direct RE_Direct_Thin`)
    .replace('#include <lights_fragment_end>', `#include <lights_fragment_end>
      #if NUM_DIR_LIGHTS > 0 && ${floor > 0 ? 1 : 0}
      { vec3 L = directionalLights[0].direction, C = directionalLights[0].color;
        float fwd = pow(max(dot(-geometryViewDir, L), 0.), 3.);
        reflectedLight.directDiffuse += C * material.diffuseColor * ${T} * ${(+floor * k).toFixed(3)} * (${shade ? '(.25 * vShade + .75) * vTrans' : '.35'}) * (.15 + 1.1 * fwd) * RECIPROCAL_PI; }
      #endif`);
  sh.vertexShader = sh.vertexShader.replace('#include <common>', '#include <common>\nvarying vec3 vTrW;')
    .replace('#include <beginnormal_vertex>', '#include <beginnormal_vertex>\n vTrW = normalize(mat3(modelMatrix) * objectNormal);');
}

const lin = hex => new THREE.Color(hex);   // THREE.Color from hex is sRGB -> linear working space
async function makeMaterials() {
  const [sugi, soffit, dark, hinoki, plaster, stoneBand, pebble] = await Promise.all([
    pbrMaterial('sugi', { repeat: [1 / 1.1, 1 / 1.1], normal: 1.15, roughness: 1 }),
    pbrMaterial('sugi', { repeat: [1 / 1.1, 1 / 1.1], normal: .6, roughness: 1 }),
    pbrMaterial('darkwood', { repeat: [1 / .9, 1 / .9], normal: .9, roughness: .95 }),
    pbrMaterial('hinoki', { repeat: [1 / .85, 1 / .85], normal: .7, roughness: .8 }),
    pbrMaterial('plaster', { repeat: [1 / 1.6, 1 / 1.6], normal: .35, roughness: 1 }),
    pbrMaterial('japanese_stone_wall', { repeat: [1 / 2.4, 1 / 2.4], normal: 1, roughness: .9 }),
    pbrMaterial('ganges_river_pebbles', { repeat: [1 / .55, 1 / .55], normal: 1.2, roughness: .85 }),
  ]);
  // weathered cedar: silver-grey, the brown scan pulled toward grey
  tune(sugi, { key: 'sugi', sat: .16, gain: 1.35 }); sugi.color.setRGB(1.0, 1.0, 1.04);
  tune(soffit, { key: 'soffit', sat: .42, gain: 1.9 }); soffit.color.setRGB(1, .97, .92);
  tune(dark, { key: 'dark', sat: .85, gain: .78 });
  tune(hinoki, { key: 'hinoki', sat: .5, gain: .92 }); hinoki.color.setRGB(1, .95, .86);
  tune(plaster, { key: 'plaster', sat: .45, gain: 1.72 }); plaster.color.setRGB(1, .975, .94);
  tune(stoneBand, { key: 'stoneBand', sat: .35, gain: 4.6 }); stoneBand.color.setRGB(1, .98, .95);
  tune(pebble, { key: 'pebble', sat: .5, gain: 2.2 });
  const tile = new THREE.MeshStandardMaterial({ color: lin(0x5c5f65), metalness: .22, roughness: .42, envMapIntensity: 1.05 });
  tile.userData.rim = RIM_OFF(); tile.onBeforeCompile = sh => rimGLSL(sh, tile.userData.rim); tile.customProgramCacheKey = () => 'kawara-rim';
  const tileV = tile.clone(); tileV.vertexColors = true; tileV.userData.rim = tile.userData.rim;
  tileV.onBeforeCompile = sh => {
    rimGLSL(sh, tile.userData.rim);
    // the butt/lap shading is sub-tile detail: fade it out once a tile is only a few pixels, or it aliases into a dotted grid
    sh.fragmentShader = sh.fragmentShader.replace('#include <color_fragment>', `
      { float px = length(fwidth(vViewPosition)); float fade = smoothstep(.012, .035, px);
        diffuseColor.rgb *= mix(vColor.rgb, vec3(.8), fade) * vec3(vColor.a > -1. ? 1. : 1.); }`);
  };
  tileV.customProgramCacheKey = () => 'kawara-rim-v2';
  const seam = new THREE.MeshStandardMaterial({ color: lin(0x34363a), metalness: .6, roughness: .34 }); tune(seam, { key: 'seam' });
  const blackMetal = new THREE.MeshStandardMaterial({ color: lin(0x17181b), metalness: .7, roughness: .38 }); tune(blackMetal, { key: 'blackMetal' });
  const frameMetal = new THREE.MeshStandardMaterial({ color: lin(0x55595f), metalness: .85, roughness: .3 }); tune(frameMetal, { key: 'frameMetal' });
  const greyMetal = new THREE.MeshStandardMaterial({ color: lin(0x8d9094), metalness: .55, roughness: .42 }); tune(greyMetal, { key: 'greyMetal' });
  const meterBody = new THREE.MeshStandardMaterial({ color: lin(0xc9c6bf), metalness: 0, roughness: .55 }); tune(meterBody, { key: 'meter' });
  const whitePlaster = plaster;   // ridge menado
  const void_ = new THREE.MeshStandardMaterial({ color: lin(0x0d0b0a), roughness: 1 }); tune(void_, { key: 'void' });
  const stone = stoneMaterial({ key: 'hstone', moss: .35, tint: [.13, .126, .118] });
  // shoji paper: bright washi, emissive from the room light (setGlow)
  const paperTex = canvasTexture(washiCanvas(), { repeat: [1, 1] });
  const paper = new THREE.MeshStandardMaterial({ color: lin(0xf2ece0), map: paperTex, roughness: .9, emissive: new THREE.Color(1, .56, .24), emissiveMap: paperTex, emissiveIntensity: 0 });
  tune(paper, { key: 'paper', extra: sh => {
    sh.vertexShader = sh.vertexShader.replace('#include <common>', '#include <common>\nvarying vec3 vPW;').replace('#include <begin_vertex>', '#include <begin_vertex>\n vPW = position;');
    sh.fragmentShader = sh.fragmentShader.replace('#include <common>', '#include <common>\nvarying vec3 vPW;')
      .replace('#include <emissivemap_fragment>', `#include <emissivemap_fragment>
        { // an andon standing inside each bay: a soft hotspot ~0.8 m up, falling off toward the frame and the kamoi
          float bx = fract((vPW.x + 4.8) / 1.92) - .5;
          float hot = .55 + .75 * exp(-bx * bx / .06) * exp(-pow(vPW.y - 1.15, 2.) / .45);
          totalEmissiveRadiance *= vColor.rgb * hot; }`); } });
  const led = new THREE.MeshBasicMaterial({ color: new THREE.Color(.25, 2.2, .9) });
  return { sugi, soffit, dark, hinoki, plaster, stoneBand, pebble, tile, tileV, seam, blackMetal, frameMetal, greyMetal, meterBody, whitePlaster, void: void_, stone, paper, led };
}

function washiCanvas() {
  const c = makeCanvas(512, 512), g = c.getContext('2d'), r = rng(9);
  g.fillStyle = '#f4efe6'; g.fillRect(0, 0, 512, 512);
  for (let i = 0; i < 2600; i++) { // long paper fibres
    g.strokeStyle = `rgba(${r() < .5 ? '255,255,255' : '205,195,178'},${.05 + r() * .12})`; g.lineWidth = .5 + r();
    const x = r() * 512, y = r() * 512, a = r() * 6.28, l = 6 + r() * 26;
    g.beginPath(); g.moveTo(x, y); g.quadraticCurveTo(x + Math.cos(a) * l * .5 + r() * 4, y + Math.sin(a) * l * .5, x + Math.cos(a) * l, y + Math.sin(a) * l); g.stroke();
  }
  return c;
}

/* solar cell texture: all-black half-cut mono panel, 20 x 6 half-cells in landscape, faint busbars */
let _cellTex = null;
function cellTexture() {
  if (_cellTex) return _cellTex;
  const W = 2048, H = 1205, c = makeCanvas(W, H), g = c.getContext('2d'), r = rng(5);
  const rC = makeCanvas(W, H), rg = rC.getContext('2d');   // roughness: cells glossy, gaps a touch rougher
  g.fillStyle = '#2a2f38'; g.fillRect(0, 0, W, H); rg.fillStyle = '#8a8a8a'; rg.fillRect(0, 0, W, H);
  const mx = 18, my = 16, cols = 20, rows = 6, gap = 7, mid = 18;
  const cw = (W - 2 * mx - (cols - 1) * gap - mid) / cols, ch = (H - 2 * my - (rows - 1) * gap) / rows;
  for (let j = 0; j < rows; j++) for (let i = 0; i < cols; i++) {
    const x = mx + i * (cw + gap) + (i >= cols / 2 ? mid : 0), y = my + j * (ch + gap);
    const v = 10 + r() * 3;
    g.fillStyle = `rgb(${v},${v + 2},${v + 7})`; g.fillRect(x, y, cw, ch);
    rg.fillStyle = '#3a3a3a'; rg.fillRect(x, y, cw, ch);
    g.fillStyle = 'rgba(58,64,76,.6)';    // multi-busbar fingers along the string (across the short side)
    for (let b = 1; b <= 5; b++) g.fillRect(x, y + ch * b / 6 - .7, cw, 1.4);
    g.fillStyle = 'rgba(255,255,255,.012)';
    for (let k = 0; k < 40; k++) g.fillRect(x + r() * cw, y + r() * ch, 1 + r() * 3, 1);
  }
  _cellTex = { map: canvasTexture(c), rough: canvasTexture(rC, { srgb: false }) };
  return _cellTex;
}

/* =================================================================== the house */
export const HOUSE = {
  x0: -4.8, x1: 4.8, zb: -3.4, zf: 1.2,       // body walls (post centrelines)
  plinth: .5, floor: .58,                     // granite plinth top, shoji sill top
  plate: 4.0,                                 // main wall-plate top
  pitch: 32 * deg, ridgeZ: -1.1, eave: .8, verge: .75,
  deck: .14, rafter: .09,                     // roof build-up under the tile plane
  his: { top: 3.3, pitch: 17 * deg, z1: 3.15, x: 5.05, deck: .035, rafter: .075 },
  eng: { z1: 2.42, top: .52, post: 2.3 },
  kamoi: 2.33, band: 2.45,
  bays: 5,
};

export async function buildHouse({ env = null, detail = 'high', panels = true, glow = 0, seed = 1, apron = true } = {}) {
  const H = HOUSE, R = rng(seed * 7919 + 13), M = await makeMaterials();
  const B = new Bucket(), group = new THREE.Group(); group.name = 'house';
  const high = detail !== 'mid';
  const tanP = Math.tan(H.pitch), cosP = Math.cos(H.pitch), sinP = Math.sin(H.pitch);
  const bay = (H.x1 - H.x0) / H.bays, Wr = (H.x1 - H.x0) + 2 * H.verge;
  const yR = H.plate + (H.zf - H.ridgeZ) * tanP + (H.deck + H.rafter) * cosP;    // tile plane at the ridge line
  const Ls = (H.zf + H.eave - H.ridgeZ) / cosP;                                   // slope length ridge -> eave
  const sWall = (H.zf - H.ridgeZ) / cosP;
  const roofY = z => yR - Math.abs(z - H.ridgeZ) * tanP;                          // tile plane height over z
  const deckBot = z => roofY(z) - (H.deck) / cosP;
  const hisY = z => H.his.top - (z - H.zf) * Math.tan(H.his.pitch);
  const tint = (k = .08, warm = 0) => { const v = 1 + (R() - .5) * 2 * k; return [v * (1 + warm), v, v * (1 - warm)]; };

  /* ---- sky-occlusion field (only darkens indirect light) */
  const AO = (x, y, z, nx, ny, nz) => {
    let a = 1;
    a *= 1 - .55 * Math.exp(-Math.max(0, y) / .16);                                 // ground contact
    if (y > H.plinth - .02) a *= 1 - .28 * Math.exp(-Math.max(0, y - H.plinth) / .12) * (Math.abs(ny) < .5 ? 1 : .4);  // plinth-top contact
    const inX = x > H.x0 - .4 && x < H.x1 + .4;
    // front, under the hisashi
    if (inX && z > H.zf - .12 && z < H.his.z1 + .05 && y < hisY(Math.max(z, H.zf)) + .05) {
      const d = clamp((H.his.z1 - z) / (H.his.z1 - H.zf)), yy = clamp((y - .3) / (H.his.top - .3));
      const vertical = Math.abs(ny) < .5;
      a *= vertical ? 1 - .5 * (.35 + .65 * yy) * (.6 + .4 * d) : 1 - (ny > 0 ? .62 * d * d + .12 : .5);
    }
    // band between hisashi and main eave, and the other three walls under the main eaves
    if (inX && Math.abs(ny) < .5) {
      const top = H.plate;
      if (y < top + .05 && y > H.plinth) a *= 1 - .32 * clamp((y - (top - 1.4)) / 1.4) ** 1.5;
    }
    // soffits and anything facing down
    if (ny < -.5) a *= .55;
    // inner corners of the body (wall meets wall)
    const cx = Math.min(Math.abs(x - H.x0), Math.abs(x - H.x1)), cz = Math.min(Math.abs(z - H.zb), Math.abs(z - H.zf));
    if (y < H.plate) a *= 1 - .15 * Math.exp(-cx / .25) * Math.exp(-cz / .25);
    return a;
  };
  const add = (key, g, col = [1, 1, 1], ao = AO) => B.add(key, paint(g, col, ao));
  const beam = (key, w, h, d, p, grain, r = [0, 0, 0], col) => add(key, place(box(w, h, d, { grain, off: [R() * 5, R() * 5] }), p, r), col || tint(.07));

  /* ---- granite plinth (kiso) with a thin projecting cap */
  const pw = H.x1 - H.x0 + .24, pd = H.zf - H.zb + .24, pcz = (H.zf + H.zb) / 2;
  add('stoneBand', place(box(pw, H.plinth - .05, pd, { grain: 'y', seg: [8, 2, 4] }), [0, (H.plinth - .05) / 2, pcz]), [1, 1, 1]);
  add('stoneBand', place(box(pw + .06, .05, pd + .06, { grain: 'y' }), [0, H.plinth - .025, pcz]), [1.12, 1.1, 1.06]);

  /* ---- sills (dodai) around the body */
  const sillH = .1, sy = H.plinth + sillH / 2;
  beam('dark', H.x1 - H.x0 + .15, sillH, .15, [0, sy, H.zf], 'x');
  beam('dark', H.x1 - H.x0 + .15, sillH, .15, [0, sy, H.zb], 'x');
  beam('dark', .15, sillH, H.zf - H.zb, [H.x0, sy, pcz - .12 + .12], 'z');
  beam('dark', .15, sillH, H.zf - H.zb, [H.x1, sy, pcz], 'z');

  /* ---- posts (hashira) */
  const postTop = H.plate - .2;
  const posts = [];
  for (let i = 0; i <= H.bays; i++) posts.push([H.x0 + i * bay, H.zf], [H.x0 + i * bay, H.zb]);
  for (const zz of [H.zb + (H.zf - H.zb) / 3, H.zb + 2 * (H.zf - H.zb) / 3]) posts.push([H.x0, zz], [H.x1, zz]);
  for (const [x, z] of posts) beam('dark', .15, postTop - H.plinth - sillH, .15, [x, (postTop + H.plinth + sillH) / 2, z], 'y');

  /* ---- wall plates (keta) running out into the gable overhang, gable tie beams, nuki bands */
  beam('dark', Wr - .1, .2, .17, [0, H.plate - .1, H.zf], 'x');
  beam('dark', Wr - .1, .2, .17, [0, H.plate - .1, H.zb], 'x');
  for (const x of [H.x0, H.x1]) {
    beam('dark', .17, .2, H.zf - H.zb + .5, [x, H.plate - .1, pcz], 'z');
    beam('dark', .16, .1, H.zf - H.zb, [x, H.band, pcz], 'z');            // nuki between siding and plaster
  }
  beam('dark', H.x1 - H.x0, .1, .16, [0, H.band, H.zb], 'x');
  beam('dark', H.x1 - H.x0, .11, .17, [0, H.kamoi + .055, H.zf], 'x');    // kamoi over the shoji

  /* ---- sugi board-and-batten (vertical boards, battens over the joints) */
  const siding = (u0, u1, y0, y1, plane, side) => {
    // plane: 'x' => wall at x = plane.x facing side (±1) along z; 'z' => wall at z facing side along x
    const bw = .205, n = Math.max(1, Math.round((u1 - u0) / bw)), w = (u1 - u0) / n, h = y1 - y0;
    for (let i = 0; i < n; i++) {
      const u = u0 + (i + .5) * w, off = [R() * 3, R() * 3];
      const t = tint(.1, (R() - .5) * .04);
      let g = box(w - .004, h, .018, { grain: 'y', off, seg: [1, 6, 1] });
      if (plane.axis === 'x') place(g, [plane.at + side * .009, (y0 + y1) / 2, u], [0, Math.PI / 2, 0]);
      else place(g, [u, (y0 + y1) / 2, plane.at + side * .009]);
      add('sugi', g, t);
      if (i < n - 1) {  // batten on the joint
        const bu = u0 + (i + 1) * w;
        g = box(.045, h, .022, { grain: 'y', off: [R() * 3, R() * 3], seg: [1, 6, 1] });
        if (plane.axis === 'x') place(g, [plane.at + side * (.018 + .011), (y0 + y1) / 2, bu], [0, Math.PI / 2, 0]);
        else place(g, [bu, (y0 + y1) / 2, plane.at + side * (.018 + .011)]);
        add('sugi', g, tint(.08));
      }
    }
  };
  const sy0 = H.plinth + sillH, sy1 = H.band - .05;
  // dark sheathing behind every board wall, so the joints never show daylight through the hollow body
  add('void', place(box(.02, sy1 - sy0, H.zf - H.zb), [H.x0 - .035, (sy0 + sy1) / 2, pcz]), [1, 1, 1], null);
  add('void', place(box(.02, sy1 - sy0, H.zf - H.zb), [H.x1 + .035, (sy0 + sy1) / 2, pcz]), [1, 1, 1], null);
  add('void', place(box(H.x1 - H.x0, sy1 - sy0, .02), [0, (sy0 + sy1) / 2, H.zb - .035]), [1, 1, 1], null);
  add('void', place(box(bay, H.kamoi - H.floor, .02), [H.x0 + bay / 2, (H.kamoi + H.floor) / 2, H.zf - .045]), [1, 1, 1], null);
  siding(H.zb + .075, H.zf - .075, sy0, sy1, { axis: 'x', at: H.x0 - .06 }, -1);   // left gable
  siding(H.zb + .075, H.zf - .075, sy0, sy1, { axis: 'x', at: H.x1 + .06 }, 1);    // right gable
  siding(H.x0 + .075, H.x1 - .075, sy0, sy1, { axis: 'z', at: H.zb - .06 }, -1);   // back
  siding(H.x0 + .075, H.x0 + bay - .075, H.floor, H.kamoi, { axis: 'z', at: H.zf - .02 }, 1);  // front bay 0 (tokonoma side)

  /* ---- shikkui plaster: upper walls, gable triangles, front band */
  const plasterWall = (pts, axis, at, side) => {   // pts: [[u,y]...] polygon in the wall plane
    const sh = new THREE.Shape(pts.map(([u, y]) => new THREE.Vector2(u, y)));
    const g = new THREE.ShapeGeometry(sh, 1);
    // ShapeGeometry lives in XY facing +z; turn it into the wall plane
    if (axis === 'x') place(g, [at, 0, 0], [0, side > 0 ? Math.PI / 2 : -Math.PI / 2, 0]);
    else place(g, [0, 0, at], [0, side > 0 ? 0 : Math.PI, 0]);
    add('plaster', g, [1, 1, 1]);
  };
  const dz = .03;
  for (const [x, side] of [[H.x0, -1], [H.x1, 1]]) {
    // for side -1 the shape u = z, for +1 u = -z (after the y-rotation)
    const U = z => side < 0 ? z : -z;
    const yd = z => deckBot(z) - .02;
    plasterWall([[U(H.zb), H.band], [U(H.zf), H.band], [U(H.zf), yd(H.zf)], [U(H.ridgeZ), yd(H.ridgeZ)], [U(H.zb), yd(H.zb)]], 'x', x + side * dz, side);
  }
  // back upper wall and front band (above the kamoi up to the plate), both under the timber
  plasterWall([[-H.x0, H.band], [-H.x1, H.band], [-H.x1, H.plate - .2], [-H.x0, H.plate - .2]].map(([u, y]) => [u, y]), 'z', H.zb - dz, -1);
  plasterWall([[H.x0, H.kamoi + .1], [H.x1, H.kamoi + .1], [H.x1, H.plate - .2], [H.x0, H.plate - .2]], 'z', H.zf + dz, 1);

  /* ---- gable timber (tsuma): king post, struts, a nuki across the gable, purlin ends out to the barge boards */
  const strutZ = [H.ridgeZ, (H.ridgeZ + H.zf) / 2 + .1, (H.ridgeZ + H.zb) / 2 - .1];
  for (const [x, side] of [[H.x0, -1], [H.x1, 1]]) {
    const xf = x + side * .045;
    for (const z of strutZ) {
      const ptop = deckBot(z) - H.rafter / cosP, pbot = ptop - .17;
      beam('dark', .12, pbot - H.plate, .12, [xf, (pbot + H.plate) / 2, z], 'y');
      // purlin (moya / munagi) end, from inside the wall out to the barge board
      const len = Wr / 2 - Math.abs(x) - .05 + .3;
      beam('dark', len, .17, .14, [x + side * (len / 2 - .3), pbot + .085, z], 'x');
    }
    const ny = H.plate + (deckBot(H.ridgeZ) - H.plate) * .42, half = (deckBot(H.ridgeZ) - ny) / tanP;
    beam('dark', .12, .1, 2 * half - .1, [xf, ny, H.ridgeZ], 'z');
  }

  /* ---- a slatted window high on the left gable (renji-mado), glowing */
  const gw = { z: H.ridgeZ, y: 3.35, w: 1.3, h: .42 };
  {
    const x = H.x0 - .05;
    beam('dark', .08, .06, gw.w + .12, [x, gw.y - gw.h / 2 - .03, gw.z], 'z');
    beam('dark', .08, .06, gw.w + .12, [x, gw.y + gw.h / 2 + .03, gw.z], 'z');
    for (const s of [-1, 1]) beam('dark', .08, gw.h, .06, [x, gw.y, gw.z + s * (gw.w / 2 + .03)], 'y');
    for (let i = 1; i < 12; i++) beam('hinoki', .03, gw.h, .022, [x - .01, gw.y, gw.z - gw.w / 2 + i * gw.w / 12], 'y');
    add('paper', place(box(.01, gw.h, gw.w, { grain: 'y' }), [x + .03, gw.y, gw.z]), [1, 1, 1], null);
  }

  /* ---- front: shoji in bays 1..4 (two panels each), frames and kumiko in hinoki, washi paper glowing */
  const shojiH = H.kamoi - H.floor, shojiGlow = [];
  for (let b = 1; b < H.bays; b++) {
    const bx0 = H.x0 + b * bay + .075, bx1 = H.x0 + (b + 1) * bay - .075, pw2 = (bx1 - bx0) / 2 + .02;
    for (let k = 0; k < 2; k++) {
      const cx = k === 0 ? bx0 + pw2 / 2 : bx1 - pw2 / 2, cz = H.zf + (k === 0 ? .055 : .015);
      const y0 = H.floor, y1 = H.kamoi, cy = (y0 + y1) / 2;
      const fr = (w, h, x, y) => beam('hinoki', w, h, .032, [x, y, cz], w > h ? 'x' : 'y', [0, 0, 0], tint(.05));
      fr(.035, shojiH, cx - pw2 / 2 + .0175, cy); fr(.035, shojiH, cx + pw2 / 2 - .0175, cy);
      fr(pw2, .045, cx, y1 - .0225); fr(pw2, .16, cx, y0 + .08);                   // top rail, koshi bottom rail
      const iy0 = y0 + .16, iy1 = y1 - .045, ix0 = cx - pw2 / 2 + .035, ix1 = cx + pw2 / 2 - .035;
      const nc = 3, nr = 7;
      for (let i = 1; i < nc; i++) beam('hinoki', .011, iy1 - iy0, .018, [lerp(ix0, ix1, i / nc), (iy0 + iy1) / 2, cz + .004], 'y', [0, 0, 0], tint(.04));
      for (let j = 1; j < nr; j++) beam('hinoki', ix1 - ix0, .011, .018, [(ix0 + ix1) / 2, lerp(iy0, iy1, j / nr), cz + .004], 'x', [0, 0, 0], tint(.04));
      const pg = place(box(ix1 - ix0, iy1 - iy0, .004, { grain: 'y', off: [R() * 2, R() * 2] }), [(ix0 + ix1) / 2, (iy0 + iy1) / 2, cz - .012]);
      const lamp = .75 + R() * .35;                                                   // uneven room light behind each panel
      add('paper', pg, [lamp, lamp, lamp], null);
      shojiGlow.push(lamp);
    }
    // shikii (sill with tracks)
    beam('dark', bx1 - bx0 + .02, .05, .12, [(bx0 + bx1) / 2, H.floor - .025, H.zf + .035], 'x');
  }

  /* ---- engawa: hinoki boards along x, edge beam, tsuka on stones, dark void underneath */
  const E = H.eng, ez0 = H.zf + .08, nb = 8, bwid = (E.z1 - ez0) / nb;
  for (let j = 0; j < nb; j++) {
    let x = H.x0 - .05, first = true;
    const z = ez0 + (j + .5) * bwid;
    while (x < H.x1 + .05) {
      const L = Math.min(first ? .6 + R() * 2.4 : 2.4 + R() * 1.4, H.x1 + .05 - x); first = false;
      if (L > .05) add('hinoki', place(box(L - .002, .03, bwid - .0025, { grain: 'x', off: [R() * 5, R() * 5] }), [x + L / 2, E.top - .015, z]), tint(.07, .01));
      x += L;
    }
  }
  beam('dark', H.x1 - H.x0 + .1, .12, .12, [0, E.top - .09, E.z1 - .06], 'x');
  beam('dark', H.x1 - H.x0 + .1, .02, E.z1 - ez0, [0, E.top - .04, (E.z1 + ez0) / 2], 'x');   // underlay: gaps never show daylight
  add('void', place(box(H.x1 - H.x0, E.top - .04, .02), [0, (E.top - .04) / 2, H.zf + .32]), [1, 1, 1]);

  /* ---- hisashi: posts, eave beam, rafters swept along the slope, sugi soffit, standing-seam roof */
  const hp = H.his, hsin = Math.sin(hp.pitch), hcos = Math.cos(hp.pitch), hLs = (hp.z1 - H.zf) / hcos;
  const hisM = new THREE.Matrix4().makeBasis(new THREE.Vector3(1, 0, 0), new THREE.Vector3(0, hcos, hsin), new THREE.Vector3(0, -hsin, hcos)).setPosition(0, hp.top, H.zf);
  const hisAdd = (key, g, col, ao = AO) => { g.applyMatrix4(hisM); return add(key, g, col, ao); };
  const kY = hisY(E.post) - (hp.deck + hp.rafter) / hcos;        // keta top
  beam('dark', 2 * hp.x - .1, .16, .13, [0, kY - .08, E.post], 'x');
  for (let i = 0; i <= H.bays; i++) {
    const x = H.x0 + i * bay, top = kY - .16;
    beam('dark', .12, top - .1, .12, [x, (top + .1) / 2, E.post], 'y');
    { const g = flatStone(seed * 7 + i * 3, .19, .2, [1.1, .95]); g.rotateY(i * 1.3); g.translate(x, .07, E.post); add('stone', g, [1, 1, 1]); }
  }
  // deck (soffit boards beneath), rafters, fascia, seamed roof
  hisAdd('soffit', box(2 * hp.x, hp.deck, hLs + .02, { grain: 'z', seg: [1, 1, 4] }).translate(0, -hp.deck / 2, (hLs + .02) / 2));
  for (let x = -hp.x + .12; x <= hp.x - .1; x += .45) {
    const g = box(.055, hp.rafter, hLs + .04, { grain: 'z', off: [R() * 3, R() * 3] }).translate(x, -hp.deck - hp.rafter / 2, (hLs - .06) / 2);
    hisAdd('dark', g, tint(.06));
  }
  hisAdd('dark', box(2 * hp.x + .02, .05, .035, { grain: 'x' }).translate(0, .005, hLs + .012));        // kayaoi on the rafter ends
  hisAdd('seam', box(2 * hp.x + .04, .008, hLs + .07).translate(0, .004, (hLs + .07) / 2 - .03));
  for (let x = -hp.x + .21; x < hp.x; x += .42) hisAdd('seam', box(.018, .028, hLs + .06).translate(x, .022, (hLs + .06) / 2 - .03));
  hisAdd('seam', box(2 * hp.x + .04, .06, .012).translate(0, -.02, hLs + .04));                         // drip edge
  for (const s of [-1, 1]) hisAdd('dark', box(.04, .12, hLs + .06, { grain: 'z' }).translate(s * (hp.x + .01), -.03, (hLs + .06) / 2 - .02));   // end boards

  /* ---- main roof: two slopes in slope-local frames (x, n, s) */
  const front = new THREE.Matrix4().makeBasis(new THREE.Vector3(1, 0, 0), new THREE.Vector3(0, cosP, sinP), new THREE.Vector3(0, -sinP, cosP)).setPosition(0, yR, H.ridgeZ);
  const flip = new THREE.Matrix4().makeTranslation(0, 0, H.ridgeZ).multiply(new THREE.Matrix4().makeRotationY(Math.PI)).multiply(new THREE.Matrix4().makeTranslation(0, 0, -H.ridgeZ));
  const back = flip.clone().multiply(front);
  const slopes = [front, back];
  for (const S of slopes) {
    const sAdd = (key, g, col, ao = AO) => { g.applyMatrix4(S); return add(key, g, col, ao); };
    // deck slab (soffit underneath)
    sAdd('soffit', box(Wr - .12, H.deck, Ls + .04, { grain: 'z', seg: [6, 1, 6] }).translate(0, -H.deck / 2, (Ls + .04) / 2 - .02));
    // rafters under the eave and in the verge overhangs
    for (let x = -Wr / 2 + .14; x <= Wr / 2 - .1; x += .45) {
      const inGable = Math.abs(x) > H.x1 + .05;
      const s0 = inGable ? .15 : sWall - .15;
      sAdd('dark', box(.06, H.rafter, Ls - s0 - .01, { grain: 'z', off: [R() * 3, R() * 3] }).translate(x, -H.deck - H.rafter / 2, s0 + (Ls - s0 - .01) / 2), tint(.06));
    }
    // fascia (kayaoi) at the eave
    sAdd('dark', box(Wr - .1, .11, .04, { grain: 'x' }).translate(0, -.055, Ls + .005));
    // barge boards (hafu) with a thin cap
    for (const sd of [-1, 1]) {
      sAdd('dark', box(.07, .34, Ls + .1, { grain: 'z', off: [R() * 3, 0] }).translate(sd * (Wr / 2 - .035), -.15, (Ls + .1) / 2 - .06), tint(.05));
    }
  }

  /* ---- kawara: instanced san-gawara on both slopes, eave tiles with a lip, verge rolls, noshi ridge, onigawara */
  const tw = Wr / Math.round(Wr / .265), tl = .3, tpitch = .235, tt = .016;
  const tileG = tileGeometry(tw, tl, tt * .8, high ? 12 : 8, false), eaveG = tileGeometry(tw, tl, tt, high ? 12 : 8, true);
  const cols = Math.round(Wr / tw), sTop = .16;
  // courses from the eave up; the last one is pulled down so no tile head passes the ridge line (they poked through the noshi)
  const courses = Math.floor((Ls - tl) / tpitch) + 2;
  const mats = [], eaveMats = [], tcol = [], ecol = [];
  const tq = new THREE.Quaternion().setFromAxisAngle(new THREE.Vector3(1, 0, 0), -Math.atan2(tt, tl));   // butt proud of the course below
  const tc = new THREE.Color();
  for (const S of slopes) for (let j = 0; j < courses; j++) for (let i = 0; i < cols; i++) {
    const butt = Math.max(Ls - j * tpitch, tl - .01);   // down-slope edge of this course
    const m = new THREE.Matrix4().compose(new THREE.Vector3(-Wr / 2 + i * tw, tt * .9 + .02, butt), tq, new THREE.Vector3(1, 1, 1));   // pans clear the deck at the tile head
    m.premultiply(S);
    const v = (.82 + R() * .32) * (R() < .06 ? .8 : 1) * (R() < .05 ? 1.15 : 1), warm = (R() - .5) * .05;
    tc.setRGB(v * (1 + warm), v * (1 + warm * .3), v * (1 - warm + R() * .03));
    if (j === 0) { eaveMats.push(m); ecol.push(tc.clone()); } else { mats.push(m); tcol.push(tc.clone()); }
  }
  const mkInst = (g, list, cl) => {
    const im = new THREE.InstancedMesh(g, M.tileV, list.length);
    list.forEach((m, i) => { im.setMatrixAt(i, m); im.setColorAt(i, cl[i]); });
    im.instanceMatrix.needsUpdate = true; im.instanceColor.needsUpdate = true;
    im.castShadow = false; im.receiveShadow = true; im.computeBoundingSphere(); return im;
  };
  const tiles = mkInst(tileG, mats, tcol), eaveTiles = mkInst(eaveG, eaveMats, ecol);
  tiles.name = 'kawara'; eaveTiles.name = 'kawara-eave';
  group.add(tiles, eaveTiles);
  // verge rolls (sodegawara) on both slopes
  const rollG = [];
  for (const S of slopes) for (const sd of [-1, 1]) {
    const g = new THREE.CylinderGeometry(.055, .055, Ls - .05, 10, 1, false).rotateX(Math.PI / 2).translate(sd * (Wr / 2 - .03), .045, (Ls - .05) / 2 + .1);
    g.applyMatrix4(S); rollG.push(g);
    const lip = box(.04, .14, Ls - .05).translate(sd * (Wr / 2 + .005), -.02, (Ls - .05) / 2 + .1); lip.applyMatrix4(S); rollG.push(lip);
  }
  // ridge: white menado plaster line, four courses of noshi, round kanmuri cap with joint rings
  const ridgeParts = [];
  const RL = Wr + .06;
  ridgeParts.push(['plaster', box(RL - .1, .1, .42, { grain: 'x' }).translate(0, yR - .045, H.ridgeZ)]);
  for (let k = 0; k < 4; k++) {                    // noshi-gawara: four courses, each stepped in 2 cm, lightly tapered
    const w = .38 - k * .04, y = yR + .02 + k * .048;
    const g = box(RL, .052, w); const P = g.attributes.position;   // courses overlap: no light between them
    for (let i = 0; i < P.count; i++) if (P.getY(i) < 0) P.setZ(i, P.getZ(i) * 1.03);
    // each course's lower edge carries a darker line (the shadow of the course above), so the stack reads as courses
    const C = g.attributes.position, cl = new Float32Array(C.count * 3); for (let i = 0; i < C.count; i++) { const v = C.getY(i) < 0 ? .62 : 1.08; cl.set([v, v, v * .98], i * 3); }
    g.setAttribute('color', new THREE.BufferAttribute(cl, 3));
    ridgeParts.push(['tile', g.translate(0, y, H.ridgeZ), true]);
  }
  const capY = yR + .02 + 3 * .048 + .021;
  ridgeParts.push(['tile', new THREE.CylinderGeometry(.105, .105, RL, 18, 1, false, 0, Math.PI).rotateZ(Math.PI / 2).translate(0, capY, H.ridgeZ)]);
  // onigawara at both ends
  const oni = oniGeometry();
  for (const sd of [-1, 1]) ridgeParts.push(['tile', oni.clone().rotateY(Math.PI / 2).translate(sd * (RL / 2 + .02), yR - .1, H.ridgeZ)]);
  const tileBucket = new Bucket();
  for (const g of rollG) tileBucket.add('tile', paint(g));
  for (const [k, g, own] of ridgeParts) {
    if (own) { g.setAttribute('ao', new THREE.BufferAttribute(new Float32Array(g.attributes.position.count).fill(1), 1)); tileBucket.add('tile', g); continue; }
    (k === 'tile' ? tileBucket : B).add(k === 'tile' ? 'tile' : 'plaster', paint(g, [1.08, 1.06, 1.02], k === 'tile' ? null : AO));
  }
  const ridgeMesh = tileBucket.mesh('tile', M.tileV, { cast: true }); ridgeMesh.name = 'ridge';
  group.add(ridgeMesh);

  /* ---- solar array: 3 rows x 6 landscape panels flush on the front slope, rails + feet, each panel its own object */
  const panelList = []; let rails = null;
  const PW = 1.7, PH = 1.0, PT = .035, gapP = .02, prow = 2, pcol = 6;
  const arrayW = pcol * PW + (pcol - 1) * gapP, ridgeClear = .24 + .3, arrayH = prow * PH + (prow - 1) * gapP;
  const s0 = ridgeClear + Math.max(0, (Ls - .3 - ridgeClear - arrayH) * .42), n0 = .1;
  const arrayC = new THREE.Vector3(0, n0 + PT, s0 + (prow * PH + (prow - 1) * gapP) / 2).applyMatrix4(front);
  if (panels) {
    const cell = cellTexture();
    const glass = new THREE.MeshPhysicalMaterial({ map: cell.map, roughnessMap: cell.rough, roughness: 1, metalness: 0, color: new THREE.Color(1, 1, 1), clearcoat: 1, clearcoatRoughness: .035, envMapIntensity: 1.25, specularIntensity: .6 });
    const glassG = new THREE.BoxGeometry(PW - .05, .004, PH - .05);   // BoxGeometry's +y face maps u->x, v->z: the cell grid
    const frameB = new Bucket();
    frameB.add('f', paint(box(PW, PT, .03).translate(0, PT / 2, -PH / 2 + .015)));
    frameB.add('f', paint(box(PW, PT, .03).translate(0, PT / 2, PH / 2 - .015)));
    frameB.add('f', paint(box(.03, PT, PH - .06).translate(-PW / 2 + .015, PT / 2, 0)));
    frameB.add('f', paint(box(.03, PT, PH - .06).translate(PW / 2 - .015, PT / 2, 0)));
    const frameMesh = frameB.mesh('f', M.frameMetal); const frameG = frameMesh.geometry;
    const slopeQ = new THREE.Quaternion().setFromRotationMatrix(front);
    for (let j = 0; j < prow; j++) for (let i = 0; i < pcol; i++) {
      const p = new THREE.Group(); p.name = `panel-${j}-${i}`;
      const fm = new THREE.Mesh(frameG, M.frameMetal); fm.castShadow = true; fm.receiveShadow = true;
      const gm = new THREE.Mesh(glassG, glass); gm.position.y = PT - .004; gm.receiveShadow = true;
      p.add(fm, gm);
      const x = -arrayW / 2 + PW / 2 + i * (PW + gapP), s = s0 + PH / 2 + j * (PH + gapP);
      p.position.set(x, n0, s).applyMatrix4(front); p.quaternion.copy(slopeQ).multiply(new THREE.Quaternion().setFromEuler(new THREE.Euler((R() - .5) * .012, 0, (R() - .5) * .01)));
      p.userData.home = { position: p.position.clone(), quaternion: p.quaternion.clone() };
      p.userData.index = [j, i];
      group.add(p); panelList.push(p);
    }
    const rb = new Bucket();
    for (let j = 0; j < prow; j++) for (const f of [.24, .76]) {
      const s = s0 + j * (PH + gapP) + f * PH;
      rb.add('r', paint(box(arrayW + .1, .04, .04).translate(0, n0 - .02, s).applyMatrix4(front)));
      for (let x = -arrayW / 2 + .3; x < arrayW / 2; x += 1.2) rb.add('r', paint(box(.05, .08, .07).translate(x, n0 - .06, s).applyMatrix4(front)));
    }
    rails = rb.mesh('r', M.blackMetal); rails.name = 'rails'; rails.castShadow = false; group.add(rails);
  }

  /* ---- battery cabinet (hinoki slats, dark cap) on the left gable near the engawa, on a granite pad */
  const bat = { x: H.x0 - .15 - .15, z: .3, w: .78, h: 1.12, d: .3 };
  add('stone', place(new RoundedBoxGeometry(bat.d + .16, .07, bat.w + .2, 2, .02), [bat.x, .035, bat.z]), [1, 1, 1]);
  add('blackMetal', place(box(bat.d - .02, bat.h - .04, bat.w - .02), [bat.x + .01, .07 + (bat.h - .04) / 2, bat.z]), [1, 1, 1]);
  const nsl = 11;
  for (let i = 0; i < nsl; i++) {
    const z = bat.z - bat.w / 2 + (i + .5) * bat.w / nsl;
    add('hinoki', place(box(.022, bat.h - .12, bat.w / nsl - .012, { grain: 'y', off: [R() * 3, R() * 3], seg: [1, 4, 1] }), [bat.x - bat.d / 2, .07 + .04 + (bat.h - .12) / 2, z]), tint(.05, .01));
  }
  for (const zz of [-1, 1]) add('hinoki', place(box(bat.d - .02, bat.h - .12, .02, { grain: 'y', off: [R() * 3, 0] }), [bat.x + .01, .07 + .04 + (bat.h - .12) / 2, bat.z + zz * (bat.w / 2 - .005)]), tint(.05, .01));
  add('blackMetal', place(box(bat.d + .05, .035, bat.w + .05), [bat.x, .07 + bat.h + .0175, bat.z]), [1, 1, 1]);
  add('led', place(box(.004, .01, .16), [bat.x - bat.d / 2 - .014, .07 + bat.h - .09, bat.z]), [1, 1, 1], null);
  add('greyMetal', place(new THREE.CylinderGeometry(.018, .018, .45, 8), [H.x0 - .1, .07 + bat.h - .25, bat.z + bat.w / 2 - .06]), [1, 1, 1]);   // conduit into the wall
  const battery = new THREE.Object3D(); battery.position.set(bat.x, .07 + bat.h + .06, bat.z); group.add(battery);

  /* ---- meter + conduit on the front wall of the end bay (the boarded one, left of the shoji), service drop above */
  const mt = { x: H.x0 + bay - .38, y: 1.72, z: H.zf + .045 };
  add('meterBody', place(new RoundedBoxGeometry(.26, .36, .12, 2, .012), [mt.x, mt.y, mt.z + .06]), [1, 1, 1]);
  add('void', place(box(.16, .1, .004), [mt.x, mt.y + .06, mt.z + .121]), [1, 1, 1], null);
  add('greyMetal', place(new THREE.CylinderGeometry(.016, .016, H.kamoi - mt.y - .18 + .02, 8), [mt.x + .07, (H.kamoi + .02 + mt.y + .18) / 2, mt.z + .03]), [1, 1, 1]);
  add('greyMetal', place(new THREE.CylinderGeometry(.016, .016, mt.y - .18 - H.floor, 8), [mt.x - .07, (mt.y - .18 + H.floor) / 2, mt.z + .03]), [1, 1, 1]);
  const meter = new THREE.Object3D(); meter.position.set(mt.x, mt.y + .2, mt.z + .08); group.add(meter);

  /* ---- kutsunugi-ishi (shoe stone) at the engawa: a natural flat-topped granite block, top ~0.3 m */
  { const g = flatStone(seed * 13 + 5, .48, .42, [1.05, .62]); g.rotateY(.06); g.translate(H.x0 + 2.5 * bay, .3, E.z1 + .36); add('stone', g, [1.04, 1.02, 1]); }

  /* ---- amaochi: dark river pebbles along the drip line, edged by a granite kerb */
  if (apron) {
    const band = (x0, x1, z0, z1) => {
      add('pebble', place(box(x1 - x0, .03, z1 - z0, { grain: 'x', off: [R() * 3, R() * 3] }), [(x0 + x1) / 2, .015, (z0 + z1) / 2]), [1, 1, 1]);
    };
    const ex = Wr / 2 + .05, ez0 = H.zb - H.eave - .1;
    band(-ex, ex, hp.z1 - .35, hp.z1 + .25);                    // front, under the hisashi drip
    band(-ex, -H.x1 - .12, ez0, hp.z1 - .35);                   // left side
    band(H.x1 + .12, ex, ez0, hp.z1 - .35);                     // right side
    band(-H.x1 - .12, H.x1 + .12, ez0, H.zb - .12);             // back
    for (const [x0, x1, z0, z1] of [[-ex - .06, ex + .06, hp.z1 + .25, hp.z1 + .31], [-ex - .06, -ex, ez0, hp.z1 + .25], [ex, ex + .06, ez0, hp.z1 + .25]])
      add('stone', place(box(x1 - x0, .06, z1 - z0, { grain: 'x' }), [(x0 + x1) / 2, .03, (z0 + z1) / 2]), [1, 1, 1]);
  }

  /* ---- merge per material */
  const meshes = {};
  const order = [['stoneBand', M.stoneBand], ['dark', M.dark], ['sugi', M.sugi], ['soffit', M.soffit], ['plaster', M.plaster], ['hinoki', M.hinoki],
    ['paper', M.paper], ['seam', M.seam], ['blackMetal', M.blackMetal], ['greyMetal', M.greyMetal], ['meterBody', M.meterBody], ['void', M.void], ['stone', M.stone], ['pebble', M.pebble], ['led', M.led]];
  for (const [k, mat] of order) {
    const m = B.mesh(k, mat, { cast: !['led', 'pebble'].includes(k) });
    if (m) { meshes[k] = m; group.add(m); }
  }

  /* ---- warm light spill from the shoji onto the engawa floor and the plinth face (additive, driven by glow) */
  const spillMat = new THREE.ShaderMaterial({
    transparent: true, depthWrite: false, blending: THREE.AdditiveBlending, premultipliedAlpha: true,
    uniforms: { uGlow: { value: 0 }, uCol: { value: new THREE.Color(1, .52, .2) } },
    vertexShader: 'varying vec2 vUv; void main(){ vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.); }',
    fragmentShader: `uniform float uGlow; uniform vec3 uCol; varying vec2 vUv;
      void main(){ float x = vUv.x, z = vUv.y; float bay = smoothstep(.0, .06, x) * smoothstep(1., .94, x);
        float f = exp(-z * 3.2) * bay * (.8 + .2 * sin(x * 25.13)); gl_FragColor = vec4(uCol * f * uGlow * .55, 1.); }`,
  });
  const spill = new THREE.Mesh(new THREE.PlaneGeometry(4 * bay - .1, E.z1 - H.zf - .06).rotateX(-Math.PI / 2), spillMat);
  spill.position.set(H.x0 + bay + 2 * bay, E.top + .003, (H.zf + .06 + E.z1) / 2);
  // uv.y runs from far (0) to near (1) after rotateX; flip so z=0 is at the wall
  { const uv = spill.geometry.attributes.uv; for (let i = 0; i < uv.count; i++) uv.setY(i, 1 - uv.getY(i)); }
  spill.renderOrder = 2; group.add(spill);

  /* ---- glow control */
  const setGlow = v => {
    v = clamp(v, 0, 1.5);
    M.paper.emissiveIntensity = v * 2.6;
    M.paper.color.setRGB(.94, .92, .88).multiplyScalar(1 - .35 * Math.min(v, 1));
    spillMat.uniforms.uGlow.value = v;
    M.led.color.setRGB(.25 * (.4 + v), 2.2 * (.4 + v), .9 * (.4 + v));
  };
  setGlow(glow);

  /* ---- anchors, bounds, sun catchers */
  const roof = new THREE.Object3D(); roof.position.copy(arrayC); group.add(roof);
  group.updateMatrixWorld(true);
  const bounds = new THREE.Box3().setFromObject(group);
  const sunCatchers = [ridgeMesh, tiles, eaveTiles, meshes.dark, meshes.soffit, meshes.plaster].filter(Boolean);
  return {
    group, panels: panelList, rails, setGlow, setRim: (k = 1, p = 3) => setRim(group, k, p), anchors: { roof, battery, meter }, bounds, sunCatchers, materials: M, meshes,
    dims: { yR, Ls, Wr, ridgeTop: capY + .105, front, arrayC: arrayC.clone(), eaveZ: H.zf + H.eave, hisZ: hp.z1, engawa: E, bay },
  };
}

/* ------------------------------------------------------------------ tile geometry
   One san-gawara in its course frame: x across [0, w], s down-slope [-L, 0] (butt at s = 0), n up.
   Asymmetric wave (wide pan, narrow roll) that is continuous from tile to tile; the butt face shows the course line.
   The eave course gets a turned-down lip (manju) under the butt. */
function tileGeometry(w, L, t, nu, lip) {
  // the right quarter of each tile rises 6 mm and laps over the next tile's pan: a small step at every joint
  const lap = u => .006 * smoothstep(w * .72, w * .98, u);
  const prof = u => { const a = 2 * Math.PI * u / w; return .024 * Math.cos(a + .62 * Math.sin(a)) + .004 + lap(u); };
  const dprof = u => (prof(u + 1e-4) - prof(u - 1e-4)) / 2e-4;
  const nv = 3, pos = [], nor = [], idx = [], col = [];
  let shadeNow = 1;
  const vert = (x, y, z, nx, ny, nz) => { pos.push(x, y, z); nor.push(nx, ny, nz); col.push(shadeNow, shadeNow, shadeNow); return pos.length / 3 - 1; };
  // top surface grid
  const top = [];
  for (let j = 0; j <= nv; j++) {
    const s = -L + L * j / nv; const row = [];
    for (let i = 0; i <= nu; i++) {
      const u = w * i / nu, d = dprof(u), n = new THREE.Vector3(-d, 1, 0).normalize();
      row.push(vert(u, prof(u) + t, s, n.x, n.y, n.z));
    }
    top.push(row);
  }
  for (let j = 0; j < nv; j++) for (let i = 0; i < nu; i++) { const a = top[j][i], b = top[j][i + 1], c = top[j + 1][i], d = top[j + 1][i + 1]; idx.push(a, c, b, b, c, d); }
  // lap face at the joint (facing +x, into the neighbour's pan), in its own soft shadow
  shadeNow = .5;
  { const a0 = vert(w, prof(w) + t, -L, 1, .3, 0), a1 = vert(w, prof(w) + t, 0, 1, .3, 0), b0 = vert(w, prof(w) + t - .008, -L, 1, .3, 0), b1 = vert(w, prof(w) + t - .008, 0, 1, .3, 0); idx.push(a0, b0, a1, a1, b0, b1); }
  // butt face (facing +s): shaded, it sits in the shadow line under the tile above
  const drop = lip ? .05 : t;
  const bt = [], bb = [];
  const bn = new THREE.Vector3(0, .35, .94).normalize(); shadeNow = .55;
  for (let i = 0; i <= nu; i++) { const u = w * i / nu; bt.push(vert(u, prof(u) + t, 0, bn.x, bn.y, bn.z)); bb.push(vert(u, prof(u) + t - drop, .004, 0, .45, .9)); }
  for (let i = 0; i < nu; i++) idx.push(bt[i], bb[i], bt[i + 1], bt[i + 1], bb[i], bb[i + 1]);
  if (lip) { // underside of the lip, visible from below at the eave
    const ub = [];
    for (let i = 0; i <= nu; i++) { const u = w * i / nu; ub.push(vert(u, prof(u) + t - drop, -.06, 0, -1, 0)); }
    const bb2 = []; for (let i = 0; i <= nu; i++) { const u = w * i / nu; bb2.push(vert(u, prof(u) + t - drop, 0, 0, -1, 0)); }
    for (let i = 0; i < nu; i++) idx.push(ub[i], ub[i + 1], bb2[i], bb2[i], ub[i + 1], bb2[i + 1]);
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  g.setAttribute('normal', new THREE.Float32BufferAttribute(nor, 3));
  g.setAttribute('color', new THREE.Float32BufferAttribute(col, 3));
  g.setIndex(idx);
  return g;
}
const smoothstep = (a, b, x) => { const t = clamp((x - a) / (b - a)); return t * t * (3 - 2 * t); };

/* onigawara: a shield with an arched crown and flared horns, extruded 0.1 m (faces +z before rotation) */
function oniGeometry() {
  const s = new THREE.Shape();
  s.moveTo(-.25, 0); s.lineTo(.25, 0); s.lineTo(.25, .3);
  s.quadraticCurveTo(.34, .42, .36, .56); s.quadraticCurveTo(.24, .5, .18, .5);
  s.quadraticCurveTo(.12, .64, 0, .66); s.quadraticCurveTo(-.12, .64, -.18, .5);
  s.quadraticCurveTo(-.24, .5, -.36, .56); s.quadraticCurveTo(-.34, .42, -.25, .3); s.lineTo(-.25, 0);
  const hole = new THREE.Path(); hole.absarc(0, .3, .07, 0, Math.PI * 2, true); s.holes.push(hole);
  const g = new THREE.ExtrudeGeometry(s, { depth: .1, bevelEnabled: true, bevelThickness: .012, bevelSize: .012, bevelSegments: 2, curveSegments: 10 });
  g.translate(0, 0, -.05);
  return g;
}
