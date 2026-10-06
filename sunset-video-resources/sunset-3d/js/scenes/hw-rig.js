// Shared rig for the three hardware cards (panel, battery, phone): one lens, one sun, one paper, one set of woods.
// Not a scene host itself; the card scenes import it so the row reads as a set.
//  - camera: 32° lens at 22° elevation, a 20° three-quarter turn from the right. Every subject is fitted to the same
//    projected height (HF of the card) with its lowest point on the same ground line (GL), and its shadow kept inside.
//  - light: the warm paper studio (ctx.env.studio), a warm bounce, ONE warm ~3000 K sun from the front-left (40° round,
//    25° up) and a cool fill from the right; the baked ground shadow is compact (cast from 40°) and fades with distance
//    whose shadow falls back-right. The ground shadow is baked once by accumulating many jittered projections (an area
//    sun, so the penumbra widens with distance) plus a sky-occlusion pass (contact AO under every base).
//  - woods: one procedural quarter-sawn hinoki (pale ivory, faint pink, straight fine grain) and one yakisugi (charred
//    cedar with alligator crackle and a faint silver-blue sheen at grazing angles).
import { THREE, clamp, damp, makeCanvas, canvasTexture, rng, REDUCED } from '../core.js';
import { hinokiTextures, hinokiEndTextures, perMetre } from '../models/woods.js';

const D = THREE.MathUtils.degToRad;
export const HW = {
  fov: 32, el: D(22), az: D(20),
  HF: .65, GL: .87, XC: -.1, maxW: .8,               // projected height / card height, ground line from top, centre x (NDC), max half-width
  // the key: a warm ~3000 K evening sun, low (25°) from the front-left; a cool fill answers it from the right
  keyDir: new THREE.Vector3(-Math.sin(D(40)) * Math.cos(D(25)), Math.sin(D(25)), Math.cos(D(40)) * Math.cos(D(25))).normalize(),
  keyColor: 0xFFB977, keyI: 3.4, envI: .34, bounceSky: 0xFFF3E4, bounceGround: 0xE7D6BC, bounceI: .3,
  fillDir: new THREE.Vector3(1, .6, .5).normalize(), fillColor: 0xB9C8FF, fillI: .55,
  // the ground shadow is baked from the same azimuth but higher (40°), so it stays compact, and fades with distance
  shadowDir: new THREE.Vector3(-Math.sin(D(40)) * Math.cos(D(40)), Math.sin(D(40)), Math.cos(D(40)) * Math.cos(D(40))).normalize(),
  shadow: 0x7a5234, sunCone: D(5),                   // paper-toned umber; the sun's angular radius (penumbra)
};

/* ================================================================ light */
/** Studio environment + the shared key (self-shadowing on the object only) and bounce. */
export function cardLights(scene, env, box, { keyI = HW.keyI, mapSize = 2048, radius = 5 } = {}) {
  scene.environment = env.studio || env.texture; scene.environmentIntensity = HW.envI;
  scene.add(new THREE.HemisphereLight(HW.bounceSky, HW.bounceGround, HW.bounceI));
  const fill = new THREE.DirectionalLight(HW.fillColor, HW.fillI); fill.position.copy(HW.fillDir).multiplyScalar(10); scene.add(fill);
  const key = new THREE.DirectionalLight(HW.keyColor, keyI);
  const c = box.getCenter(new THREE.Vector3()), r = box.getSize(new THREE.Vector3()).length() / 2;
  key.position.copy(c).addScaledVector(HW.keyDir, r * 3 + 1); key.target.position.copy(c);
  scene.add(key, key.target);
  key.castShadow = true; key.shadow.mapSize.set(mapSize, mapSize); key.shadow.radius = radius;
  key.shadow.bias = -.0002; key.shadow.normalBias = r * .003;
  key.updateMatrixWorld(); key.target.updateMatrixWorld();
  const lc = key.shadow.camera; lc.position.copy(key.position); lc.lookAt(c); lc.updateMatrixWorld();
  const inv = lc.matrixWorldInverse, b = new THREE.Box3(), v = new THREE.Vector3();
  for (const x of [box.min.x, box.max.x]) for (const y of [box.min.y, box.max.y]) for (const z of [box.min.z, box.max.z]) b.expandByPoint(v.set(x, y, z).applyMatrix4(inv));
  const pad = r * .04;
  Object.assign(lc, { left: b.min.x - pad, right: b.max.x + pad, bottom: b.min.y - pad, top: b.max.y + pad, near: Math.max(.01, -b.max.z - r), far: -b.min.z + r });
  lc.updateProjectionMatrix();
  key.shadow.autoUpdate = false; key.shadow.needsUpdate = true;
  return { key };
}

