/* Sunset — somei-yoshino cherry (agent A).
   export async function buildSakura({ seed = 1, height = 7, bloom = 1, spread = 1, avoid = null, groundPetals = true, lean = 0 })
     -> { group, update(t, wind), trunk (Mesh), blossoms (Mesh), bounds (Box3), crown: { centre: Vector3, radius }, setSun(dirWorld) }
   A seeded recursive skeleton (short gnarled trunk, 3-5 spreading limbs, horizontal secondary branches, upturned tips)
   swept into bark tubes (sakura_bark, UVs in metres), with blossom clumps as alpha-tested cards along the outer twigs:
   pale petals with deeper pink eyes, backlit translucency that respects the sun's shadow map, cut-out shadows through
   customDepthMaterial, and a gentle wind sway shared by twigs and the clumps riding on them.
   `avoid(p: Vector3) -> bool` lets a scene keep branches out of a building (growth bends away, then stops). */
import { THREE, pbrMaterial, canvasTexture, makeCanvas, loadTexture, rng, clamp, lerp } from '../core.js';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';
import { translucencyGLSL, rimGLSL, RIM_OFF, bledTexture } from './house.js';

/* ------------------------------------------------------------------ blossom atlas: 2 x 2 clumps
   Each cell is one clump of 30-45 somei-yoshino flowers seen from a few metres: pale, almost white petals with a faint
   pink blush toward the claw, deeper rose flowers buried in the core, no outlines and no dark marks (at hero distance
   any dark detail turns into speckle). Alpha is the flowers' own scalloped silhouette. */
function drawFlower(g, x, y, r, rot, tilt, R, col) {
  g.save(); g.translate(x, y); g.rotate(rot); g.scale(1, tilt);
  for (let k = 0; k < 5; k++) {
    g.save(); g.rotate(k * Math.PI * 2 / 5 + (R() - .5) * .3);
    const pr = r * (.9 + R() * .2);
    const p = new Path2D();
    p.moveTo(0, 0);
    p.bezierCurveTo(pr * .46, -pr * .08, pr * .66, -pr * .6, pr * .36, -pr * .98);
    p.quadraticCurveTo(pr * .14, -pr * .9, 0, -pr * .84);             // the shallow notch
    p.quadraticCurveTo(-pr * .14, -pr * .9, -pr * .36, -pr * .98);
    p.bezierCurveTo(-pr * .66, -pr * .6, -pr * .46, -pr * .08, 0, 0);
    const gr = g.createLinearGradient(0, 0, 0, -pr);
    gr.addColorStop(0, `rgb(${col[0][0]},${col[0][1]},${col[0][2]})`);
    gr.addColorStop(.45, `rgb(${col[1][0]},${col[1][1]},${col[1][2]})`);
    gr.addColorStop(1, `rgb(${col[2][0]},${col[2][1]},${col[2][2]})`);
    g.fillStyle = gr; g.fill(p);
    g.restore();
  }
  // a soft rose eye and pale stamens: low contrast, no dark pixels
  const eg = g.createRadialGradient(0, 0, 0, 0, 0, r * .3);
  eg.addColorStop(0, `rgba(${col[0][0] - 12},${col[0][1] - 40},${col[0][2] - 30},.8)`); eg.addColorStop(1, 'rgba(240,190,200,0)');
  g.fillStyle = eg; g.beginPath(); g.arc(0, 0, r * .3, 0, 7); g.fill();
  g.fillStyle = 'rgba(246,226,196,.7)';
  for (let k = 0; k < 7; k++) { const a = R() * 6.28, l = r * (.2 + R() * .14); g.beginPath(); g.arc(Math.cos(a) * l, Math.sin(a) * l, Math.max(.8, r * .035), 0, 7); g.fill(); }
  g.restore();
}
const mixc = (a, b, t) => a.map((v, i) => Math.round(v + (b[i] - v) * t));
function blossomAtlas(size = 1024) {
  const c = makeCanvas(size, size), g = c.getContext('2d'), R = rng(211), h = size / 2;
  // petal colours (sRGB): [claw, middle, edge]; core flowers are rosier, surface flowers nearly white
  const coreCol = [[222, 128, 152], [236, 170, 186], [244, 200, 210]];
  const skinCol = [[242, 190, 202], [250, 226, 231], [255, 246, 247]];
  for (let v = 0; v < 4; v++) {
    const ox = (v % 2) * h, oy = (v >> 1) * h, cx = ox + h / 2, cy = oy + h / 2;
    g.save(); g.beginPath(); g.rect(ox, oy, h, h); g.clip();
    // three to five sub-bunches (each a corymb of 3-5 flowers on one bud) make the clump lumpy, not a disc
    const subs = 3 + (R() * 3 | 0), fl = [];
    for (let s2 = 0; s2 < subs; s2++) {
      const sa = R() * 6.28, sd = (.06 + R() * .16) * h, sx = cx + Math.cos(sa) * sd, sy = cy + Math.sin(sa) * sd * .85, n = 8 + (R() * 6 | 0);
      for (let k = 0; k < n; k++) {
        const a = R() * 6.28, d = Math.sqrt(R()) * h * .15;
        const x = sx + Math.cos(a) * d, y = sy + Math.sin(a) * d, rr = Math.hypot(x - cx, y - cy) / (h * .42);
        fl.push({ x, y, r: h * (.052 + R() * .02), depth: clamp(rr * .8 + R() * .35) });
      }
    }
    fl.sort((a, b) => a.depth - b.depth);          // deep (rosier) flowers first, surface flowers on top
    for (const f of fl) {
      const t = clamp(f.depth * 1.25 - .1), col = [0, 1, 2].map(i => mixc(coreCol[i], skinCol[i], t));
      drawFlower(g, f.x, f.y, f.r, R() * 6.28, R() < .35 ? .5 + R() * .35 : .85 + R() * .15, R, col);
    }
    g.restore();
  }
  // bleed colour into the transparent texels so mip levels never pull in black at the clump edges
  const id = g.getImageData(0, 0, size, size), d = id.data;
  for (let pass = 0; pass < 4; pass++) {
    const src = new Uint8ClampedArray(d);
    for (let y = 1; y < size - 1; y++) for (let x = 1; x < size - 1; x++) {
      const i = (y * size + x) * 4; if (src[i + 3] > 8) continue;
      let r = 0, gg = 0, b = 0, n = 0;
      for (const o of [-4, 4, -size * 4, size * 4]) { const j = i + o; if (src[j + 3] > 8) { r += src[j]; gg += src[j + 1]; b += src[j + 2]; n++; } }
      if (n) { d[i] = r / n; d[i + 1] = gg / n; d[i + 2] = b / n; d[i + 3] = 1; }
    }
  }
  for (let i = 3; i < d.length; i += 4) if (d[i] === 1) d[i] = 0;
  g.putImageData(id, 0, 0);
  return c;
}

