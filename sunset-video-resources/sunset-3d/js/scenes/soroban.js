/* Plan card 2 — "Solar loan": a soroban on the paper sweep, set to ¥14,800 (the monthly payment).
   Low open ebony frame (no floor: the paper shows between the rods) with pinned corners, sharp dark boxwood bicones
   on bamboo rods, unit dots on the beam every third rod.
   The ones place is the dotted rod 9, so 1-4-8-0-0 sits on rods 5-9 with the thousands dot under the 4 (14,800).
   Idle loop: the board is cleared with one sweep, the three digits are flicked in one after another, then held.
   Units: cm. Shares the plan-card stage, key and lens with coins.js. */
import { THREE, pbrSet, rng, clamp, lerp, REDUCED } from '../core.js';
import { RoundedBoxGeometry } from 'three/addons/geometries/RoundedBoxGeometry.js';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';
import { CARD_FOV, CARD_POST, metalEnv, paperSweep, contactBlob, cardCamera } from './coins.js';

const RODS = 13, PITCH = 1.72, BEAD_R = .76, BEAD_T = .86, ROD_Y = .86, FRAME_H = 1.3, RAIL = .6, BEAM = .62;
const Z = { back: -2.55, beam0: -.62, beam1: .0, front: 5.05 };   // inner faces (z runs from the heaven side to the earth side)
const VALUE = [0, 0, 0, 0, 0, 1, 4, 8, 0, 0, 0, 0, 0];          // ¥14,800 with the ones on rod 9 (a unit dot)
const LOOP = 14;                                                  // seconds: clear, set 1-4-8, hold

/** Box with rounded edges and UVs in cm, grain along the longest horizontal axis. */
function woodBox(w, h, d, r, off = [0, 0]) {
  const g = new RoundedBoxGeometry(w, h, d, 2, r), p = g.attributes.position.array, n = g.attributes.normal.array, uv = g.attributes.uv.array;
  const long = w >= d ? 'x' : 'z';
  for (let t = 0; t < p.length / 9; t++) {
    let nx = 0, ny = 0, nz = 0; for (let k = 0; k < 3; k++) { nx += n[t * 9 + k * 3]; ny += n[t * 9 + k * 3 + 1]; nz += n[t * 9 + k * 3 + 2]; }
    const ax = Math.abs(nx), ay = Math.abs(ny), az = Math.abs(nz);
    for (let k = 0; k < 3; k++) {
      const i = t * 3 + k, x = p[i * 3], y = p[i * 3 + 1], z = p[i * 3 + 2];
      let u, v;   // u runs along the grain
      if (long === 'x') { if (ay >= ax && ay >= az) { u = x; v = z; } else if (az >= ax) { u = x; v = y; } else { u = z; v = y; } }
      else { if (ay >= ax && ay >= az) { u = z; v = x; } else if (ax >= az) { u = z; v = y; } else { u = x; v = y; } }
      uv[i * 2] = u + off[0]; uv[i * 2 + 1] = v + off[1];
    }
  }
  return g;
}

/** Sharp-edged soroban bicone, axis along y, with its bore. UV v runs pole to pole. */
function beadGeometry() {
  // two straight cones meeting at a knife-sharp equator (separate normals: a crisp crease), small flats round the bore
  const hub = .2, hole = .12, h = BEAD_T / 2;
  const top = new THREE.CylinderGeometry(hub, BEAD_R, h, 48, 1, true); top.translate(0, h / 2, 0);
  const bot = new THREE.CylinderGeometry(BEAD_R, hub, h, 48, 1, true); bot.translate(0, -h / 2, 0);
  const capT = new THREE.RingGeometry(hole, hub, 48, 1); capT.rotateX(-Math.PI / 2); capT.translate(0, h, 0);
  const capB = new THREE.RingGeometry(hole, hub, 48, 1); capB.rotateX(Math.PI / 2); capB.translate(0, -h, 0);
  const parts = [top, bot, capT, capB].map(g => { g = g.index ? g.toNonIndexed() : g; g.deleteAttribute('uv'); return g; });
  return mergeGeometries(parts);
}

