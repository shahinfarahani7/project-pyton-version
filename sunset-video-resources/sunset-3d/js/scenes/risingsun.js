/* Plan card 3 — "Sunset Plan": a small two-leaf byōbu standing on the paper sweep, under the same lens and key as the
   coins and the soroban. Black urushi leaves in a black lacquer frame with gilt corner fittings; across both leaves,
   seigaiha in raised maki-e gold lines (rows growing larger toward the foot), and a gold-leaf sun half set behind the
   top row — flattened a touch at its base, reddening in its lower half. The sun sinks and rises very slowly.
   Units: cm. */
import { THREE, rng, clamp, lerp, damp, REDUCED } from '../core.js';
import { RoundedBoxGeometry } from 'three/addons/geometries/RoundedBoxGeometry.js';
import { CARD_FOV, CARD_POST, metalEnv, paperSweep, contactBlob, cardCamera } from './coins.js';

const TAU = Math.PI * 2;
const LW = 8.6, LH = 12.4, LT = .55, FRAME = .42, OPEN = .5;   // leaf size, thickness, frame width, fold angle per leaf (rad)
const IW = LW - FRAME * 2, IH = LH - FRAME * 2;                  // inner panel of one leaf
const ROWS = 15;

/* the seigaiha rows across the unfolded pair (x 0 .. 2·IW, y 0 .. IH from the panel foot): radius grows toward the foot,
   spacing follows the radius, every row shifted by half a period plus a little drift */
function rowTable(seed = 3) {
  const R = rng(seed), cy = [], r = [], off = [];
  let y = IH * .5;
  for (let j = 0; j < ROWS; j++) {
    const t = Math.min(1, j / 11), rj = lerp(.62, 1.45, Math.pow(t, 1.25)) * (.94 + R() * .12);
    if (j) y -= rj * .5 * (.92 + R() * .16);
    cy.push(y); r.push(rj); off.push((j % 2) * rj + (R() - .5) * .3);
  }
  return { cy, r, off };
}