/* ------------------------------------------------------------------ tube sweep */
export function tube(pts, radii, flex, radial, texM, uRep) {
  const n = pts.length, pos = [], nor = [], uv = [], anc = [], fx = [], idx = [];
  const T = [], N = [], B = [];
  for (let i = 0; i < n; i++) T.push(pts[Math.min(n - 1, i + 1)].clone().sub(pts[Math.max(0, i - 1)]).normalize());
  let nrm = Math.abs(T[0].y) < .9 ? new THREE.Vector3(0, 1, 0) : new THREE.Vector3(1, 0, 0);
  nrm = nrm.sub(T[0].clone().multiplyScalar(nrm.dot(T[0]))).normalize();
  let v = 0;
  for (let i = 0; i < n; i++) {
    if (i > 0) { nrm = nrm.sub(T[i].clone().multiplyScalar(nrm.dot(T[i]))).normalize(); v += pts[i].distanceTo(pts[i - 1]); }
    const bin = new THREE.Vector3().crossVectors(T[i], nrm);
    for (let j = 0; j <= radial; j++) {
      const a = j / radial * Math.PI * 2, d = nrm.clone().multiplyScalar(Math.cos(a)).addScaledVector(bin, Math.sin(a));
      const p = pts[i].clone().addScaledVector(d, radii[i]);
      pos.push(p.x, p.y, p.z); nor.push(d.x, d.y, d.z);
      uv.push(j / radial * uRep, v / texM);
      anc.push(pts[i].x, pts[i].y, pts[i].z); fx.push(flex[i]);
    }
  }
  const W = radial + 1;
  for (let i = 0; i < n - 1; i++) for (let j = 0; j < radial; j++) { const a = i * W + j, b = a + 1, c = a + W, d = c + 1; idx.push(a, b, c, b, d, c); }
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  g.setAttribute('normal', new THREE.Float32BufferAttribute(nor, 3));
  g.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2));
  g.setAttribute('aAnchor', new THREE.Float32BufferAttribute(anc, 3));
  g.setAttribute('aFlex', new THREE.Float32BufferAttribute(fx, 1));
  g.setIndex(idx);
  return g;
}