/* ================================================================ baked soft ground shadow + contact AO */
const _flatVS = /* glsl */`
  uniform vec3 uDir; uniform float uFall; varying float vFade;
  void main(){
    vec4 p = vec4(position, 1.);
    #ifdef USE_INSTANCING
      p = instanceMatrix * p;
    #endif
    vec4 w = modelMatrix * p;
    vec2 push = uDir.xz / uDir.y * max(w.y, 0.);
    vFade = exp(-length(push) / uFall);            // the shadow thins with distance from where it's cast
    w.xz -= push; w.y = 0.;
    gl_Position = projectionMatrix * viewMatrix * w;
  }`;
/** Bakes the shadow `root`'s shadow-casting meshes throw on the paper (y = 0) and returns a plane showing it. */
export function bakeGround(renderer, scene, root, { res = 1024, keySamples = 72, aoSamples = 40, keyK = .5, aoK = .36, peak = .58, color = HW.shadow, seed = 3 } = {}) {
  root.updateMatrixWorld(true);
  const box = new THREE.Box3().setFromObject(root), h = Math.max(.001, box.max.y);
  const AO_MIN = D(58), tanMin = Math.tan(AO_MIN);                        // AO only from high up: contact, not a skirt
  const reach = Math.max(h / tanMin, h / Math.tan(Math.asin(HW.shadowDir.y) - HW.sunCone));
  const x0 = box.min.x - reach, x1 = box.max.x + reach, z0 = box.min.z - reach, z1 = box.max.z + reach;
  const cam = new THREE.OrthographicCamera(x0 - (x0 + x1) / 2, x1 - (x0 + x1) / 2, (z1 - z0) / 2, -(z1 - z0) / 2, .1, 100);
  cam.position.set((x0 + x1) / 2, 50, (z0 + z1) / 2); cam.up.set(0, 0, -1); cam.lookAt((x0 + x1) / 2, 0, (z0 + z1) / 2); cam.updateMatrixWorld();
  const sil = new THREE.WebGLRenderTarget(res, res, { depthBuffer: false });
  const acc = new THREE.WebGLRenderTarget(res, res, { type: THREE.HalfFloatType, depthBuffer: false });
  const flat = new THREE.ShaderMaterial({ uniforms: { uDir: { value: new THREE.Vector3() }, uFall: { value: h * 1.1 } }, vertexShader: _flatVS, fragmentShader: 'varying float vFade; void main(){ gl_FragColor = vec4(vFade); }', side: THREE.DoubleSide, depthTest: false, depthWrite: false, blending: THREE.CustomBlending, blendEquation: THREE.MaxEquation, blendSrc: THREE.OneFactor, blendDst: THREE.OneFactor });
  const quadGeo = new THREE.PlaneGeometry(2, 2);
  const addMat = new THREE.ShaderMaterial({ uniforms: { t: { value: sil.texture }, w: { value: 0 } }, vertexShader: 'varying vec2 vUv; void main(){ vUv = uv; gl_Position = vec4(position.xy, 0., 1.); }', fragmentShader: 'uniform sampler2D t; uniform float w; varying vec2 vUv; void main(){ gl_FragColor = vec4(vec3(texture2D(t, vUv).r * w), 1.); }', blending: THREE.AdditiveBlending, depthTest: false, depthWrite: false });
  const quad = new THREE.Mesh(quadGeo, addMat); quad.frustumCulled = false; const qs = new THREE.Scene(); qs.add(quad);
  // hide everything that isn't a shadow caster in root
  const hidden = [];
  scene.traverse(o => { if ((o.isMesh || o.isPoints || o.isLine || o.isSprite) && o.visible) { let inRoot = false; for (let p = o; p; p = p.parent) if (p === root) inRoot = true; if (!inRoot || !o.castShadow) { o.visible = false; hidden.push(o); } } });
  const prevOverride = scene.overrideMaterial, prevRT = renderer.getRenderTarget(), prevCol = renderer.getClearColor(new THREE.Color()), prevA = renderer.getClearAlpha(), prevScissor = renderer.getScissorTest();
  renderer.setScissorTest(false);
  renderer.setClearColor(0x000000, 0);
  renderer.setRenderTarget(acc); renderer.clear(true, false, false);
  scene.overrideMaterial = flat;
  const r = rng(seed), k = HW.shadowDir, t1 = new THREE.Vector3(), t2 = new THREE.Vector3(), d = new THREE.Vector3();
  t1.crossVectors(k, new THREE.Vector3(0, 1, 0)).normalize(); t2.crossVectors(k, t1).normalize();
  const pass = (dir, w) => {
    flat.uniforms.uDir.value.copy(dir);
    renderer.setRenderTarget(sil); renderer.clear(true, false, false); renderer.render(scene, cam);
    addMat.uniforms.w.value = w; renderer.setRenderTarget(acc); renderer.render(qs, cam);
  };
  for (let i = 0; i < keySamples; i++) {                                  // area sun: uniform disc of directions
    const a = (i + r()) / keySamples * Math.PI * 2 * 7.1, rad = Math.sqrt((i + .5) / keySamples) * HW.sunCone;
    d.copy(k).addScaledVector(t1, Math.cos(a) * rad).addScaledVector(t2, Math.sin(a) * rad).normalize();
    pass(d, keyK / keySamples);
  }
  for (let i = 0; i < aoSamples; i++) {                                   // sky: cosine-weighted, above AO_MIN
    const u = (i + r()) / aoSamples, phi = r() * Math.PI * 2, cmax = Math.cos(AO_MIN), ct = Math.sqrt(1 - u * (1 - cmax * cmax));
    const st = Math.sqrt(1 - ct * ct);   // st = sin(elev) (up component)
    d.set(Math.cos(phi) * ct, st, Math.sin(phi) * ct).normalize();
    pass(d, aoK / aoSamples);
  }
  scene.overrideMaterial = prevOverride;
  for (const o of hidden) o.visible = true;
  // one density across the row: scale so the umbra reaches `peak`, whatever the object's shape
  let gain = 1;
  { const buf = new Uint16Array(res * res * 4); renderer.readRenderTargetPixels(acc, 0, 0, res, res, buf);
    const vals = []; for (let i = 0; i < buf.length; i += 16) { const v = THREE.DataUtils.fromHalfFloat(buf[i]); if (v > .01) vals.push(v); }
    vals.sort((a, b) => a - b); const p = vals.length ? vals[Math.floor(vals.length * .985)] : 1; gain = peak / Math.max(p, .05); }
  renderer.setRenderTarget(prevRT); renderer.setClearColor(prevCol, prevA); renderer.setScissorTest(prevScissor);
  sil.dispose(); flat.dispose(); addMat.dispose(); quadGeo.dispose();
  const mat = new THREE.ShaderMaterial({
    transparent: true, depthWrite: false,
    uniforms: { t: { value: acc.texture }, uCol: { value: new THREE.Color(color) }, uGain: { value: gain } },
    vertexShader: 'varying vec2 vUv; void main(){ vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.); }',
    fragmentShader: /* glsl */`uniform sampler2D t; uniform vec3 uCol; uniform float uGain; varying vec2 vUv;
      void main(){ float a = texture2D(t, vUv).r * uGain; a = max(a - .02, 0.) * 1.04; vec2 e = min(vUv, 1. - vUv); a *= smoothstep(0., .04, min(e.x, e.y));
        gl_FragColor = vec4(uCol, clamp(a, 0., 1.)); }`,
  });
  mat.toneMapped = false;
  const plane = new THREE.Mesh(new THREE.PlaneGeometry(x1 - x0, z1 - z0), mat);
  plane.rotation.x = -Math.PI / 2; plane.position.set((x0 + x1) / 2, .0004, (z0 + z1) / 2); plane.renderOrder = -1;
  scene.add(plane);
  // the shadow's footprint, for framing: where the sun throws each silhouette point on the paper (its visible tail)
  const foot = [], ky = Math.sin(Math.asin(k.y)), kxz = Math.sqrt(1 - ky * ky), kh = Math.hypot(k.x, k.z);
  for (const p of silhouettePoints(root, 600)) { const tt = p.y / ky * kxz / kh; foot.push(new THREE.Vector3(p.x - k.x * tt, 0, p.z - k.z * tt)); }
  return { plane, foot };
}