export async function create(ctx) {
  const { renderer, env: pageEnv } = ctx;
  const scene = new THREE.Scene();
  const env = pageEnv.studio || metalEnv(renderer), menv = metalEnv(renderer);
  scene.environment = env; scene.environmentIntensity = .45;
  const camera = new THREE.PerspectiveCamera(CARD_FOV, 1.45, 4, 400);
  const stage = paperSweep(scene, { box: [22, 14], center: [0, -1], keyI: 3.1, back: -14, radius: 14 });

  const rows = rowTable();
  const U = {
    uCy: { value: rows.cy }, uR: { value: rows.r }, uOff: { value: rows.off },
    uSun: { value: new THREE.Vector3(IW * 1.2, IH * .52, 2.35) }, uLeafX: { value: 0 },
  };

  /* black urushi with the maki-e: one material per leaf (uLeafX = where the leaf starts in the unfolded design) */
  const faceMat = leafX => {
    const m = new THREE.MeshPhysicalMaterial({ color: new THREE.Color('#0e0b0a').convertSRGBToLinear(), roughness: .32, metalness: 0, clearcoat: 1, clearcoatRoughness: .16, envMap: menv, envMapIntensity: .9 });
    const LU = { ...U, uLeafX: { value: leafX } };
    m.onBeforeCompile = sh => {
      Object.assign(sh.uniforms, LU);
      sh.vertexShader = sh.vertexShader.replace('#include <common>', '#include <common>\nvarying vec2 vDP; varying vec3 vTx; varying vec3 vTy; varying vec3 vTz;')
        .replace('#include <begin_vertex>', `#include <begin_vertex>
          vDP = vec2(position.x + ${(IW / 2).toFixed(3)} + uLeafX, position.y + ${(IH / 2).toFixed(3)});
          vTx = normalize(normalMatrix * vec3(1., 0., 0.)); vTy = normalize(normalMatrix * vec3(0., 1., 0.)); vTz = normalize(normalMatrix * vec3(0., 0., 1.));`)
        .replace('#include <common>', '#include <common>\nuniform float uLeafX;');
      sh.fragmentShader = sh.fragmentShader.replace('#include <common>', `#include <common>
        uniform float uCy[${ROWS}], uR[${ROWS}], uOff[${ROWS}]; uniform vec3 uSun; uniform float uLeafX;
        varying vec2 vDP; varying vec3 vTx; varying vec3 vTy; varying vec3 vTz;
        float h12(vec2 p){ vec3 p3 = fract(vec3(p.xyx) * .1031); p3 += dot(p3, p3.yzx + 33.33); return fract((p3.x + p3.y) * p3.z); }
        float vn(vec2 p){ vec2 i = floor(p), f = fract(p); f = f * f * (3. - 2. * f); return mix(mix(h12(i), h12(i + vec2(1,0)), f.x), mix(h12(i + vec2(0,1)), h12(i + vec2(1,1)), f.x), f.y); }`)
        .replace('#include <color_fragment>', `#include <color_fragment>
          vec2 p = vDP;
          float fwp = length(fwidth(p)) * .8 + 1e-5;
          // --- seigaiha: the lowest row containing p wins (each row lies over the one above)
          float inWave = 0., d = 2., rr = 1.; vec2 cen = vec2(0.);
          for (int j = 0; j < ${ROWS}; j++) {
            float rj = uR[j], cy = uCy[j], cx = uOff[j] + floor((p.x - uOff[j]) / (2. * rj) + .5) * 2. * rj;
            float dd = length(p - vec2(cx, cy)) / rj;
            if (dd < 1. && p.y > cy - rj * 1.2) { d = dd; rr = rj; cen = vec2(cx, cy); inWave = 1.; }
          }
          // below the last row the design is all scales
          if (p.y < uCy[${ROWS - 1}]) { float rj = uR[${ROWS - 1}]; float cy = uCy[${ROWS - 1}] - rj * .5; float cx = uOff[${ROWS - 1}] + rj + floor((p.x - uOff[${ROWS - 1}] - rj) / (2. * rj) + .5) * 2. * rj; d = min(length(p - vec2(cx, cy)) / rj, 1.); rr = rj; cen = vec2(cx, cy); inWave = 1.; }
          float rw = (1. - d) * rr;                                         // distance to the scale's own outline
          float ringQ = d * 4., ringD = abs(fract(ringQ + .5) - .5) * rr / 4.;
          float lw = max(.05 * rr, fwp * .9);
          float lineR = (1. - smoothstep(lw * .5 - fwp * .5, lw * .5 + fwp * .5, ringD)) * step(.2, d);
          float lineE = 1. - smoothstep(lw * .6 - fwp * .5, lw * .6 + fwp * .5, rw);
          float gold = max(lineR, lineE) * inWave;
          // raised lines: a rounded ridge across each line (radial), so each line has a lit side and a shaded side
          vec2 rad = (p - cen) / max(length(p - cen), 1e-4);
          float sR = clamp((fract(ringQ + .5) - .5) * rr / 4. / (lw * .5), -1., 1.);
          float sE = clamp(-rw / (lw * .6), -1., 0.) + clamp(rw / (lw * .6), 0., 1.) * 0.;
          float slope = (lineR > lineE ? sR : sE) * gold * .45;
          vec3 nLoc = normalize(vec3(rad * slope, 1.));
          // --- the sun: gold leaf, flattened a little at its base, behind the waves
          vec2 q = p - uSun.xy; q.y *= q.y < 0. ? 1.12 : 1.;
          float sd = length(q) / uSun.z, sf = fwidth(sd) + 1e-5;
          float sun = (1. - smoothstep(1. - sf, 1. + sf, sd)) * (1. - inWave);
          float low = smoothstep(.75, -.6, q.y / uSun.z);                   // reddening toward the base
          float mott = vn(p * .9) * .7 + vn(p * 3.1) * .3;
          vec3 goldC = vec3(1., .74, .36), redGold = vec3(.95, .38, .16);
          vec3 sunC = mix(goldC * 1.05, redGold, low * .8) * (.96 + mott * .07);
          float metal = max(gold, sun);
          diffuseColor.rgb = mix(diffuseColor.rgb, goldC * (.92 + mott * .1), gold);
          diffuseColor.rgb = mix(diffuseColor.rgb, sunC, sun);
          // gold-leaf crinkle on the sun (very low amplitude)
          // the lacquer's own faint brushed waviness
          nLoc = normalize(nLoc + vec3(vn(p * .45) - .5, vn(p * .45 + 7.) - .5, 0.) * .012 * (1. - metal));`)
        .replace('#include <normal_fragment_maps>', `#include <normal_fragment_maps>
          normal = normalize(vTx * nLoc.x + vTy * nLoc.y + vTz * nLoc.z);
          #ifdef DOUBLE_SIDED
            normal *= faceDirection;
          #endif`)
        .replace('#include <metalnessmap_fragment>', `#include <metalnessmap_fragment>
          metalnessFactor = metal;`)
        .replace('#include <roughnessmap_fragment>', `#include <roughnessmap_fragment>
          roughnessFactor = mix(roughnessFactor, .26 + mott * .1, metal);`)
        .replace('#include <lights_physical_fragment>', `#include <lights_physical_fragment>
          #ifdef USE_CLEARCOAT
          material.clearcoat *= 1. - metal * .85;
          #endif`);
    };
    m.customProgramCacheKey = () => 'byobu-face';
    return m;
  };

  /* the byōbu: two leaves hinged at the back centre, opened to a shallow V toward the viewer */
  const frameMat = new THREE.MeshPhysicalMaterial({ color: new THREE.Color('#0f0b0a').convertSRGBToLinear(), roughness: .3, clearcoat: 1, clearcoatRoughness: .12, envMap: menv, envMapIntensity: .9 });
  const giltMat = new THREE.MeshStandardMaterial({ color: new THREE.Color(.86, .66, .34), roughness: .3, metalness: 1, envMap: menv, envMapIntensity: 1.2 });
  const screen = new THREE.Group(); scene.add(screen);
  const mkLeaf = side => {   // side -1 (left) or +1 (right); the leaf extends from the hinge (x = 0) outward
    const g = new THREE.Group();
    const cx = side * LW / 2;
    // frame: four rounded lacquer bars, a back board, and the inset face
    const bar = (w, h, x, y) => { const m = new THREE.Mesh(new RoundedBoxGeometry(w, h, LT, 2, .08), frameMat); m.position.set(cx + x, y, 0); m.castShadow = m.receiveShadow = true; g.add(m); };
    bar(LW, FRAME, 0, FRAME / 2); bar(LW, FRAME, 0, LH - FRAME / 2); bar(FRAME, LH, -LW / 2 + FRAME / 2, LH / 2); bar(FRAME, LH, LW / 2 - FRAME / 2, LH / 2);
    const back = new THREE.Mesh(new THREE.BoxGeometry(IW, IH, LT * .5), frameMat); back.position.set(cx, LH / 2, -LT * .2); back.castShadow = true; g.add(back);
    const face = new THREE.Mesh(new THREE.PlaneGeometry(IW, IH, 1, 1), faceMat(side < 0 ? 0 : IW)); face.position.set(cx, LH / 2, LT * .1); face.receiveShadow = true; g.add(face);
    // gilt corner fittings (kanagu): small L plates on the outer corners of the frame's face
    const kg = new THREE.BoxGeometry(.9, .14, .06), kgv = new THREE.BoxGeometry(.14, .9, .06);
    for (const [sx, sy] of [[-1, -1], [1, -1], [-1, 1], [1, 1]]) {
      const ox = cx + sx * (LW / 2 - .45), oy = LH / 2 + sy * (LH / 2 - .07);
      const a = new THREE.Mesh(kg, giltMat); a.position.set(ox, oy, LT / 2 + .03); g.add(a);
      const b = new THREE.Mesh(kgv, giltMat); b.position.set(cx + sx * (LW / 2 - .07), LH / 2 + sy * (LH / 2 - .45), LT / 2 + .03); g.add(b);
    }
    g.rotation.y = -side * OPEN;   // the outer edges come forward
    return g;
  };
  screen.add(mkLeaf(-1), mkLeaf(1));
  screen.position.set(0, 0, 0);
  const blob = contactBlob(LW * 2.3, 3, .5); blob.position.set(0, .004, -1.2); scene.add(blob);
  stage.key.shadow.autoUpdate = true;

  const view = { az: .22, el: .2, dist: 48, target: new THREE.Vector3(-2.1, LH * .44, 0), shift: [0, 0] };   // the screen sits right of centre: the card tag keeps the top-left
  const st = {};
  let hot = 0;
  return {
    scene, camera, post: { ...CARD_POST },
    update(dt, t, s) {
      cardCamera(camera, view, s, st, dt, t);
      hot = damp(hot, s.hover ? 1 : 0, 3, dt);
      // the sun sinks and rises again, very slowly (sine: seamless); a touch higher under the pointer
      const ph = REDUCED ? 0 : Math.sin(t * TAU / 30);
      U.uSun.value.y = IH * .5 + ph * .55 + hot * .45;
    },
  };
}