export async function create(ctx) {
  const { renderer, env: pageEnv } = ctx;
  const scene = new THREE.Scene();
  const env = pageEnv.studio || metalEnv(renderer), menv = metalEnv(renderer);
  scene.environment = env; scene.environmentIntensity = .45;
  const camera = new THREE.PerspectiveCamera(CARD_FOV, 1.45, 4, 400);
  const R = rng(21);

  const stage = paperSweep(scene, { box: [30, 14], center: [0, 1], keyI: 3.1, back: -18, radius: 18 });

  /* ebony: the darkwood scan pushed near-black, fine streaks kept, satin oil finish */
  const dk = await pbrSet('darkwood');
  for (const k of ['map', 'normalMap', 'roughnessMap', 'aoMap']) if (dk[k]) { dk[k].repeat.set(1 / 40, 1 / 40); dk[k].needsUpdate = true; }
  const ebony = new THREE.MeshPhysicalMaterial({
    map: dk.map, normalMap: dk.normalMap, normalScale: new THREE.Vector2(.3, .3), roughnessMap: dk.roughnessMap, roughness: .5, aoMap: dk.aoMap, aoMapIntensity: .5,
    color: new THREE.Color(.26, .22, .22), clearcoat: .5, clearcoatRoughness: .24, envMap: menv, envMapIntensity: .9,
  });
  // dark boxwood (#6b3f1e) bicones, satin; per-bead tone through instance colour; faint turned rings
  // tsuge boxwood: pale honey, dense and nearly grainless, fine turned rings, satin wax; per-bead tone via instance colour
  const bead = new THREE.MeshPhysicalMaterial({ color: new THREE.Color('#C8AE82').convertSRGBToLinear(), roughness: .36, clearcoat: .55, clearcoatRoughness: .22, envMap: menv, envMapIntensity: 1, sheen: .2, sheenColor: new THREE.Color(1, .85, .6) });
  bead.onBeforeCompile = sh => {
    sh.vertexShader = sh.vertexShader.replace('#include <common>', '#include <common>\nvarying vec3 vBP;').replace('#include <begin_vertex>', '#include <begin_vertex>\nvBP = position;');
    sh.fragmentShader = sh.fragmentShader.replace('#include <common>', '#include <common>\nvarying vec3 vBP;')
      .replace('#include <color_fragment>', `#include <color_fragment>
        float rr = length(vBP.xy) * 38. + vBP.z * 4.;
        float fw = fwidth(rr) + 1e-4;
        float ring = smoothstep(.5 - fw, .5 + fw, abs(fract(rr) - .5) * 2.) * clamp(1. - fw, 0., 1.);
        diffuseColor.rgb *= .95 + ring * .07;`);
  };
  const bamboo = new THREE.MeshStandardMaterial({ color: new THREE.Color(.5, .38, .2), roughness: .45, envMap: menv, envMapIntensity: .7 });
  const ivory = new THREE.MeshStandardMaterial({ color: new THREE.Color(.86, .82, .74), roughness: .4, envMap: menv, envMapIntensity: .6 });
  const brass = new THREE.MeshStandardMaterial({ color: new THREE.Color(.74, .54, .28), roughness: .35, metalness: 1, envMap: menv, envMapIntensity: 1.1 });

  /* the soroban */
  const sb = new THREE.Group();
  const X0 = (RODS - 1) / 2 * PITCH + PITCH / 2, halfW = X0 + RAIL;
  const addWood = (w, h, d, x, y, z, r = .06) => { const m = new THREE.Mesh(woodBox(w, h, d, r, [R() * 30, R() * 30]), ebony); m.position.set(x, y, z); m.castShadow = m.receiveShadow = true; sb.add(m); return m; };
  addWood(halfW * 2, FRAME_H, RAIL, 0, FRAME_H / 2, Z.back - RAIL / 2);
  addWood(halfW * 2, FRAME_H, RAIL, 0, FRAME_H / 2, Z.front + RAIL / 2);
  addWood(RAIL, FRAME_H - .01, Z.front - Z.back + .01, -X0 - RAIL / 2, FRAME_H / 2, (Z.back + Z.front) / 2);
  addWood(RAIL, FRAME_H - .01, Z.front - Z.back + .01, X0 + RAIL / 2, FRAME_H / 2, (Z.back + Z.front) / 2);
  const beamH = .95; addWood(X0 * 2 + .02, beamH, BEAM, 0, ROD_Y + .22, (Z.beam0 + Z.beam1) / 2, .04);
  // back board (the soroban's thin bottom), set well below the beads
  // brass pins through each corner joint (on the rails' top faces)
  const pinGeo = new THREE.CylinderGeometry(.07, .07, .02, 16);
  for (const sx of [-1, 1]) for (const z of [Z.back - RAIL / 2, Z.front + RAIL / 2]) { const pin = new THREE.Mesh(pinGeo, brass); pin.position.set(sx * (X0 + RAIL / 2), FRAME_H + .005, z); sb.add(pin); }
  // unit dots on the beam, every third rod
  const dotGeo = new THREE.CylinderGeometry(.075, .075, .02, 20);
  for (let i = 0; i < RODS; i += 3) { const d = new THREE.Mesh(dotGeo, ivory); d.position.set((i - (RODS - 1) / 2) * PITCH, ROD_Y + .22 + beamH / 2 + .005, (Z.beam0 + Z.beam1) / 2); sb.add(d); }
  // bamboo rods, continuous from rail to rail through the beam
  const rodGeo = new THREE.CylinderGeometry(.1, .1, Z.front - Z.back + RAIL, 10); rodGeo.rotateX(Math.PI / 2);
  const rods = new THREE.InstancedMesh(rodGeo, bamboo, RODS); rods.castShadow = rods.receiveShadow = true;
  const _m = new THREE.Matrix4();
  for (let i = 0; i < RODS; i++) rods.setMatrixAt(i, _m.makeTranslation((i - (RODS - 1) / 2) * PITCH, ROD_Y, (Z.back + Z.front) / 2));
  sb.add(rods);
  // beads: one heaven bead + four earth beads per rod
  const beadGeo = beadGeometry(); beadGeo.rotateX(Math.PI / 2);
  const beads = new THREE.InstancedMesh(beadGeo, bead, RODS * 5); beads.castShadow = beads.receiveShadow = true;
  beads.instanceMatrix.setUsage(THREE.DynamicDrawUsage);
  const spin = [];
  for (let i = 0; i < RODS * 5; i++) {
    spin.push(R() * Math.PI * 2);
    const v = .86 + R() * .24, warm = R() * .12;
    beads.setColorAt(i, new THREE.Color(v, v * (.97 - warm * .5), v * (.95 - warm)));
  }
  sb.add(beads);

  // bead z for a digit v (0..9): heaven bead down to the beam when v >= 5; (v % 5) earth beads up against the beam
  const H_OFF = Z.back + BEAD_T / 2 + .01, H_ON = Z.beam0 - BEAD_T / 2 - .005;
  const earthZ = (k, n) => k < n ? Z.beam1 + BEAD_T / 2 + .005 + k * BEAD_T : Z.front - BEAD_T / 2 - .01 - (3 - k) * BEAD_T;
  const rodZ = v => [v >= 5 ? H_ON : H_OFF, ...[0, 1, 2, 3].map(k => earthZ(k, v % 5))];
  const ZERO = rodZ(0), SET = VALUE.map(rodZ);
  const _q = new THREE.Quaternion(), _e = new THREE.Euler(), _s = new THREE.Vector3(1, 1, 1), _p = new THREE.Vector3();
  const ease = t => { t = clamp(t); return 1 - (1 - t) ** 3; };
  /* the loop, as per-rod progress 0 (cleared) .. 1 (set): digits flicked in 1, 4, 8; the whole board swept clear at the end */
  function rodProgress(i, t) {
    if (REDUCED) return 1;
    const x = ((t % LOOP) + LOOP) % LOOP;
    const order = { 5: 0, 6: 1, 7: 2 }[i];
    const on = order === undefined ? 1 : ease((x - (1.2 + order * .9)) / .28);
    const off = ease((x - (LOOP - 1.4) - (i - 5) * .03) / .45);
    return on * (1 - off);
  }
  let last = '';
  function setBeads(t) {
    const pr = VALUE.map((_, i) => rodProgress(i, t)), key = pr.map(v => v.toFixed(3)).join();
    if (key === last) return false; last = key;
    for (let i = 0; i < RODS; i++) for (let j = 0; j < 5; j++) {
      const idx = i * 5 + j, z = lerp(ZERO[j], SET[i][j], pr[i]);
      _e.set(0, 0, spin[idx]); _q.setFromEuler(_e);
      _p.set((i - (RODS - 1) / 2) * PITCH, ROD_Y, z);
      beads.setMatrixAt(idx, _m.compose(_p, _q, _s));
    }
    beads.instanceMatrix.needsUpdate = true;
    return true;
  }

  /* place the board on the desk, turned a little */
  sb.position.set(0, 0, -(Z.back + Z.front) / 2);
  const pivot = new THREE.Group(); pivot.add(sb); pivot.rotation.y = -.12; pivot.position.set(0, 0, 1); scene.add(pivot);
  const blob = contactBlob(halfW * 2 + 1.2, Z.front - Z.back + 2.2, .32); blob.rotation.z = -.12; blob.position.set(0, .004, 1); scene.add(blob);
  stage.key.shadow.autoUpdate = false; stage.key.shadow.needsUpdate = true;

  const view = { az: .06, el: .95, dist: 44.5, target: new THREE.Vector3(0, .5, 1), shift: [0, .01] };
  const st = {};
  return {
    scene, camera, post: { ...CARD_POST },
    update(dt, t, s) {
      cardCamera(camera, view, s, st, dt, t);
      if (setBeads(t)) stage.key.shadow.needsUpdate = true;
    },
  };
}