/* ================================================================ woods */
const _texCache = {};
function wrapNoise(seed, n) {   // periodic value noise on an n×n lattice
  const r = rng(seed), g = new Float32Array(n * n); for (let i = 0; i < g.length; i++) g[i] = r();
  return (x, y) => {
    const xi = Math.floor(x), yi = Math.floor(y), xf = x - xi, yf = y - yi, u = xf * xf * (3 - 2 * xf), v = yf * yf * (3 - 2 * yf);
    const X0 = ((xi % n) + n) % n, Y0 = ((yi % n) + n) % n, X1 = (X0 + 1) % n, Y1 = (Y0 + 1) % n;
    const a = g[Y0 * n + X0], b = g[Y0 * n + X1], c = g[Y1 * n + X0], d = g[Y1 * n + X1];
    return a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v;
  };
}
function normalFromHeight(hgt, S, strength) {
  const c = makeCanvas(S, S), g = c.getContext('2d'), im = g.createImageData(S, S);
  for (let y = 0; y < S; y++) for (let x = 0; x < S; x++) {
    const i = y * S + x, l = hgt[y * S + (x - 1 + S) % S], r = hgt[y * S + (x + 1) % S], u = hgt[((y - 1 + S) % S) * S + x], d = hgt[((y + 1) % S) * S + x];
    let nx = (l - r) * strength, ny = (d - u) * strength, nz = 1; const L = Math.hypot(nx, ny, nz);
    im.data[i * 4] = (nx / L * .5 + .5) * 255; im.data[i * 4 + 1] = (ny / L * .5 + .5) * 255; im.data[i * 4 + 2] = (nz / L * .5 + .5) * 255; im.data[i * 4 + 3] = 255;
  }
  g.putImageData(im, 0, 0);
  return c;
}
const tex = (c, srgb) => { const t = canvasTexture(c, { srgb }); t.wrapS = t.wrapT = THREE.RepeatWrapping; t.generateMipmaps = true; t.minFilter = THREE.LinearMipmapLinearFilter; return t; };