/* shared wind displacement: rigid per anchor point, grows with flex^2 */
const WIND_GLSL = /* glsl */`
uniform float uTime, uWind;
vec3 windOffset(vec3 a, float flex){
  float f = flex * flex;
  float s1 = sin(uTime * 1.13 + a.x * .55 + a.z * .41), s2 = sin(uTime * 2.37 + a.y * 1.7 + a.x * .9), s3 = sin(uTime * 4.1 + dot(a, vec3(3.1, 2.3, 2.9)));
  return vec3(.07 * s1 + .025 * s2 + .012 * s3 * flex, .02 * s2 + .01 * s3, .045 * s2 + .02 * s1) * f * uWind;
}`;

export async function buildSakura({ seed = 1, height = 7, bloom = 1, spread = 1, avoid = null, groundPetals = true, lean = 0 } = {}) {
  const R = rng(seed * 104729 + 7);
  const group = new THREE.Group(); group.name = 'sakura';
  const k = height / 7;
  const up = new THREE.Vector3(0, 1, 0);
  const branches = [];   // { pts, radii, flex, depth }
  const clusters = [];   // { p, n (outward), s (size), flex }

  const rotAround = (v, axis, a) => v.clone().applyAxisAngle(axis, a);
  const perp = v => { const a = Math.abs(v.y) < .95 ? up : new THREE.Vector3(1, 0, 0); return new THREE.Vector3().crossVectors(v, a).normalize(); };
  const blocked = p => avoid ? avoid(p) : false;

  function grow(p0, dir, len, r0, depth, flex0, maxDepth) {
    const segs = Math.max(3, Math.round(len / (.22 * k) + 2));
    const pts = [p0.clone()], radii = [r0], flex = [flex0];
    let p = p0.clone(), d = dir.clone();
    const rEnd = r0 * (depth === 0 ? .62 : .42);
    let stopped = false;
    for (let i = 1; i <= segs; i++) {
      const t = i / segs;
      // gnarl, gravitropism: limbs spread and level out, tips turn up a little
      const noise = new THREE.Vector3(R() - .5, (R() - .5) * .5, R() - .5).multiplyScalar(depth === 0 ? .16 : depth === 1 ? .26 : .38);
      const hz = new THREE.Vector3(d.x, 0, d.z); if (hz.lengthSq() > 1e-4) hz.normalize();
      if (depth === 0) d.addScaledVector(up, .1);
      else if (depth === 1) d.addScaledVector(up, .015).addScaledVector(hz, .02);
      else if (depth === 2) d.addScaledVector(hz, .03).addScaledVector(up, .01);
      else d.addScaledVector(up, (t - .35) * .12).addScaledVector(hz, .03);
      d.add(noise).normalize();
      if (depth >= 2 && d.y < -.35) { d.y = -.35; d.normalize(); }
      let np = p.clone().addScaledVector(d, len / segs);
      if (blocked(np)) {   // bend away from the building: try a few alternatives, else stop here
        let ok = false;
        for (let tr = 0; tr < 6 && !ok; tr++) {
          const alt = d.clone().add(new THREE.Vector3(R() - .5, R() * .6, R() - .5).multiplyScalar(1.6)).normalize();
          const q = p.clone().addScaledVector(alt, len / segs);
          if (!blocked(q)) { d = alt; np = q; ok = true; }
        }
        if (!ok) { stopped = true; break; }
      }
      p = np; pts.push(p.clone()); radii.push(lerp(r0, rEnd, Math.pow(t, .8))); flex.push(lerp(flex0, flex0 + (1 - flex0) * (depth >= 2 ? .5 : .25), t));
    }
    if (pts.length < 3) return;
    branches.push({ pts, radii, flex, depth });
    // children
    if (depth < maxDepth && !stopped) {
      const nChild = depth === 0 ? 4 + (R() < .5 ? 1 : 0) : depth === 1 ? 3 + (R() * 2 | 0) : depth === 2 ? 3 : 2 + (R() < .5 ? 1 : 0);
      for (let c = 0; c < nChild; c++) {
        const at = depth === 0 ? pts.length - 1 : Math.max(1, Math.min(pts.length - 1, Math.round((.35 + .65 * (c + R() * .8) / nChild) * (pts.length - 1))));
        const base = pts[at], pr = radii[at];
        const tdir = pts[Math.min(pts.length - 1, at + 1)].clone().sub(pts[Math.max(0, at - 1)]).normalize();
        let cd;
        if (depth === 0) {  // main limbs fan out around the trunk top
          const az = (c / nChild) * Math.PI * 2 + R() * .6, el = (30 + R() * 18) * Math.PI / 180;
          cd = new THREE.Vector3(Math.cos(az) * Math.sin(el), Math.cos(el), Math.sin(az) * Math.sin(el));
        } else {
          const ax = rotAround(perp(tdir), tdir, R() * Math.PI * 2);
          cd = rotAround(tdir, ax, (22 + R() * 26) * Math.PI / 180);
          // keep the crown lifting and spreading: pull toward outward-and-up from the trunk axis
          const out = new THREE.Vector3(base.x, 0, base.z); if (out.lengthSq() > 1e-4) out.normalize();
          cd.addScaledVector(out, depth <= 2 ? .35 : .2).addScaledVector(up, depth <= 1 ? .25 : depth === 2 ? .12 : .05).normalize();
        }
        const clen = (depth === 0 ? 2.7 + R() * 1.1 : len * (.66 + R() * .16)) * (depth === 0 ? k * spread : 1);
        const cr = depth === 0 ? pr * (.62 + R() * .1) : pr * (.62 + R() * .08);
        grow(base.clone().addScaledVector(tdir, -pr * .3), cd, clen, cr, depth + 1, flex[at], maxDepth);
      }
      // a terminal leader continues most limbs
    }
    // blossom clumps along the outer branches
    if (depth >= 3) {
      const every = depth >= 4 ? 1 : 2;
      for (let i = Math.max(1, pts.length - (depth >= 4 ? pts.length : 4)); i < pts.length; i += every) {
        // (these R() draws are kept only so every scene's skeleton stays identical; clumps are placed after growth)
        if (R() > bloom * (depth >= 4 ? .95 : .7)) continue;
        const nC = depth >= 4 ? 2 + (R() * 2 | 0) : 1;
        for (let q = 0; q < nC; q++) { R(); R(); R(); R(); }
      }
    }
  }

  const trunkLen = 1.9 * k, trunkDir = new THREE.Vector3(lean, 1, lean * .3).normalize();
  grow(new THREE.Vector3(0, -.15, 0), trunkDir, trunkLen, .3 * k, 0, 0, 5);

  /* clumps grow from the limbs: every ~0.3 m along the outer part of each branch a short spur carries one clump,
     set off the bark toward the light side, so each clump visibly hangs on wood and sky shows between the spurs */
  {
    const RC = rng(seed * 3571 + 17);
    let cx = 0, cz = 0, n = 0; for (const b of branches) if (b.depth >= 3) { const q = b.pts[b.pts.length - 1]; cx += q.x; cz += q.z; n++; }
    const axis = new THREE.Vector3(cx / Math.max(1, n), 0, cz / Math.max(1, n));
    for (const b of branches) {
      if (b.depth < 2) continue;
      const from = b.depth === 2 ? .4 : b.depth === 3 ? .2 : 0, L = b.pts.length;
      let acc = RC() * .3 * k;
      for (let i = 1; i < L; i++) {
        acc += b.pts[i].distanceTo(b.pts[i - 1]);
        if (i / (L - 1) < from || acc < .21 * k) continue;
        acc = 0;
        if (RC() > bloom * (b.depth >= 4 ? .92 : .8)) continue;
        const t = b.pts[Math.min(L - 1, i + 1)].clone().sub(b.pts[i - 1]).normalize();
        const out = b.pts[i].clone().sub(axis); out.y = 0; out.normalize();
        const side = new THREE.Vector3(RC() - .5, .55 + RC() * .5, RC() - .5).addScaledVector(out, .6);
        side.addScaledVector(t, -side.dot(t)).normalize();
        const sz = (.36 + RC() * .2) * k * (b.depth >= 4 ? .9 : 1);
        const p = b.pts[i].clone().addScaledVector(side, b.radii[i] + sz * .38);
        clusters.push({ p, s: sz, flex: b.flex[i], a: b.pts[i].clone(), side });
        if (b.depth >= 3 && RC() < .7) {         // a second clump on the other side of the limb
          const s2 = side.clone().multiplyScalar(-1).addScaledVector(new THREE.Vector3(0, 1, 0), .8).normalize();
          clusters.push({ p: b.pts[i].clone().addScaledVector(s2, b.radii[i] + sz * .3), s: sz * .8, flex: b.flex[i], a: b.pts[i].clone(), side: s2 });
        }
      }
      // every branch tip ends in a clump
      if (b.depth >= 3 && RC() < bloom) { const q = b.pts[L - 1], t = q.clone().sub(b.pts[L - 2]).normalize(); clusters.push({ p: q.clone().addScaledVector(t, .1 * k), s: (.28 + RC() * .12) * k, flex: b.flex[L - 1], a: q.clone(), side: t }); }
    }
  }

  /* ---- bark mesh */
  const bark = await pbrMaterial('sakura_bark', { repeat: [1, 1], normal: 1.4, roughness: .92 });
  bark.color.setRGB(1.1, 1.0, 1.0);
  const barkU = { uTime: { value: 0 }, uWind: { value: 1 } };
  const windVS = sh => {
    Object.assign(sh.uniforms, barkU);
    sh.vertexShader = sh.vertexShader.replace('#include <common>', `#include <common>\nattribute vec3 aAnchor; attribute float aFlex;\n${WIND_GLSL}`)
      .replace('#include <begin_vertex>', '#include <begin_vertex>\n transformed += windOffset(aAnchor, aFlex);');
  };
  const barkRim = RIM_OFF(), pxU = { value: 0 };
  bark.onBeforeCompile = sh => {
    windVS(sh);
    // thin twigs never go below ~0.7 px wide (sub-pixel tubes alias into dashed ink strokes)
    sh.uniforms.uPx = pxU;
    sh.vertexShader = sh.vertexShader.replace('#include <common>', '#include <common>\nuniform float uPx;')
      .replace('transformed += windOffset(aAnchor, aFlex);', `{ vec3 rel = position - aAnchor; float rr = max(length(rel), 1e-4);
          float need = uPx * max(-(modelViewMatrix * vec4(aAnchor, 1.)).z, 0.) * .7;
          transformed = aAnchor + rel * max(1., need / rr); }
        transformed += windOffset(aAnchor, aFlex);`);
    rimGLSL(sh, barkRim);
    // darker in the crotches and on the undersides; a touch of lichen grey on the upper trunk
    sh.vertexShader = sh.vertexShader.replace('#include <common>', '#include <common>\nvarying float vUnder; varying float vH;')
      .replace('#include <begin_vertex>', '#include <begin_vertex>\n vUnder = normal.y; vH = aFlex;');
    sh.fragmentShader = sh.fragmentShader.replace('#include <common>', '#include <common>\nvarying float vUnder; varying float vH;')
      .replace('#include <aomap_fragment>', '#include <aomap_fragment>\n reflectedLight.indirectDiffuse *= mix(.55, 1., smoothstep(-.8, .6, vUnder)) * mix(.6, 1., smoothstep(0., .3, vH)); reflectedLight.indirectSpecular *= .28;');
  };
  bark.customProgramCacheKey = () => 'sakura-bark';
  const tubes = [];
  for (const b of branches) {
    const radial = b.depth === 0 ? 14 : b.depth === 1 ? 10 : b.depth === 2 ? 7 : b.depth === 3 ? 5 : 4;
    const r0 = b.radii[0], uRep = Math.max(1, Math.round(2 * Math.PI * r0 / .7));
    tubes.push(tube(b.pts, b.radii, b.flex, radial, .7, uRep));
  }
  // root flare: a few buttress roots sinking into the ground
  for (let i = 0; i < 5; i++) {
    const a = i / 5 * Math.PI * 2 + R() * .5, rr = .3 * k;
    const pts = [], radii = [], flex = [];
    for (let j = 0; j <= 5; j++) { const t = j / 5; pts.push(new THREE.Vector3(Math.cos(a) * (rr * .3 + t * rr * 2.2), .45 * k * (1 - t) ** 1.6 - .06, Math.sin(a) * (rr * .3 + t * rr * 2.2))); radii.push(lerp(rr * .55, rr * .12, t)); flex.push(0); }
    tubes.push(tube(pts, radii, flex, 8, .7, 2));
  }
  const barkG = mergeGeometries(tubes);
  const trunk = new THREE.Mesh(barkG, bark); trunk.castShadow = true; trunk.receiveShadow = true; trunk.name = 'sakura-bark';
  const _vp = new THREE.Vector4();
  trunk.onBeforeRender = (r, sc, cam) => { r.getCurrentViewport(_vp); pxU.value = 2 / (cam.projectionMatrix.elements[5] * Math.max(1, _vp.w)); };
  const barkDepth = new THREE.MeshDepthMaterial({ depthPacking: THREE.RGBADepthPacking });
  barkDepth.onBeforeCompile = windVS;
  trunk.customDepthMaterial = barkDepth;
  group.add(trunk);

  /* ---- blossom cards: photographic somei-yoshino clusters (assets/img/blossom-atlas, 3 x 3 cells, each with the uv of
     its twig stub). Every clump is 14-26 small cards on a lumpy shell around its spur, each card turned so its stub
     points back at the limb it grows from, random cell and mirror, so the canopy is many clusters with sky between. */
  let atlas = null, cells = null;
  try {
    const [tex, meta] = await Promise.all([loadTexture('assets/img/blossom-atlas.webp', { srgb: true }), fetch('assets/img/blossom-atlas.json').then(r => r.json())]);
    if (tex?.image && meta?.cells?.length) { atlas = bledTexture(tex.image, { despill: true }); cells = meta.cells; }
  } catch (e) { /* fall back to the drawn atlas */ }
  if (!atlas) {
    atlas = canvasTexture(blossomAtlas(1024)); atlas.generateMipmaps = true; atlas.minFilter = THREE.LinearMipmapLinearFilter;
    cells = [0, 1, 2, 3].map(v => ({ u0: (v % 2) * .5, v0: (v >> 1) * .5, u1: (v % 2) * .5 + .5, v1: (v >> 1) * .5 + .5, stem: [(v % 2) * .5 + .25, (v >> 1) * .5 + .05] }));
  }
  const crownC = new THREE.Vector3(); for (const c of clusters) crownC.add(c.p); crownC.divideScalar(Math.max(1, clusters.length));
  let crownR = 0; for (const c of clusters) crownR = Math.max(crownR, c.p.distanceTo(crownC));
  const pos = [], nor = [], uv = [], anc = [], fx = [], sh = [], idx = [];
  let vi = 0;
  const _W1 = new THREE.Vector3(), _W2 = new THREE.Vector3(), _X = new THREE.Vector3(), _Y = new THREE.Vector3();
  const addCard = (ctr, sz, nrm, toward, cell, flip, lightN) => {
    // in-plane basis so that the cell's stub direction (theta) maps onto `toward` projected into the card plane
    const sx = cell.stem[0] - (cell.u0 + cell.u1) / 2, sy = cell.stem[1] - (cell.v0 + cell.v1) / 2;
    const th = Math.atan2(sy, flip ? -sx : sx), ct = Math.cos(th), st = Math.sin(th);
    _W1.copy(toward).addScaledVector(nrm, -toward.dot(nrm)); if (_W1.lengthSq() < 1e-6) _W1.copy(perp(nrm)); _W1.normalize();
    _W2.crossVectors(nrm, _W1);
    _X.copy(_W1).multiplyScalar(ct).addScaledVector(_W2, -st); _Y.copy(_W2).multiplyScalar(ct).addScaledVector(_W1, st);
    for (const [cx, cy] of [[-1, -1], [1, -1], [1, 1], [-1, 1]]) {
      pos.push(ctr.x + (_X.x * cx + _Y.x * cy) * sz / 2, ctr.y + (_X.y * cx + _Y.y * cy) * sz / 2, ctr.z + (_X.z * cx + _Y.z * cy) * sz / 2);
      nor.push(lightN.x, lightN.y, lightN.z);
      const u = flip ? -cx : cx;
      uv.push(cell.u0 + (u * .5 + .5) * (cell.u1 - cell.u0), cell.v0 + (cy * .5 + .5) * (cell.v1 - cell.v0));
    }
    idx.push(vi, vi + 1, vi + 2, vi, vi + 2, vi + 3); vi += 4;
  };
  const RB = rng(seed * 911 + 5);
  let ymin = 1e9, ymax = -1e9; for (const c of clusters) { ymin = Math.min(ymin, c.p.y); ymax = Math.max(ymax, c.p.y); }
  const cardOf = [], skin = []; let ci = -1;
  const nz3 = (x, y, z) => .5 + .5 * Math.sin(x * 7.3 + Math.sin(y * 5.1) * 2) * Math.sin(z * 6.7 + Math.sin(x * 4.3) * 2);
  for (const c of clusters) {
    ci++;
    const nCards = Math.round((14 + RB() * 12) * (c.s / (.46 * k)) ** 2);
    const radial = c.p.clone().sub(crownC);
    const outer = clamp(radial.length() / crownR);
    const hgt = clamp((c.p.y - ymin) / Math.max(.1, ymax - ymin));
    const shade = (.5 + .3 * outer + .2 * hgt) * (.85 + .3 * RB());          // inner clumps and the crown's underside darker
    const rad = c.s * .5;
    for (let q = 0; q < nCards; q++) {
      // a point on a lumpy, slightly flattened shell (most cards near the skin, a few inside), biased to the light side
      const d = new THREE.Vector3(RB() * 2 - 1, RB() * 2 - 1, RB() * 2 - 1); if (d.lengthSq() < 1e-4) d.set(0, 1, 0); d.normalize();
      d.addScaledVector(c.side, .45).normalize();
      const f = Math.pow(RB(), .45);                                         // 0 core .. 1 skin
      const lump = .8 + .4 * nz3(d.x + c.p.x, d.y + c.p.y, d.z + c.p.z);
      const p = c.p.clone().add(new THREE.Vector3(d.x, d.y * .8, d.z).multiplyScalar(rad * f * lump));
      const nrm = d.clone().multiplyScalar(.75).add(new THREE.Vector3(RB() - .5, RB() - .5, RB() - .5).multiplyScalar(.9)).normalize();
      const toward = c.a.clone().sub(p);
      const cell = cells[(RB() * cells.length) | 0], flip = RB() < .5;
      const lightN = d.clone().multiplyScalar(.6).addScaledVector(radial.clone().normalize(), .4).normalize();
      addCard(p, (.16 + RB() * .08) * (.85 + .3 * f), nrm, toward, cell, flip, lightN); cardOf.push(ci);
      const sk = clamp(.2 + .8 * f * (.55 + .45 * Math.max(0, d.dot(c.side))));
      const under = clamp(.5 + (p.y - c.p.y) / (rad * 1.6)) * .3 + .7;
      for (let m = 0; m < 4; m++) { anc.push(c.a.x, c.a.y, c.a.z); fx.push(c.flex); sh.push(clamp(shade * under, .2, 1.1)); skin.push(sk); }
    }
  }
  const bg = new THREE.BufferGeometry();
  bg.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  bg.setAttribute('normal', new THREE.Float32BufferAttribute(nor, 3));
  bg.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2));
  bg.setAttribute('aAnchor', new THREE.Float32BufferAttribute(anc, 3));
  bg.setAttribute('aFlex', new THREE.Float32BufferAttribute(fx, 1));
  bg.setAttribute('aShade', new THREE.Float32BufferAttribute(sh, 1));
  bg.setAttribute('aSkin', new THREE.Float32BufferAttribute(skin, 1));
  const transA = new THREE.Float32BufferAttribute(skin.map(v => .35 + .65 * v), 1); bg.setAttribute('aTrans', transA);
  bg.setIndex(idx);
  const blossomU = { uTrans: { value: new THREE.Color(1.15, 1.02, 1.25) }, uTransK: { value: 1.5 } };
  const bm = new THREE.MeshStandardMaterial({ map: atlas, alphaTest: .42, side: THREE.DoubleSide, roughness: .85, metalness: 0, color: new THREE.Color(1, 1, 1) });
  bm.onBeforeCompile = s => {
    windVS(s); Object.assign(s.uniforms, blossomU);
    s.vertexShader = s.vertexShader.replace('#include <common>', '#include <common>\nattribute float aShade; attribute float aTrans; attribute float aSkin; varying float vShade; varying float vTrans; varying float vSkin;')
      .replace('#include <begin_vertex>', '#include <begin_vertex>\n vShade = aShade; vTrans = aTrans; vSkin = aSkin;');
    s.fragmentShader = s.fragmentShader.replace('#include <common>', '#include <common>\nvarying float vShade; varying float vTrans; varying float vSkin;')
      // keep clumps full at a distance: alpha grows gently with the mip level (a soft mask, so no speckle)
      .replace('#include <alphatest_fragment>', `
        { vec2 ts = vMapUv * 1536.; float lod = .5 * log2(max(dot(dFdx(ts), dFdx(ts)), dot(dFdy(ts), dFdy(ts))));
          diffuseColor.a = clamp(diffuseColor.a * (1. + max(lod - 1., 0.) * .22), 0., 1.); }
        #include <alphatest_fragment>`)
      // clump cores deep rose, the skin near white
      .replace('#include <map_fragment>', '#include <map_fragment>\n diffuseColor.rgb *= mix(vec3(.86, .66, .74), vec3(1.), smoothstep(.15, .85, vSkin)) * mix(.9, 1., smoothstep(.3, 1., vShade));')
      .replace('#include <aomap_fragment>', '#include <aomap_fragment>\n reflectedLight.indirectDiffuse *= vShade * vec3(1.08, .9, .92); reflectedLight.indirectSpecular *= vShade * .15;')
      // translucency: sun through the petals, from the shadowed direct light of the (single) directional light
;
    translucencyGLSL(s, { tint: [blossomU.uTrans.value.r, blossomU.uTrans.value.g, blossomU.uTrans.value.b], k: blossomU.uTransK.value, floor: 1, warmCool: true, shade: true });
  };
  bm.customProgramCacheKey = () => 'sakura-blossom' + blossomU.uTrans.value.getHexString() + blossomU.uTransK.value;
  const blossoms = new THREE.Mesh(bg, bm); blossoms.castShadow = true; blossoms.receiveShadow = true; blossoms.name = 'sakura-blossom';
  const bdm = new THREE.MeshDepthMaterial({ depthPacking: THREE.RGBADepthPacking, map: atlas, alphaTest: .42, side: THREE.DoubleSide });
  bdm.onBeforeCompile = windVS;
  blossoms.customDepthMaterial = bdm;
  group.add(blossoms);

  /* ---- fallen petals on the ground under the crown */
  if (groundPetals) {
    const pc = makeCanvas(64, 64), pg = pc.getContext('2d');
    pg.translate(32, 32); pg.fillStyle = '#f7d9df';
    const p = new Path2D(); p.moveTo(0, 28); p.bezierCurveTo(16, 18, 22, -6, 14, -22); p.quadraticCurveTo(6, -28, 0, -20); p.quadraticCurveTo(-6, -28, -14, -22); p.bezierCurveTo(-22, -6, -16, 18, 0, 28);
    pg.fill(p); pg.fillStyle = 'rgba(214,120,146,.5)'; pg.beginPath(); pg.ellipse(0, 20, 5, 8, 0, 0, 7); pg.fill();
    const ptex = canvasTexture(pc);
    const n = 900, pgeo = new THREE.PlaneGeometry(.028, .034).rotateX(-Math.PI / 2);
    const pm = new THREE.MeshStandardMaterial({ map: ptex, alphaTest: .5, roughness: .8, side: THREE.DoubleSide });
    const im = new THREE.InstancedMesh(pgeo, pm, n); const m4 = new THREE.Matrix4(), q = new THREE.Quaternion(), e = new THREE.Euler(), col = new THREE.Color();
    for (let i = 0; i < n; i++) {
      const a = R() * 6.28, d = Math.sqrt(R()) * crownR * 1.15;
      const x = crownC.x + Math.cos(a) * d, z = crownC.z + Math.sin(a) * d;
      e.set((R() - .5) * .5, R() * 6.28, (R() - .5) * .5); q.setFromEuler(e);
      const s = .8 + R() * .5;
      m4.compose(new THREE.Vector3(x, .012 + R() * .01, z), q, new THREE.Vector3(s, s, s)); im.setMatrixAt(i, m4);
      const v = .8 + R() * .25; im.setColorAt(i, col.setRGB(v, v * .96, v * .97));
    }
    im.receiveShadow = true; im.name = 'sakura-fallen'; group.add(im);
  }

  const bounds = new THREE.Box3().setFromObject(group);
  return {
    group, trunk, blossoms, bounds, crown: { centre: crownC, radius: crownR }, clusters: clusters.length,
    update(t, wind = 1) { barkU.uTime.value = t; barkU.uWind.value = wind; },
    /** Light transmitted through the crown toward `dirWorld` (unit vector to the light): clumps with many clumps between
        them and the light glow less, the thin rim glows most. Call once per light direction (cheap: a voxel march). */
    setSun(dirWorld) {
      group.updateMatrixWorld(true);
      const d = dirWorld.clone().transformDirection(new THREE.Matrix4().copy(group.matrixWorld).invert()).normalize();
      const V = .55, key = (x, y, z) => `${Math.floor(x / V)},${Math.floor(y / V)},${Math.floor(z / V)}`, grid = new Map();
      for (const c of clusters) { const k2 = key(c.p.x, c.p.y, c.p.z); grid.set(k2, (grid.get(k2) || 0) + c.s * c.s); }
      const T = new Float32Array(clusters.length);
      clusters.forEach((c, i) => {
        let tau = 0;
        for (let st = 1; st <= 22; st++) { const q = c.p.clone().addScaledVector(d, st * .45); tau += grid.get(key(q.x, q.y, q.z)) || 0; }
        T[i] = Math.exp(-tau * .8);
      });
      for (let v = 0; v < cardOf.length; v++) { const t2 = (.15 + 1.3 * T[cardOf[v]]) * (.3 + .7 * skin[v * 4]); for (let m = 0; m < 4; m++) transA.setX(v * 4 + m, t2); }
      transA.needsUpdate = true;
    },
    /** set before first render (compiled into the shader) */
    setTranslucency(color, k2 = 1.5) { if (color) blossomU.uTrans.value.copy(color); blossomU.uTransK.value = k2; bm.needsUpdate = true; },
    setSunColor() {},
    /** warm rim on the bark where the sun is behind it (0 = off) */
    setRim(k = 1, p = 2.5) { barkRim.value.set(k, p); },
  };
}
