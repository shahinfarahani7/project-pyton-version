/* Sunset — the garden (agent A): raked gravel, moss banks, set stones, stepping stones, a kasuga tōrō, a cloud-pruned pine.
   export async function buildGarden({ seed = 1, size = [20, 14], path, rocks, lantern, pine, moss, glow = 0, rake = 'x' } = {})
     -> { group, gravel, setGlow(v), update(t, wind), features: { lantern: Vector3|null, pine: Vector3|null } }
   All positions are garden-local metres (x right, z toward the viewer), ground at y = 0; the group is centred on the gravel.
   Defaults compose a small karesansui on their own; scenes pass their own layout.
   - path:    [[x, z], ...] stepping-stone centres (tobi-ishi), flat granite slabs sitting 5 cm proud
   - rocks:   [[x, z, size, yaw], ...] set stones; gravel is raked in rings around each
   - lantern: [x, z] kasuga-dōrō (glowing hibukuro, setGlow 0..1)
   - pine:    [x, z, yaw] low cloud-pruned pine (niwaki) with needle pads
   - moss:    [[x, z, rx, rz], ...] moss islands (sugigoke mounds) */
import { THREE, pbrMaterial, canvasTexture, makeCanvas, rng, clamp, lerp } from '../core.js';
import { mergeVertices, mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';
import { stoneMaterial, tune, paint, Bucket, translucencyGLSL, rimGLSL, RIM_OFF, setRim, bledTexture, noise3, flatStone } from './house.js';
export { flatStone };
import { tube } from './sakura.js';

function leafCanvas() {
  // 2 x 2 atlas of small-leaved foliage (satsuki azalea / box): overlapping glossy ellipses with midribs
  const c = makeCanvas(512, 512), g = c.getContext('2d'), R = rng(93);
  for (let v = 0; v < 4; v++) {
    const ox = (v % 2) * 256, oy = (v >> 1) * 256;
    g.save(); g.beginPath(); g.rect(ox, oy, 256, 256); g.clip();
    for (let k = 0; k < 340; k++) {
      const a = R() * 6.28, d = Math.sqrt(R()) * 112, x = ox + 128 + Math.cos(a) * d, y = oy + 128 + Math.sin(a) * d * .9;
      const L = 9 + R() * 8, W = L * (.42 + R() * .12), rot = R() * 6.28, sh = 30 + R() * 55;
      g.save(); g.translate(x, y); g.rotate(rot);
      g.fillStyle = `rgb(${sh * .5 | 0},${sh * .92 | 0},${sh * .34 | 0})`; g.beginPath(); g.ellipse(0, 0, L, W, 0, 0, 7); g.fill();
      g.restore();
    }
    g.restore();
  }
  return c;
}

/** Weathered boulder: welded icosphere, displaced by noise, with a few cleavage planes, partly buried. */
export function rockGeometry(seed, size = 1, squash = [1.15, .62, .9], detail = 4) {
  let g = new THREE.IcosahedronGeometry(1, detail);
  g.deleteAttribute('normal'); g.deleteAttribute('uv');
  g = mergeVertices(g);
  const n = noise3(seed), R = rng(seed * 31 + 1), P = g.attributes.position, v = new THREE.Vector3();
  const planes = Array.from({ length: 7 }, () => ({ n: new THREE.Vector3(R() - .5, R() * .7 - .15, R() - .5).normalize(), d: .55 + R() * .25 }));
  for (let i = 0; i < P.count; i++) {
    v.fromBufferAttribute(P, i);
    let r = 1 + (n(v.x * 1.3 + 3, v.y * 1.3, v.z * 1.3, 4) - .5) * .7 + (n(v.x * 4, v.y * 4, v.z * 4, 2) - .5) * .16;
    v.multiplyScalar(r);
    for (const pl of planes) { const d = v.dot(pl.n); if (d > pl.d) v.addScaledVector(pl.n, -(d - pl.d) * .85); }   // cleavage facets
    v.set(v.x * squash[0], v.y * squash[1], v.z * squash[2]).multiplyScalar(size);
    P.setXYZ(i, v.x, v.y, v.z);
  }
  g.computeVertexNormals();
  return g;
}

function needleCanvas() {
  // 2 x 2 atlas of black-pine needle tufts: stiff paired needles fanning up from a twig tip, dense at the base
  const c = makeCanvas(512, 512), g = c.getContext('2d'), R = rng(71);
  g.lineCap = 'round';
  for (let v = 0; v < 4; v++) {
    const ox = (v % 2) * 256, oy = (v >> 1) * 256;
    g.save(); g.beginPath(); g.rect(ox, oy, 256, 256); g.clip();
    for (let k = 0; k < 9; k++) {
      const x = ox + 40 + R() * 176, y = oy + 150 + R() * 80, n = 34 + (R() * 20 | 0), L = 60 + R() * 50;
      for (let i = 0; i < n; i++) {
        const a = -Math.PI / 2 + (R() - .5) * 2.4, l = L * (.55 + R() * .45), sh = 30 + R() * 44;
        g.strokeStyle = `rgb(${sh * .52 | 0},${sh * .95 | 0},${sh * .42 | 0})`; g.lineWidth = 1.3 + R() * .9;
        g.beginPath(); g.moveTo(x, y); g.quadraticCurveTo(x + Math.cos(a) * l * .5, y + Math.sin(a) * l * .5 - 5, x + Math.cos(a) * l, y + Math.sin(a) * l); g.stroke();
      }
    }
    g.restore();
  }
  return c;
}

export async function buildGarden({ seed = 1, size = [20, 14], path = null, rocks = null, lantern = undefined, pine = undefined, moss = null, glow = 0, rake = 'x', court = null, mossGround = false, shrubs = [], hedge = null, edge = null, sand = null, farFade = true, shape = null, mossAlbedo = .125 } = {}) {
  const R = rng(seed * 7717 + 3);
  const group = new THREE.Group(); group.name = 'garden';
  const [W, D] = size;
  path = path || [[3.2, 5.6], [2.6, 4.7], [2.9, 3.7], [2.3, 2.8], [2.5, 1.8], [2.0, .9]];
  rocks = rocks || [[-4.5, 1.5, .8, .4], [-3.6, 2.3, .45, 1.2], [-6.5, -1.5, .55, 2.1]];
  if (lantern === undefined) lantern = [4.4, 2.6];
  if (pine === undefined) pine = [-7.2, -3.4, .3];
  moss = moss || [[-4.2, 1.8, 1.6, 1.2], [3.2, 3.2, 1.8, 3.2], [-7, -3, 2, 1.4], [6.5, -2, 2.2, 1.6]];

  /* ---- raked gravel */
  // court: [x0, z0, x1, z1] limits the raked gravel to a courtyard edged with granite kerbs (default: the whole size)
  const C = court || [-W / 2, -D / 2, W / 2, D / 2];
  const gg = new THREE.PlaneGeometry(C[2] - C[0], C[3] - C[1], 1, 1).rotateX(-Math.PI / 2).translate((C[0] + C[2]) / 2, 0, (C[1] + C[3]) / 2);
  { const P = gg.attributes.position, uv = gg.attributes.uv; for (let i = 0; i < P.count; i++) uv.setXY(i, P.getX(i), P.getZ(i)); }
  paint(gg);
  const gm = await pbrMaterial('ganges_river_pebbles', { repeat: [1 / .42, 1 / .42], normal: .8, roughness: .9, envMapIntensity: .7 });
  const rings = rocks.map(([x, z, s]) => new THREE.Vector4(x, z, s * 1.05, s * 1.05 + .55));
  if (lantern) rings.push(new THREE.Vector4(lantern[0], lantern[1], .42, .95));
  while (rings.length < 8) rings.push(new THREE.Vector4(1e4, 1e4, 0, 0));
  const gu = { uRing: { value: rings.slice(0, 8) }, uPitch: { value: sand?.pitch ?? .085 }, uAmp: { value: sand?.amp ?? .011 }, uAxis: { value: rake === 'x' ? 0 : 1 }, uFar: { value: farFade && !sand ? 1 : 0 } };
  tune(gm, {
    key: 'gravel', sat: .2, gain: 1.9, extra: sh => {
      Object.assign(sh.uniforms, gu);
      sh.vertexShader = sh.vertexShader.replace('#include <common>', '#include <common>\nvarying vec3 vGP; varying vec3 vGW;')
        .replace('#include <begin_vertex>', '#include <begin_vertex>\n vGP = position; vGW = (modelMatrix * vec4(position, 1.)).xyz;');
      sh.fragmentShader = sh.fragmentShader.replace('#include <common>', `#include <common>
        varying vec3 vGP; varying vec3 vGW; uniform vec4 uRing[8]; uniform float uPitch, uAmp, uAxis, uFar; uniform vec2 uOff;
        float rakeH(vec2 p){
          p -= uOff; float h = cos(6.2831853 * (uAxis < .5 ? p.y : p.x) / uPitch);
          for (int i = 0; i < 8; i++) { vec4 Rg = uRing[i]; float r = length(p - Rg.xy) - Rg.z;
            if (r < Rg.w - Rg.z) { float k = smoothstep(Rg.w - Rg.z, Rg.w - Rg.z - .05, r); h = mix(h, cos(6.2831853 * max(r, 0.) / uPitch), k); } }
          return h; }`)
        .replace('#include <map_fragment>', `#include <map_fragment>
          vec2 gp = vGW.xz;
          { vec2 q = mat2(.8, -.6, .6, .8) * vMapUv * .61 + vec2(.37, .71);
            vec4 s2 = texture2D(map, q);
            float bl = smoothstep(.3, .7, .5 + .5 * sin(gp.x * .83 + sin(gp.y * .61) * 1.7) * cos(gp.y * .57 + gp.x * .21));
            vec3 alt = s2.rgb * diffuse;
            diffuseColor.rgb = mix(diffuseColor.rgb, alt, bl);
            float far = smoothstep(7., 24., length(vGW.xz - cameraPosition.xz));
            vec3 meanCol = texture2D(map, vMapUv, 12.).rgb * diffuse;          // the map's own average: any map fades correctly
            diffuseColor.rgb = mix(diffuseColor.rgb, meanCol * 1.05, far * .85 * uFar); } float fw = max(fwidth(gp.x), fwidth(gp.y)) / uPitch; float rk = smoothstep(.45, .15, fw);
          float hh = rakeH(gp);
          diffuseColor.rgb *= mix(1., .78 + .22 * (hh * .5 + .5), rk);`)
        .replace('#include <normal_fragment_maps>', `#include <normal_fragment_maps>
          { float e = .006; float h0 = rakeH(gp), hx = rakeH(gp + vec2(e, 0.)), hz = rakeH(gp + vec2(0., e));
            vec3 gw = vec3(-(hx - h0) / e, 0., -(hz - h0) / e) * uAmp * 6.2831853 / 6.2831853 * rk;
            normal = normalize(normal + mat3(viewMatrix) * gw * 1.4); }`);
    },
  });
  gm.color.setRGB(1, .97, .92);
  if (sand) {   // raked sand: a flat pale albedo from `sand.color` (sRGB 0..1) with fine grain from the pebble normal only
    const sc = sand.color || [.66, .64, .6];
    const t1 = new THREE.DataTexture(new Uint8Array([sc[0] * 255, sc[1] * 255, sc[2] * 255, 255]), 1, 1); t1.colorSpace = THREE.SRGBColorSpace; t1.wrapS = t1.wrapT = THREE.RepeatWrapping; t1.needsUpdate = true;
    gm.map = t1; gm.normalScale.set(.25, .25); gm.color.setRGB(.36, .36, .36);
  }
  const gravel = new THREE.Mesh(gg, gm); gravel.receiveShadow = true; gravel.name = 'gravel';
  group.add(gravel);
  // rings are given in garden-local coords; the shader works in world space
  gu.uOff = { value: new THREE.Vector2() };
  gravel.onBeforeRender = () => gu.uOff.value.set(group.position.x, group.position.z);

  const B = new Bucket();
  const aoGround = (x, y, z) => 1 - .5 * Math.exp(-Math.max(0, y) / .12);

  // ground height (garden-local): level gravel court, turf that creeps over its wandering edge, optional drop-offs
  const nzG = noise3(seed + 5);
  const groundY = (x, z) => {
    if (!mossGround) return 0;
    const dOut = Math.max(C[0] - x, x - C[2], C[1] - z, z - C[3]) + (nzG(x * .9, 3, z * .9, 2) - .5) * .7;
    let y = dOut < 0 ? -.02 : .006 + .05 * clamp(dOut / 1.4) + (nzG(x * .35, 0, z * .35, 3) - .5) * .08 * clamp(dOut / 2);
    if (edge) { const [[ex0, ez0], [ex1, ez1]] = edge, dx = ex1 - ex0, dz = ez1 - ez0, sd = ((x - ex0) * dz - (z - ez0) * dx) / Math.hypot(dx, dz); if (sd < 0) y -= Math.min(6, sd * sd * 3 - sd * 1.5); }
    if (shape) y = shape(x, z, y);   // a scene's own terrain (garden-local coordinates)
    return y;
  };
  if (mossGround) {
    const mg = new THREE.PlaneGeometry(W, D, 170, 150).rotateX(-Math.PI / 2);
    const P = mg.attributes.position;
    for (let i = 0; i < P.count; i++) P.setY(i, groundY(P.getX(i), P.getZ(i)));
    mg.computeVertexNormals();
    { const uv = mg.attributes.uv; for (let i = 0; i < P.count; i++) uv.setXY(i, P.getX(i), P.getZ(i)); }
    B.add('moss', paint(mg, [1, 1, 1], (x, y) => .85 + y));
  }
  /* ---- moss islands: soft mounds whose edges dip under the gravel */
  const mossG = [];
  for (const [mx, mz, rx, rz] of moss) {
    const seg = 56, rs = 9, pos = [], idx = [], nz = noise3(Math.round(mx * 100 + mz * 7));
    const hgt = .07 + R() * .05;
    pos.push(mx, hgt, mz);
    for (let j = 1; j <= rs; j++) for (let i = 0; i < seg; i++) {
      const a = i / seg * Math.PI * 2, t = j / rs;
      const wob = 1 + (nz(Math.cos(a) * 1.7 + 5, Math.sin(a) * 1.7, 0, 3) - .5) * .7;
      const x = mx + Math.cos(a) * rx * t * wob, z = mz + Math.sin(a) * rz * t * wob;
      const y = hgt * Math.pow(1 - t * t, .65) + (nz(x * 2.2, 0, z * 2.2, 2) - .5) * .04 * (1 - t) - (j === rs ? .012 : 0);
      pos.push(x, y, z);
    }
    for (let i = 0; i < seg; i++) idx.push(0, 1 + (i + 1) % seg, 1 + i);
    for (let j = 1; j < rs; j++) for (let i = 0; i < seg; i++) {
      const a = 1 + (j - 1) * seg + i, b = 1 + (j - 1) * seg + (i + 1) % seg, c = a + seg, d = b + seg;
      idx.push(a, b, c, b, d, c);
    }
    const g = new THREE.BufferGeometry(); g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3)); g.setIndex(idx); g.computeVertexNormals();
    const P = g.attributes.position, uv = new Float32Array(P.count * 2); for (let i = 0; i < P.count; i++) { uv[i * 2] = P.getX(i); uv[i * 2 + 1] = P.getZ(i); }
    g.setAttribute('uv', new THREE.BufferAttribute(uv, 2));
    mossG.push(B.add('moss', paint(g, [1, 1, 1], (x, y) => .75 + y * 2)));
  }
  // calibrated so the turf's mean linear albedo is `mossAlbedo` (≈ .12: real short moss/grass); a scene darkens it with .color
  const mossM = new THREE.MeshStandardMaterial({ color: new THREE.Color(1, 1, 1), roughness: .96 });
  const mossK = (mossAlbedo / .039).toFixed(3);   // .039 = mean luminance of the procedural turf below at k = 1
  tune(mossM, {
    key: 'moss' + mossK, extra: sh => {
      sh.vertexShader = sh.vertexShader.replace('#include <common>', '#include <common>\nvarying vec3 vMP;').replace('#include <begin_vertex>', '#include <begin_vertex>\n vMP = (modelMatrix * vec4(position, 1.)).xyz;');
      sh.fragmentShader = sh.fragmentShader.replace('#include <common>', `#include <common>\nvarying vec3 vMP;
        float mh(vec2 p){ p = fract(p * vec2(.1031, .103)); p += dot(p, p.yx + 33.33); return fract((p.x + p.y) * p.x); }
        float mn(vec2 p){ vec2 i = floor(p), f = fract(p); f = f * f * (3. - 2. * f); return mix(mix(mh(i), mh(i + vec2(1, 0)), f.x), mix(mh(i + vec2(0, 1)), mh(i + vec2(1, 1)), f.x), f.y); }`)
        .replace('#include <map_fragment>', `#include <map_fragment>
          float dist = length(vMP - cameraPosition), fine = 1. - smoothstep(.0012, .0045, max(fwidth(vMP.x), fwidth(vMP.z) * .3)), mid2 = 1. - smoothstep(14., 40., dist);
          float m1 = mn(vMP.xz * 1.1), m2 = mn(vMP.xz * 4.3);
          // short turf: blade-scale streaks (anisotropic noise) and single bright tips, averaging out with distance
          // turf clumps ~10-25 cm (no sub-centimetre speckle: at page distance that read as sandpaper)
          float b1 = mn(vMP.xz * 9.), b2 = mn(vMP.xz * 21. + 3.), tips = 0.;
          vec3 mc = mix(vec3(.02, .026, .011), vec3(.05, .058, .02), m1 * .7 + (m2 - .5) * .35 * mid2 + .15);      // deep green-umber
          mc = mix(mc, vec3(.07, .06, .03), smoothstep(.7, .95, m2) * .3 * mid2);                                 // dry patches
          float blade = .78 + .44 * (b1 * .6 + b2 * .4);
          diffuseColor.rgb *= mc * blade * ${mossK};`)
        .replace('#include <normal_fragment_maps>', `#include <normal_fragment_maps>
          { float fine = 1. - smoothstep(.0012, .0045, max(fwidth(vMP.x), fwidth(vMP.z) * .3));
            vec2 q = vec2(vMP.x * 180., vMP.z * 60.); float a0 = mn(q), ax = mn(q + vec2(.35, 0.)), az = mn(q + vec2(0., .35));
            normal = normalize(normal + mat3(viewMatrix) * vec3(-(ax - a0), 0., -(az - a0)) * 0. * fine); }`)
        .replace('#include <aomap_fragment>', '#include <aomap_fragment>\n reflectedLight.indirectSpecular *= .22; reflectedLight.indirectDiffuse *= vec3(.9, 1., .8);')
        .replace('#include <lights_fragment_end>', '#include <lights_fragment_end>\n reflectedLight.directSpecular *= .25;');
    },
  });

  /* ---- set stones (with rings raked around them) */
  for (const [x, z, s, yaw] of rocks) {
    const g = rockGeometry(Math.round(x * 13 + z * 7) + seed, s, [1.2, .66 + R() * .2, .9]);
    g.rotateY(yaw || 0); g.translate(x, s * .22, z);
    B.add('rock', paint(g, [1, 1, 1], aoGround));
  }

  /* ---- stepping stones: irregular granite slabs, 5 cm proud */
  for (let i = 0; i < path.length; i++) {
    const [x, z] = path[i], r = .27 + R() * .1;
    const g = flatStone(i * 17 + seed, r, .16);
    g.rotateY(R() * Math.PI); g.translate(x, .045, z);
    B.add('slab', paint(g, [1, 1, 1], aoGround));
  }

  /* ---- kasuga tōrō */
  let lanternPos = null, lanternGlowMat = null;
  if (lantern) {
    const [lx, lz] = lantern; lanternPos = new THREE.Vector3(lx, 0, lz);
    const parts = [];
    const hex = (rt, rb, h, y, seg = 6) => { const g = new THREE.CylinderGeometry(rt, rb, h, seg, 1); g.rotateY(Math.PI / 6); g.translate(lx, y + h / 2, lz); parts.push(g); };
    hex(.3, .36, .1, 0); hex(.2, .28, .08, .1);                                     // kiso + lotus step
    const sao = new THREE.CylinderGeometry(.085, .1, .72, 16, 1); sao.translate(lx, .18 + .36, lz); parts.push(sao);
    hex(.11, .11, .04, .56, 16);                                                   // fushi ring
    hex(.28, .18, .15, .9); hex(.2, .2, .03, 1.05);                                // chūdai
    // hibukuro: six posts around a glowing core
    for (let k = 0; k < 6; k++) { const a = k / 6 * Math.PI * 2; const g = new THREE.BoxGeometry(.07, .3, .07); g.rotateY(-a); g.translate(lx + Math.cos(a) * .17, 1.08 + .15, lz + Math.sin(a) * .17); parts.push(g); }
    hex(.2, .21, .03, 1.38);
    // kasa: hexagonal roof with lifted corners (warabite)
    const kasa = new THREE.CylinderGeometry(.05, .44, .24, 6, 3); kasa.rotateY(Math.PI / 6);
    { const P = kasa.attributes.position; for (let k = 0; k < P.count; k++) { const x = P.getX(k), y = P.getY(k), z = P.getZ(k), rr = Math.hypot(x, z); const t = clamp((rr - .3) / .14); P.setY(k, y + t * t * .07 - (y < -.1 ? .0 : 0)); } kasa.computeVertexNormals(); }
    kasa.translate(lx, 1.41 + .12, lz); parts.push(kasa);
    for (let k = 0; k < 6; k++) { const a = k / 6 * Math.PI * 2 + Math.PI / 6; const g = new THREE.SphereGeometry(.035, 8, 6); g.translate(lx + Math.cos(a) * .45, 1.41 + .085, lz + Math.sin(a) * .45); parts.push(g); }
    const hoju = new THREE.SphereGeometry(.075, 16, 12); { const P = hoju.attributes.position; for (let k = 0; k < P.count; k++) { const y = P.getY(k); if (y > 0) P.setY(k, y * (1 + .9 * (y / .075) ** 3)); } hoju.computeVertexNormals(); }
    hoju.translate(lx, 1.65 + .08, lz); parts.push(hoju);
    hex(.07, .09, .05, 1.63, 12);
    for (const g of parts) B.add('lantern', paint(g, [1, 1, 1], (x, y, z, nx, ny) => aoGround(x, y, z) * (ny < -.3 ? .45 : 1) * (.7 + .3 * clamp(y / 1.7))));
    // glowing paper core (behind the posts)
    const core = new THREE.CylinderGeometry(.14, .14, .26, 6, 1); core.rotateY(Math.PI / 6); core.translate(lx, 1.08 + .15, lz);
    lanternGlowMat = new THREE.MeshStandardMaterial({ color: new THREE.Color(.5, .45, .38), emissive: new THREE.Color(1, .5, .2), emissiveIntensity: 0, roughness: .9 });
    const cm = new THREE.Mesh(core, lanternGlowMat); group.add(cm);
  }

  /* ---- cloud-pruned pine (niwaki, kuromatsu): a leaning, twisting trunk; every cloud pad sits on its own limb, which
     forks under the pad into a few twigs; pads are low domes of needle tufts over a dark core, ragged at the rim */
  let pinePos = null, pineFoliageMat = null, pineBarkMat = null;
  if (pine) {
    const [px, pz, yaw] = pine; pinePos = new THREE.Vector3(px, 0, pz);
    const nz = noise3(seed + 99), RP = rng(seed * 31 + 7);
    const trunkPts = [], radii = [], flex = [];
    for (let i = 0; i <= 14; i++) {
      const t = i / 14;
      trunkPts.push(new THREE.Vector3(px + Math.sin(t * 2.9) * .5 + t * .3 + (nz(t * 4, 1, 0, 2) - .5) * .12, t * 2.35, pz + Math.sin(t * 1.9 + 1) * .28 + (nz(t * 4, 5, 0, 2) - .5) * .12));
      radii.push(lerp(.15, .055, Math.pow(t, .8)) * (1 + (nz(t * 9, 2, 2, 1) - .5) * .25)); flex.push(0);
    }
    const bark = [tube(trunkPts, radii, flex, 11, .6, 1)];
    // flare into the ground
    for (let i = 0; i < 4; i++) { const a = i / 4 * 6.28 + RP(), b = trunkPts[0]; const pts = [0, 1, 2, 3].map(j => new THREE.Vector3(b.x + Math.cos(a) * j * .09, .16 - j * .06, b.z + Math.sin(a) * j * .09)); bark.push(tube(pts, [.1, .07, .05, .03], [0, 0, 0, 0], 6, .6, 1)); }
    const pads = [];
    const padSpec = [[.38, .95, 1.25, .5], [.62, 1.3, -1.15, .44], [.85, 1.72, .95, .4], [1, 2.42, 0, .52], [.72, 1.18, 2.45, .36]];
    for (const [t, y, a, rr] of padSpec) {
      const i0 = Math.round(t * 14), base = trunkPts[i0];
      const dir = new THREE.Vector3(Math.cos(a + yaw), 0, Math.sin(a + yaw));
      const L = t > .97 ? .02 : .55 + RP() * .45;
      const end = base.clone().addScaledVector(dir, L); end.y = y;
      if (L > .05) {   // the limb: out and slightly down, then up into the pad (a classic trained 'elbow')
        const m1 = base.clone().lerp(end, .35); m1.y = base.y - .06;
        const m2 = base.clone().lerp(end, .75); m2.y = end.y - .1;
        bark.push(tube([base, m1, m2, end], [radii[i0] * .7, .055, .045, .035], [0, 0, 0, 0], 7, .6, 1));
      }
      // twigs fanning out under the pad
      for (let k = 0; k < 5; k++) {
        const b = k / 5 * 6.28 + RP(), l = rr * (.55 + RP() * .35);
        const tip = end.clone().add(new THREE.Vector3(Math.cos(b) * l * 1.2, .06 + RP() * .06, Math.sin(b) * l));
        const mid = end.clone().lerp(tip, .5); mid.y -= .03;
        bark.push(tube([end, mid, tip], [.03, .02, .012], [0, 0, 0], 5, .6, 1));
      }
      // each cloud is three or four overlapping lobes, so its outline scallops instead of reading as a disc
      const pr = rr + RP() * .12, nl = 3 + (RP() < .5 ? 1 : 0), a0 = RP() * 6.28;
      for (let l = 0; l < nl; l++) {
        const b = a0 + l / nl * 6.28 + (RP() - .5) * .6, d = pr * (.34 + RP() * .16);
        pads.push({ c: end.clone().add(new THREE.Vector3(Math.cos(b) * d * 1.15, .07 + (RP() - .3) * .1, Math.sin(b) * d)), r: pr * (.58 + RP() * .14) });
      }
      pads.push({ c: end.clone().add(new THREE.Vector3(0, .12, 0)), r: pr * .55 });
    }
    pineBarkMat = await pbrMaterial('sakura_bark', { repeat: [1, 1], normal: 1.3 }); pineBarkMat.color.setRGB(.95, .82, .76);
    pineBarkMat.userData.rim = RIM_OFF(); pineBarkMat.onBeforeCompile = sh => rimGLSL(sh, pineBarkMat.userData.rim); pineBarkMat.customProgramCacheKey = () => 'pine-bark';
    const tm = new THREE.Mesh(mergeGeometries(bark.map(g => { g.deleteAttribute('aAnchor'); g.deleteAttribute('aFlex'); return g; })), pineBarkMat);
    tm.castShadow = tm.receiveShadow = true; tm.name = 'pine-bark'; group.add(tm);
    // needle tufts: dense on the dome and the rim (tufts stand up and poke out past the core), sparse underneath
    const nt = bledTexture(needleCanvas());
    const pos = [], nor = [], uv = [], idx = [], shd = [], coreG = []; let vi = 0;
    for (const pd of pads) {
      const n = Math.round(300 * (pd.r / .3) ** 2);
      const cg = new THREE.IcosahedronGeometry(1, 3); cg.deleteAttribute('uv'); cg.deleteAttribute('normal');
      const cm = mergeVertices(cg), CP = cm.attributes.position;
      for (let i = 0; i < CP.count; i++) { const x = CP.getX(i), y = CP.getY(i), z = CP.getZ(i), w = 1 + (nz(x * 2 + pd.c.x, y * 2, z * 2 + pd.c.z, 2) - .5) * .35;
        CP.setXYZ(i, x * pd.r * 1.0 * w, (y > 0 ? y * .6 : y * .32) * pd.r * w, z * pd.r * .88 * w); }
      cm.computeVertexNormals(); cm.translate(pd.c.x, pd.c.y, pd.c.z); coreG.push(cm);
      for (let i = 0; i < n; i++) {
        const u = RP() * Math.PI * 2, top = RP() < .82, v = top ? Math.acos(1 - RP() * 1.05) : Math.PI / 2 + RP() * .5;
        const dirn = new THREE.Vector3(Math.sin(v) * Math.cos(u), Math.cos(v), Math.sin(v) * Math.sin(u));
        const rr = pd.r * (.92 + .3 * nz(Math.cos(u) * 2 + pd.c.x, Math.sin(u) * 2, pd.c.z, 2));
        const c = pd.c.clone().add(new THREE.Vector3(dirn.x * rr * 1.05, dirn.y * rr * (dirn.y > 0 ? .62 : .34), dirn.z * rr * .9));
        const s = .17 + RP() * .1;
        // tufts stand roughly upright (needles fan up from the twig), leaning outward at the rim
        const upv = new THREE.Vector3(dirn.x * .55, 1, dirn.z * .55).normalize();
        const side = new THREE.Vector3(-dirn.z, 0, dirn.x).normalize().applyAxisAngle(upv, (RP() - .5) * 1.2);
        const q0 = (RP() * 4) | 0, u0 = (q0 % 2) * .5, v0 = (q0 >> 1) * .5;
        const nn = dirn.clone().multiplyScalar(.6).addScaledVector(new THREE.Vector3(0, 1, 0), .5).normalize();
        for (const [cx, cy] of [[-1, -1], [1, -1], [1, 1], [-1, 1]]) {
          const p = c.clone().addScaledVector(side, cx * s / 2).addScaledVector(upv, (cy + .6) * s / 2);
          pos.push(p.x, p.y, p.z); nor.push(nn.x, nn.y, nn.z); uv.push(u0 + (cx * .5 + .5) * .5, v0 + (cy * .5 + .5) * .5);
          shd.push(clamp(.35 + .65 * (dirn.y * .5 + .5), 0, 1));
        }
        idx.push(vi, vi + 1, vi + 2, vi, vi + 2, vi + 3); vi += 4;
      }
    }
    const fg = new THREE.BufferGeometry();
    fg.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3)); fg.setAttribute('normal', new THREE.Float32BufferAttribute(nor, 3)); fg.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2));
    fg.setAttribute('aShade', new THREE.Float32BufferAttribute(shd, 1)); fg.setIndex(idx);
    const fm = new THREE.MeshStandardMaterial({ map: nt, alphaTest: .5, side: THREE.DoubleSide, roughness: .9, color: new THREE.Color(.62, .68, .52) });
    fm.userData.rim = RIM_OFF();
    fm.onBeforeCompile = s2 => {
      s2.vertexShader = s2.vertexShader.replace('#include <common>', '#include <common>\nattribute float aShade; varying float vShade;').replace('#include <begin_vertex>', '#include <begin_vertex>\n vShade = aShade;');
      s2.fragmentShader = s2.fragmentShader.replace('#include <common>', '#include <common>\nvarying float vShade;')
        .replace('#include <alphatest_fragment>', `{ vec2 ts = vMapUv * 512.; float lod = .5 * log2(max(dot(dFdx(ts), dFdx(ts)), dot(dFdy(ts), dFdy(ts)))); diffuseColor.a = clamp(diffuseColor.a * (1. + max(lod - 1., 0.) * .25), 0., 1.); }\n#include <alphatest_fragment>`)
        .replace('#include <aomap_fragment>', '#include <aomap_fragment>\n reflectedLight.indirectDiffuse *= vShade; reflectedLight.indirectSpecular *= vShade * .12;');
      translucencyGLSL(s2, { tint: [1.1, 1, .45], k: .9 });
      rimGLSL(s2, fm.userData.rim, { tint: [1.3, 1.05, .5], grey: .1 });
    };
    fm.customProgramCacheKey = () => 'pine-needles-2';
    pineFoliageMat = fm;
    for (const g of coreG) B.add('pinecore', paint(g, [1, 1, 1], (x, y) => .6));
    const foliage = new THREE.Mesh(fg, fm); foliage.castShadow = foliage.receiveShadow = true; foliage.name = 'pine-needles';
    foliage.customDepthMaterial = new THREE.MeshDepthMaterial({ depthPacking: THREE.RGBADepthPacking, map: nt, alphaTest: .5, side: THREE.DoubleSide });
    group.add(foliage);
  }

  /* ---- clipped azalea mounds (o-karikomi) and a boundary hedge: leaf cards on lumpy ellipsoids, dense at the skin */
  if (shrubs.length || hedge) {
    const lt = bledTexture(leafCanvas());
    const pos = [], nor = [], uv = [], idx = [], shd = []; let vi = 0;
    const nz = noise3(seed + 321);
    const clump = (cx, cy, cz, rx, ry, rz, n, card) => {
      for (let i = 0; i < n; i++) {
        const u = R() * Math.PI * 2, v = Math.acos(1 - R() * 1.85);          // mostly the upper hemisphere
        const d = new THREE.Vector3(Math.sin(v) * Math.cos(u), Math.cos(v), Math.sin(v) * Math.sin(u));
        const lump = .82 + .3 * nz(d.x * 2 + cx, d.y * 2, d.z * 2 + cz, 2), depth = .86 + R() * .16;
        const c = new THREE.Vector3(cx + d.x * rx * lump * depth, Math.max(.02, cy + d.y * ry * lump * depth), cz + d.z * rz * lump * depth);
        const s = card * (.75 + R() * .5);
        const nn = d.clone().normalize();
        const t1 = new THREE.Vector3().crossVectors(nn, new THREE.Vector3(R() - .5, R() - .5, R() - .5)).normalize(), t2 = new THREE.Vector3().crossVectors(nn, t1);
        const q0 = (R() * 4) | 0, u0 = (q0 % 2) * .5, v0 = (q0 >> 1) * .5;
        for (const [a, b] of [[-1, -1], [1, -1], [1, 1], [-1, 1]]) {
          const p = c.clone().addScaledVector(t1, a * s / 2).addScaledVector(t2, b * s / 2);
          pos.push(p.x, p.y, p.z); nor.push(nn.x, nn.y, nn.z); uv.push(u0 + (a * .5 + .5) * .5, v0 + (b * .5 + .5) * .5);
          shd.push(clamp(.35 + .65 * (d.y * .5 + .5) * depth, 0, 1));
        }
        idx.push(vi, vi + 1, vi + 2, vi, vi + 2, vi + 3); vi += 4;
      }
    };
    const core = (x, y, z, rx, ry, rz) => { const g = rockGeometry(Math.round(x * 31 + z * 17), 1, [rx * .93, ry * .9, rz * .93], 2); g.translate(x, y, z); B.add('shrubcore', paint(g, [1, 1, 1], (px, py) => .5 + py * .4)); };
    for (const [x, z, rx, ry, rz, y0 = 0] of shrubs) { clump(x, y0 + ry * .55, z, rx, ry, rz, Math.round(700 * rx * rz + 60), .16); core(x, y0 + ry * .5, z, rx, ry, rz); }
    if (hedge) {   // [[x0,z0],[x1,z1], height, depth]
      const [[x0, z0], [x1, z1], hh, dd] = hedge, L = Math.hypot(x1 - x0, z1 - z0), n = Math.ceil(L / .9);
      for (let i = 0; i <= n; i++) { const t = i / n; clump(lerp(x0, x1, t), hh * .5, lerp(z0, z1, t), .75, hh * .55 * (.9 + R() * .2), dd * .5, 260, .2); core(lerp(x0, x1, t), hh * .45, lerp(z0, z1, t), .75, hh * .5, dd * .5); }
    }
    const sg = new THREE.BufferGeometry();
    sg.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3)); sg.setAttribute('normal', new THREE.Float32BufferAttribute(nor, 3));
    sg.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2)); sg.setAttribute('aShade', new THREE.Float32BufferAttribute(shd, 1)); sg.setIndex(idx);
    const sm = new THREE.MeshStandardMaterial({ map: lt, alphaTest: .5, side: THREE.DoubleSide, roughness: .9, color: new THREE.Color(.62, .7, .55) });
    sm.userData.rim = RIM_OFF();
    sm.onBeforeCompile = s2 => {
      s2.vertexShader = s2.vertexShader.replace('#include <common>', '#include <common>\nattribute float aShade; varying float vShade;').replace('#include <begin_vertex>', '#include <begin_vertex>\n vShade = aShade;');
      s2.fragmentShader = s2.fragmentShader.replace('#include <common>', '#include <common>\nvarying float vShade;')
        .replace('#include <alphatest_fragment>', `{ vec2 ts = vMapUv * 512.; float lod = .5 * log2(max(dot(dFdx(ts), dFdx(ts)), dot(dFdy(ts), dFdy(ts)))); diffuseColor.a = clamp(diffuseColor.a * (1. + max(lod - 1., 0.) * .25), 0., 1.); }\n#include <alphatest_fragment>`)
        .replace('#include <aomap_fragment>', '#include <aomap_fragment>\n reflectedLight.indirectDiffuse *= vShade; reflectedLight.indirectSpecular *= vShade * .12;');
      translucencyGLSL(s2, { tint: [.8, 1.05, .45], k: .22 });
      rimGLSL(s2, sm.userData.rim, { tint: [1.2, 1, .5], grey: 0 });
    };
    sm.customProgramCacheKey = () => 'garden-shrub-2';
    const shrubMesh = new THREE.Mesh(sg, sm); shrubMesh.castShadow = shrubMesh.receiveShadow = true; shrubMesh.name = 'shrubs';
    shrubMesh.customDepthMaterial = new THREE.MeshDepthMaterial({ depthPacking: THREE.RGBADepthPacking, map: lt, alphaTest: .5, side: THREE.DoubleSide });
    group.add(shrubMesh);
  }

  /* ---- merge */
  const rockM = stoneMaterial({ key: 'grock', moss: 1, lichen: .9, tint: [.15, .145, .135] });
  const slabM = stoneMaterial({ key: 'gslab', moss: .12, lichen: .4, tint: [.24, .23, .215] });
  const lantM = stoneMaterial({ key: 'glant', moss: .45, lichen: 1, tint: [.13, .128, .12], scale: 2 });
  const coreM = new THREE.MeshStandardMaterial({ color: new THREE.Color(.018, .03, .012), roughness: .9 }); tune(coreM, { key: 'shrubcore' });
  const pineCoreM = new THREE.MeshStandardMaterial({ color: new THREE.Color(.012, .02, .01), roughness: .9 }); tune(pineCoreM, { key: 'pinecore' });
  for (const [k, m] of [['moss', mossM], ['rock', rockM], ['slab', slabM], ['lantern', lantM], ['shrubcore', coreM], ['pinecore', pineCoreM]]) { const mesh = B.mesh(k, m, { cast: k !== 'moss' && k !== 'shrubcore' }); if (mesh) group.add(mesh); }

  const setGlow = v => { if (lanternGlowMat) lanternGlowMat.emissiveIntensity = clamp(v, 0, 2) * 3; };
  setGlow(glow);
  return { group, gravel, setGlow, update() {}, mossMaterial: mossM, stoneMaterial: rockM, features: { lantern: lanternPos, pine: pinePos },
    /** ground height at a garden-local point (turf, court, drop-offs) */
    heightAt: groundY, court: C,
    /** warm rim light on stones, lantern, moss, pine and shrubs where the key light is behind them (0 = off) */
    setRim(k = 1, p = 3) { setRim(group, k, p); } };
}