/** The page's hinoki (js/models/woods.js), for UVs in metres; grain runs along v. */
export function hinokiMaterial({ tint = 1, seed = 3, rough = 1, contrast = .52 } = {}) {
  const h = perMetre(hinokiTextures({ seed, contrast, ringSpacing: 2.4 }), 1);
  return new THREE.MeshPhysicalMaterial({
    map: h.map, normalMap: h.normalMap, roughnessMap: h.roughnessMap, roughness: rough, normalScale: new THREE.Vector2(.4, .4),
    color: new THREE.Color(tint * .93, tint * .92, tint * .91), clearcoat: .1, clearcoatRoughness: .5, envMapIntensity: .9,
  });
}
/** Hinoki end grain (sawn ends, cut sections). */
export function hinokiEndMaterial({ tint = 1, seed = 5 } = {}) {
  const h = perMetre(hinokiEndTextures({ seed }), 1);
  return new THREE.MeshPhysicalMaterial({ map: h.map, normalMap: h.normalMap, roughnessMap: h.roughnessMap, roughness: 1, normalScale: new THREE.Vector2(.5, .5), color: new THREE.Color(tint, tint, tint), envMapIntensity: .8 });
}

/** Yakisugi: charred cedar with 2–4 cm alligator crackle; one tile = .3 m. */
export const YAKI_TILE = .3;
function yakiTextures() {
  if (_texCache.yaki) return _texCache.yaki;
  // yakisugi char: raised, rounded blisters 2.5 cm across × ~4 cm along the grain, split by deep cracks; grey ash on
  // the crowns; dead matte. One tile = YAKI_TILE (.3 m): 12 × 7 cells.
  const S = 1024, CX = 12, CY = 7;
  const r = rng(21), fp = [];
  for (let j = 0; j < CY; j++) for (let i = 0; i < CX; i++) fp.push([(i + .15 + r() * .7) / CX, (j + .12 + r() * .76) / CY, r(), .8 + r() * .4]);
  const grain = wrapNoise(31, 256), blot = wrapNoise(32, 10), wx = wrapNoise(33, 24), wy = wrapNoise(34, 12), cw = wrapNoise(35, 40), ash = wrapNoise(37, 20), fine = wrapNoise(38, 128);
  const col = makeCanvas(S, S), cg = col.getContext('2d'), ci = cg.createImageData(S, S);
  const rgh = makeCanvas(S, S), rg = rgh.getContext('2d'), ri = rg.createImageData(S, S);
  const hgt = new Float32Array(S * S);
  for (let y = 0; y < S; y++) for (let x = 0; x < S; x++) {
    let u = x / S, v = y / S;
    u += .008 * (wx(u * 24, v * 24) - .5); v += .014 * (wy(u * 12, v * 12) - .5);
    u = (u + 1) % 1; v = (v + 1) % 1;
    const gi = Math.floor(u * CX), gj = Math.floor(v * CY);
    let d1 = 9, d2 = 9, id = 0;
    for (let dj = -1; dj <= 1; dj++) for (let di = -1; di <= 1; di++) {
      const ii = (gi + di + CX) % CX, jj = (gj + dj + CY) % CY, p = fp[jj * CX + ii];
      const px = (p[0] + (gi + di - ii) / CX - u) * CX, py = (p[1] + (gj + dj - jj) / CY - v) * CY;
      const dd = Math.hypot(px, py) / p[3];
      if (dd < d1) { d2 = d1; d1 = dd; id = p[2]; } else if (dd < d2) d2 = dd;
    }
    const e = d2 - d1, w = .07 + .07 * cw(u * 40, v * 40);
    const crack = 1 - clamp((e - w * .3) / w);                    // 1 in a crack
    const dome = Math.sqrt(clamp(e / .5)) * (1 - crack);          // rounded blister, highest mid-cell
    const g1 = grain(u * 256, v * 7) - .5, b = blot(u * 10, v * 10), f = fine(u * 128, v * 128) - .5;
    const crown = clamp((dome - .72) / .28), ashy = crown * clamp((ash(u * 20, v * 20) - .45) * 3);
    const i = y * S + x;
    let val = (15 + id * 6 + b * 7 + g1 * 6 + f * 5 + dome * 9) * (1 - .88 * crack);
    val = val + ashy * 38;
    ci.data[i * 4] = val; ci.data[i * 4 + 1] = val * .99; ci.data[i * 4 + 2] = val * 1.01; ci.data[i * 4 + 3] = 255;
    ri.data[i * 4] = 255 * (1 - .75 * crack) * (.75 + .25 * dome); ri.data[i * 4 + 1] = clamp(.9 + .06 * crack + f * .06) * 255; ri.data[i * 4 + 2] = 0; ri.data[i * 4 + 3] = 255;
    hgt[i] = dome * 1.1 - crack * .9 + g1 * .12 + f * .08;
  }
  cg.putImageData(ci, 0, 0); rg.putImageData(ri, 0, 0);
  _texCache.yaki = { map: tex(col, true), rough: tex(rgh, false), normal: tex(normalFromHeight(hgt, S, 2.8), false) };
  return _texCache.yaki;
}
export function yakisugiMaterial({ tint = 1 } = {}) {
  const t = yakiTextures();
  const m = new THREE.MeshPhysicalMaterial({
    map: t.map, roughnessMap: t.rough, normalMap: t.normal, normalScale: new THREE.Vector2(1, 1), aoMap: t.rough, aoMapIntensity: 1,
    color: new THREE.Color(tint * .78, tint * .84, tint * 1.0), roughness: 1, envMapIntensity: .3, specularIntensity: .22,
  });
  for (const k of ['map', 'roughnessMap', 'normalMap', 'aoMap']) { m[k] = m[k].clone(); m[k].repeat.set(1 / YAKI_TILE, 1 / YAKI_TILE); m[k].needsUpdate = true; }
  return m;
}

/* ================================================================ helpers */
/** alphaMap reads the green channel: flatten a canvas's alpha onto black so soft edges survive. */
export function maskTex(c) { const m = makeCanvas(c.width, c.height), g = m.getContext('2d'); g.fillStyle = '#000'; g.fillRect(0, 0, m.width, m.height); g.drawImage(c, 0, 0); return canvasTexture(m, { srgb: false }); }
/** Box-projected UVs in metres (u along the face's horizontal axis, v up), so textures keep real scale. The axis is
    picked per triangle from its geometric normal (a rounded box's corner vertices carry blended normals). Returns a
    non-indexed copy. */
export function boxUV(src, scale = 1, { u0 = 0, v0 = 0, mirrorX = false, swap = false } = {}) {
  const geo = src.index ? src.toNonIndexed() : src;
  if (!geo.attributes.normal) geo.computeVertexNormals();
  const p = geo.attributes.position, uv = new Float32Array(p.count * 2);
  const a = new THREE.Vector3(), b = new THREE.Vector3(), c = new THREE.Vector3(), n = new THREE.Vector3();
  for (let t = 0; t < p.count; t += 3) {
    a.fromBufferAttribute(p, t); b.fromBufferAttribute(p, t + 1); c.fromBufferAttribute(p, t + 2);
    n.subVectors(c, b).cross(a.clone().sub(b));
    const ax = Math.abs(n.x), ay = Math.abs(n.y), az = Math.abs(n.z);
    for (let k = 0; k < 3; k++) {
      const i = t + k, x = mirrorX ? Math.abs(p.getX(i)) : p.getX(i);
      let u, v;
      if (ay >= ax && ay >= az) { u = x; v = p.getZ(i); } else if (ax >= az) { u = p.getZ(i); v = p.getY(i); } else { u = x; v = p.getY(i); }
      if (swap) [u, v] = [v, u];
      uv[i * 2] = u * scale + u0; uv[i * 2 + 1] = v * scale + v0;
    }
  }
  geo.setAttribute('uv', new THREE.BufferAttribute(uv, 2));
  if (geo !== src) src.dispose();
  return geo;
}
/** World-space sample points of every shadow-casting mesh under root (for silhouette-accurate framing). */
export function silhouettePoints(root, max = 5000) {
  root.updateMatrixWorld(true);
  const pts = [], v = new THREE.Vector3(), m = new THREE.Matrix4();
  let total = 0; root.traverse(o => { if (o.isMesh && o.castShadow) total += o.geometry.attributes.position.count * (o.isInstancedMesh ? o.count : 1); });
  const step = Math.max(1, Math.floor(total / max));
  let n = 0;
  root.traverse(o => {
    if (!o.isMesh || !o.castShadow) return;
    const P = o.geometry.attributes.position, inst = o.isInstancedMesh ? o.count : 1;
    for (let k = 0; k < inst; k++) {
      if (o.isInstancedMesh) { o.getMatrixAt(k, m); m.premultiply(o.matrixWorld); } else m.copy(o.matrixWorld);
      for (let i = 0; i < P.count; i++, n++) if (n % step === 0) pts.push(v.fromBufferAttribute(P, i).applyMatrix4(m).clone());
    }
  });
  return pts;
}

/** The shared camera. Fits `points` so their projected height is HF of the card with the lowest point on the ground
    line; keeps them within maxW and `shadow` points inside the frame. mode 'orbit' (panel, battery) or 'truck' (phone:
    the view direction never changes, so a face-on screen stays face-on). */
export function cardCamera(points, { shadow = [], mode = 'orbit', HF: HF0 = HW.HF, HFn = null, GL = HW.GL, XC = HW.XC, maxW = HW.maxW, topPx = 32, az = HW.az, el = HW.el, fov = HW.fov } = {}) {
  let HF = HF0;
  const camera = new THREE.PerspectiveCamera(fov, 5 / 4, .01, 100);
  const box = new THREE.Box3().setFromPoints(points), tgt0 = box.getCenter(new THREE.Vector3());
  const st = { d: box.getSize(new THREE.Vector3()).length() * 2.2, aspect: 0, tgt: tgt0.clone() };
  const _v = new THREE.Vector3(), R = new THREE.Vector3(), U = new THREE.Vector3();
  const place = (a, e, d, t) => { camera.position.set(t.x + Math.sin(a) * Math.cos(e) * d, t.y + Math.sin(e) * d, t.z + Math.cos(a) * Math.cos(e) * d); camera.lookAt(t); camera.updateMatrixWorld(); };
  const bounds = (pts) => { let x0 = 1e9, x1 = -1e9, y0 = 1e9, y1 = -1e9; for (const p of pts) { _v.copy(p).project(camera); x0 = Math.min(x0, _v.x); x1 = Math.max(x1, _v.x); y0 = Math.min(y0, _v.y); y1 = Math.max(y1, _v.y); } return { x0, x1, y0, y1 }; };
  function fit(aspect, hpx = 336) {
    camera.aspect = aspect; camera.updateProjectionMatrix();
    const t = tgt0.clone(); let d = st.d;
    for (let it = 0; it < 14; it++) {
      place(az, el, d, t);
      const b = bounds(points), s = shadow.length ? bounds(shadow) : b;
      let k = (b.y1 - b.y0) / (2 * HF);
      k = Math.max(k, (b.x1 - b.x0) / (2 * maxW));
      // the shadow must end inside the card once the object is re-centred
      const cb = (b.x0 + b.x1) / 2, gl = 1 - 2 * GL;
      k = Math.max(k, (s.x1 - cb) / (.96 - XC), (cb - s.x0) / (.96 + XC), (s.y1 - b.y0) / (.96 - gl));
      k = Math.max(k, (b.y1 - b.y0) / ((1 - 2 * topPx / hpx) - gl));          // always ≥ topPx clear above
      d *= k;
      R.setFromMatrixColumn(camera.matrixWorld, 0); U.setFromMatrixColumn(camera.matrixWorld, 1);
      const h = Math.tan(D(fov / 2)) * d;
      const bx = ((b.x0 + b.x1) / 2) / k - XC, by = b.y0 / k - (1 - 2 * GL);
      t.addScaledVector(R, bx * h * aspect).addScaledVector(U, by * h);
    }
    st.d = d; st.tgt.copy(t); st.aspect = aspect;
  }
  const cur = { az, el, x: 0, y: 0 };
  return {
    camera,
    update(dt, t, s) {
      const a = s.w / s.h, hf = HFn && s.w < 400 ? HFn : HF0; if (Math.abs(a - st.aspect) > 1e-3 || hf !== HF || Math.abs(s.h - (st.hpx || 0)) > .5) { HF = hf; st.hpx = s.h; fit(a, s.h); }
      const px = s.hover ? clamp(s.pointer.x, -1, 1) : 0, py = s.hover ? clamp(s.pointer.y, -1, 1) : 0, m = REDUCED ? 0 : 1;
      if (mode === 'truck') {
        cur.x = damp(cur.x, m * (Math.sin(t * .21) * .006 + px * .02), 3, dt); cur.y = damp(cur.y, m * (Math.sin(t * .16) * .004 - py * .014), 3, dt);
        place(az, el, st.d, st.tgt);
        R.setFromMatrixColumn(camera.matrixWorld, 0); U.setFromMatrixColumn(camera.matrixWorld, 1);
        const h = Math.tan(D(fov / 2)) * st.d;
        camera.position.addScaledVector(R, cur.x * h).addScaledVector(U, cur.y * h); camera.updateMatrixWorld();
      } else {
        cur.az = damp(cur.az, az + m * (Math.sin(t * .21) * .02 + px * .06), 3, dt);
        cur.el = damp(cur.el, el + m * (Math.sin(t * .16) * .007 - py * .025), 3, dt);
        place(cur.az, cur.el, st.d, st.tgt);
      }
    },
  };
}
