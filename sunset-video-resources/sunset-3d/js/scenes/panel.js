// Hardware card 1 — one all-black 440 W module on a section of ibushi-gin kawara roof.
// A cut section of roof resting on the paper: pale rafters whose ends sit on the paper at the eave, a purlin on a post
// under the high end, a roof board and tile battens — all showing clean sawn end grain at the cut — and separate
// smoked-silver J-tiles (ibushi-gin) laid in columns, each a hair off true, with manju-ended eave tiles and a ridge.
// The module covers the upper right of the slice so the roof reads around it; two black rails on stainless hooks hold
// it 5 cm clear of the tile crowns. Its glass (a real clearcoat, F0 .04) reflects a soft dusk dome. Shared card rig.
import { THREE, canvasTexture, makeCanvas, rng, clamp, pbrMaterial } from '../core.js';
import { RoundedBoxGeometry } from 'three/addons/geometries/RoundedBoxGeometry.js';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';
import { HW, cardLights, cardCamera, bakeGround, silhouettePoints, hinokiEndMaterial } from './hw-rig.js';

const PITCH = THREE.MathUtils.degToRad(26);
const PW = 1.05, PL = 1.72, FR = .035;                  // module (m)
const TW = .30, TS = .265, TL = .30, TE = .235;          // tile width, column spacing, length, exposure
const COLS = 7, ROWS = 11;                                 // 2 columns left and 2 courses below the module's own
const RW = TS * (COLS - 1) + TW, RL = TE * ROWS + .06;   // roof board
const BOARD = .018, RAF = .075, BAT = .018;               // board, rafter depth, batten height
const A = .015, B = .025, TT = .014, LIFT = TT * 1.25;    // pan depth, roll height, tile thickness, lower-end lift
const DATUM = BAT + A + TT * .4;                          // tile pans rest on the battens

/* ---------------------------------------------------------------- cells: one half-cut cell per texture repeat */
export function cellTextures() {
  const W = 512, H = 256;                                  // 166 × 83 mm half cell
  const c = makeCanvas(W, H), g = c.getContext('2d');
  const m = makeCanvas(W, H), gm = m.getContext('2d');     // G = roughness, B = metalness
  const gap = 10, ch = 20;
  g.fillStyle = '#2a2d33'; g.fillRect(0, 0, W, H);          // charcoal backsheet between cells
  gm.fillStyle = 'rgb(0,190,0)'; gm.fillRect(0, 0, W, H);
  const cellPath = (ctx) => {
    const x0 = gap / 2, y0 = gap / 2, x1 = W - gap / 2, y1 = H - gap / 2;
    ctx.beginPath(); ctx.moveTo(x0 + ch, y0); ctx.lineTo(x1 - ch, y0); ctx.lineTo(x1, y0 + ch); ctx.lineTo(x1, y1 - ch); ctx.lineTo(x1 - ch, y1);
    ctx.lineTo(x0 + ch, y1); ctx.lineTo(x0, y1 - ch); ctx.lineTo(x0, y0 + ch); ctx.closePath();
  };
  cellPath(g); g.fillStyle = '#111623'; g.fill();
  const r = rng(41);
  g.save(); cellPath(g); g.clip();
  for (let i = 0; i < 900; i++) { const x = r() * W, y = r() * H, s = 2 + r() * 10; g.fillStyle = `rgba(${40 + r() * 30 | 0},${46 + r() * 30 | 0},${62 + r() * 36 | 0},${.03 + r() * .05})`; g.fillRect(x, y, s, s * .6); }
  for (let y = gap / 2 + 4; y < H - gap / 2; y += 6) { g.fillStyle = 'rgba(120,126,140,.12)'; g.fillRect(0, y, W, 1); }   // fingers
  for (let i = 0; i < 5; i++) { const x = gap / 2 + (i + .5) * (W - gap) / 5; g.fillStyle = '#4a4f5a'; g.fillRect(x - 3, 0, 6, H); }   // busbars
  g.restore();
  gm.save(); cellPath(gm); gm.fillStyle = 'rgb(0,130,0)'; gm.fill(); gm.clip();
  for (let i = 0; i < 5; i++) { const x = gap / 2 + (i + .5) * (W - gap) / 5; gm.fillStyle = 'rgb(0,90,200)'; gm.fillRect(x - 3, 0, 6, H); }
  gm.restore();
  const map = canvasTexture(c, { repeat: [1, 1] }), mr = canvasTexture(m, { srgb: false, repeat: [1, 1] });
  return { map, mr };
}

/* ---------------------------------------------------------------- one sangawara J-tile
   local: x across (0 .. TW, pan left, roll right), z along the slope (-TL/2 up .. +TL/2 eave end), y up. */
const prof = u => u < .66 ? -A * Math.sin(Math.PI * u / .66) : B * Math.pow(Math.sin(Math.PI * (u - .66) / .34), .8);
const liftAt = z => LIFT * (z / TL + .5);
function tileGeometry() {
  const NX = 32, NZ = 16, pos = [], col = [], uv = [], idx = [];
  const add = (x, y, z, k) => { pos.push(x, y, z); col.push(k, k, k); uv.push(x, z); return pos.length / 3 - 1; };
  // baked occlusion: deep in the pan, and a dark band just below the lip of the course above (the overlap)
  const OVL = -TL / 2 + (TL - TE);
  const ao = (u, z) => (.74 + .26 * clamp(prof(u) / A + .9)) * (z < OVL ? .3 : .36 + .64 * Math.pow(clamp((z - OVL) / .045), .7));
  const top = [], bot = [];
  for (let j = 0; j <= NZ; j++) for (let i = 0; i <= NX; i++) {
    const u = i / NX, x = u * TW, z = -TL / 2 + TL * j / NZ, y = prof(u) + liftAt(z);
    top.push(add(x, y, z, ao(u, z))); bot.push(add(x, y - TT, z, .5));
  }
  const at = (arr, i, j) => arr[j * (NX + 1) + i];
  for (let j = 0; j < NZ; j++) for (let i = 0; i < NX; i++) {
    idx.push(at(top, i, j), at(top, i, j + 1), at(top, i + 1, j), at(top, i + 1, j), at(top, i, j + 1), at(top, i + 1, j + 1));
    idx.push(at(bot, i, j), at(bot, i + 1, j), at(bot, i, j + 1), at(bot, i + 1, j), at(bot, i + 1, j + 1), at(bot, i, j + 1));
  }
  const strip = (pts, k) => {
    const base = pos.length / 3;
    for (const [x, y, z] of pts) { add(x, y, z, k); add(x, y - TT, z, k * .7); }
    for (let i = 0; i < pts.length - 1; i++) { const a = base + i * 2; idx.push(a, a + 1, a + 2, a + 2, a + 1, a + 3); }
  };
  const lip = []; for (let i = 0; i <= NX; i++) { const u = i / NX; lip.push([u * TW, prof(u) + liftAt(TL / 2), TL / 2]); }
  strip(lip, .8);
  for (const u of [0, 1]) { const e = []; for (let j = 0; j <= NZ; j++) { const z = -TL / 2 + TL * j / NZ; e.push([u * TW, prof(u) + liftAt(z), z]); } strip(u ? e : e.reverse(), .78); }
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  g.setAttribute('color', new THREE.Float32BufferAttribute(col, 3));
  g.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2));
  g.setIndex(idx); g.computeVertexNormals();
  return g;
}
function mottle(size, seed, { lo = 150, a = .1 } = {}) {
  const c = makeCanvas(size, size), g = c.getContext('2d'), r = rng(seed);
  g.fillStyle = 'rgb(200,200,200)'; g.fillRect(0, 0, size, size);
  for (let i = 0; i < 1600; i++) {
    const x = r() * size, y = r() * size, rad = 3 + r() ** 3 * size * .12, v = lo + r() * (255 - lo) | 0;
    const gr = g.createRadialGradient(x, y, 0, x, y, rad); gr.addColorStop(0, `rgba(${v},${v},${v},${a})`); gr.addColorStop(1, `rgba(${v},${v},${v},0)`);
    g.fillStyle = gr;
    for (const ox of [-size, 0, size]) for (const oy of [-size, 0, size]) g.fillRect(x - rad + ox, y - rad + oy, rad * 2, rad * 2);
  }
  const t = canvasTexture(c, { srgb: false }); t.wrapS = t.wrapT = THREE.RepeatWrapping; t.repeat.set(2.4, 2.4);
  return t;
}
function endGrain() {        // sawn end of a charcoal-stained timber: faint rings
  const S = 128, c = makeCanvas(S, S), g = c.getContext('2d');
  g.fillStyle = '#3b3129'; g.fillRect(0, 0, S, S);
  for (let i = 40; i > 0; i--) { g.strokeStyle = i % 2 ? 'rgba(20,14,10,.35)' : 'rgba(90,72,58,.25)'; g.lineWidth = 1.4; g.beginPath(); g.arc(S * .2, S * 1.3, i * 5, 0, Math.PI * 2); g.stroke(); }
  return canvasTexture(c);
}

/** A soft, dim dusk dome for the glass: warm toward the sun (front-left), lavender overhead, dark below the horizon. */
function duskEnv(renderer) {
  const sc = new THREE.Scene();
  const m = new THREE.ShaderMaterial({
    side: THREE.BackSide, depthWrite: false,
    uniforms: { uSun: { value: HW.keyDir.clone() } },
    vertexShader: 'varying vec3 vD; void main(){ vD = normalize(position); gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.); }',
    fragmentShader: /* glsl */`uniform vec3 uSun; varying vec3 vD;
      void main(){
        vec3 d = normalize(vD); float t = dot(d, normalize(uSun));
        vec3 zen = vec3(.035, .04, .09), mid = vec3(.13, .11, .2), warm = vec3(.9, .5, .32);
        vec3 c = mix(zen, mid, smoothstep(.95, .2, d.y));
        c = mix(c, warm, smoothstep(.55, .98, t) * .85);
        c = mix(c, vec3(.03, .025, .03), smoothstep(.02, -.1, d.y));
        gl_FragColor = vec4(c, 1.);
      }`,
  });
  sc.add(new THREE.Mesh(new THREE.SphereGeometry(10, 48, 24), m));
  const pm = new THREE.PMREMGenerator(renderer), tex = pm.fromScene(sc, .02).texture; pm.dispose(); m.dispose();
  return tex;
}

export async function create(ctx) {
  const { env, renderer } = ctx;
  const scene = new THREE.Scene();
  const root = new THREE.Group(); scene.add(root);

  /* ---------- roof frame: pale sawn timber, end grain at every cut */
  const pale = await pbrMaterial('sugi', { repeat: [2, 2], tint: new THREE.Color(1.95, 2.3, 2.9), roughness: 1, normal: .7 });
  const ends = hinokiEndMaterial({ tint: .9 });
  const grainAlongX = [ends, ends, pale, pale, pale, pale], grainAlongZ = [pale, pale, pale, pale, ends, ends];
  const roof = new THREE.Group(); roof.rotation.x = PITCH;
  roof.position.y = (BOARD + RAF) * Math.cos(PITCH) + RL / 2 * Math.sin(PITCH) - .002;   // rafter feet on the paper at the eave
  root.add(roof);
  const board = new THREE.Mesh(new THREE.BoxGeometry(RW, BOARD, RL), [ends, ends, pale, pale, pale, pale]); board.position.y = -BOARD / 2; roof.add(board);
  for (const x of [-RW / 2 + .0225, -RW / 6, RW / 6, RW / 2 - .0225]) {
    const r = new THREE.Mesh(new THREE.BoxGeometry(.045, RAF, RL), grainAlongZ); r.position.set(x, -BOARD - RAF / 2, 0); roof.add(r);
  }
  roof.updateMatrixWorld(true);
  const toWorld = (x, y, z) => new THREE.Vector3(x, y, z).applyMatrix4(roof.matrixWorld);
  const under = toWorld(0, -BOARD - RAF, -RL / 2 + .2), PUR = .09;
  const purlin = new THREE.Mesh(new THREE.BoxGeometry(RW, PUR, PUR), grainAlongX); purlin.position.set(0, under.y - PUR / 2, under.z); root.add(purlin);
  for (const x of [-RW / 2 + .2, RW / 2 - .2]) { const hgt = under.y - PUR; const post = new THREE.Mesh(new THREE.BoxGeometry(.09, hgt, .09), [pale, pale, ends, ends, pale, pale]); post.position.set(x, hgt / 2, under.z); root.add(post); }
  for (let row = 0; row < ROWS; row++) {        // tile battens: their sawn ends show at the cut
    const z = RL / 2 + .025 - row * TE - TL + .03;
    const b = new THREE.Mesh(new THREE.BoxGeometry(RW, BAT, .024), grainAlongX); b.position.set(0, BAT / 2, z); roof.add(b);
  }

  /* ---------- tiles: ibushi-gin — dark smoked silver, satin, smoky mottling, each tile its own tone */
  const tgeo = tileGeometry();
  const tileMat = new THREE.MeshStandardMaterial({ color: 0x7490b2, vertexColors: true, metalness: .24, roughness: .5, roughnessMap: mottle(256, 9, { lo: 160, a: .1 }), map: mottle(256, 17, { lo: 150, a: .08 }) });
  const footU = { uFoot: { value: new THREE.Vector4(0, 0, PW / 2 + .02, PL / 2 + .02) } };
  tileMat.onBeforeCompile = (sh) => {
    Object.assign(sh.uniforms, footU);
    sh.vertexShader = sh.vertexShader.replace('#include <common>', '#include <common>\nvarying vec3 vRoof; varying float vJit; varying float vCrown;')
      .replace('#include <uv_vertex>', `#include <uv_vertex>
        vJit = 0.;
        #ifdef USE_INSTANCING
          vec2 io = fract(vec2(float(gl_InstanceID)) * vec2(.371, .613));
          vJit = fract(float(gl_InstanceID) * .7548) - .5;
          #ifdef USE_MAP
            vMapUv += io;
          #endif
          #ifdef USE_ROUGHNESSMAP
            vRoughnessMapUv += io.yx;
          #endif
        #endif`)
      .replace('#include <begin_vertex>', '#include <begin_vertex>\nvCrown = smoothstep(.004, .02, transformed.y - (' + (LIFT * .5).toFixed(4) + '));\n#ifdef USE_INSTANCING\n vRoof = (instanceMatrix * vec4(transformed, 1.)).xyz;\n#else\n vRoof = transformed;\n#endif');
    sh.fragmentShader = sh.fragmentShader.replace('#include <common>', '#include <common>\nvarying vec3 vRoof; varying float vJit; varying float vCrown; uniform vec4 uFoot;')
      .replace('#include <roughnessmap_fragment>', '#include <roughnessmap_fragment>\n roughnessFactor = mix(clamp(roughnessFactor * (1. + vJit * .08), .5, .6), .28, vCrown * .8);')
      .replace('#include <lights_fragment_end>', `#include <lights_fragment_end>
        { vec2 q = abs(vRoof.xz - uFoot.xy) - uFoot.zw;
          float d = length(max(q, 0.)) + min(max(q.x, q.y), 0.);
          float o = mix(.4, 1., smoothstep(-.06, .05, d));
          reflectedLight.indirectDiffuse *= o; reflectedLight.indirectSpecular *= o; reflectedLight.directSpecular *= mix(1., o, .5); }`);
  };
  const tiles = new THREE.InstancedMesh(tgeo, tileMat, COLS * ROWS);
  const r = rng(5), m4 = new THREE.Matrix4(), q = new THREE.Quaternion(), e = new THREE.Euler(), p = new THREE.Vector3(), sc = new THREE.Vector3(1, 1, 1), c = new THREE.Color();
  let n = 0;
  const colX = col => -RW / 2 + col * TS;
  for (let row = 0; row < ROWS; row++) {
    const zLow = RL / 2 + .025 - row * TE;
    for (let col = 0; col < COLS; col++) {
      e.set((r() - .5) * .018, (r() - .5) * .02, (r() - .5) * .024); q.setFromEuler(e);
      p.set(colX(col) + (r() - .5) * .007, DATUM + (r() - .5) * .004, zLow - TL / 2 + (r() - .5) * .007);
      m4.compose(p, q, sc); tiles.setMatrixAt(n, m4);
      const k = .96 + r() * .08, w = (r() - .5) * .02; c.setRGB(k * (1 - w), k, k * (1 + w)); tiles.setColorAt(n, c);
      n++;
    }
  }
  tiles.computeBoundingSphere(); roof.add(tiles);
  const tileSolid = new THREE.MeshStandardMaterial({ color: 0x6d88aa, metalness: .24, roughness: .42 });
  // eave course: manju (round ends) on each roll and a tare lip under each pan
  const zE = RL / 2 + .025 + .004, yE = DATUM + LIFT;
  for (let col = 0; col < COLS; col++) {
    const x0 = colX(col);
    const man = new THREE.Mesh(new THREE.CylinderGeometry(.046, .046, .018, 40), tileSolid);
    man.rotation.x = Math.PI / 2; man.scale.set(1, 1, .82); man.position.set(x0 + .83 * TW, yE + B * .35, zE); roof.add(man);
    const tare = new THREE.Mesh(new RoundedBoxGeometry(.19, .04, .014, 2, .004), tileSolid); tare.position.set(x0 + .33 * TW, yE - A - .01, zE - .002); roof.add(tare);
  }
  // ridge: a stack of noshi-gawara, a half-round ganburi cap, and an onigawara on the gable facing the camera
  const zR = -RL / 2 + .07, yR = DATUM + B * .5;
  for (let i = 0; i < 5; i++) { const w = .13 - i * .012, nb = new THREE.Mesh(new RoundedBoxGeometry(RW + .02 - i * .004, .014, w, 1, .003), tileSolid); nb.position.set(0, yR + .007 + i * .0145, zR); roof.add(nb); }
  const capY = yR + .075;
  const gan = new THREE.Mesh(new THREE.CylinderGeometry(.042, .042, RW + .01, 40, 1, false, 0, Math.PI), tileSolid);
  gan.rotation.z = Math.PI / 2; gan.position.set(0, capY, zR); roof.add(gan);
  { // onigawara: a thick arched plate with a raised boss, on the +x gable
    const o = new THREE.Shape(), W = .09, H = .15;
    o.moveTo(-W, 0); o.lineTo(-W * .95, H * .55); o.quadraticCurveTo(-W * .95, H, 0, H * 1.02); o.quadraticCurveTo(W * .95, H, W * .95, H * .55); o.lineTo(W, 0); o.closePath();
    const og = new THREE.ExtrudeGeometry(o, { depth: .028, bevelEnabled: true, bevelThickness: .004, bevelSize: .004, bevelSegments: 2 });
    const oni = new THREE.Mesh(og, tileSolid); oni.rotation.y = Math.PI / 2; oni.position.set(RW / 2 + .01, yR - .02, zR); roof.add(oni);
    const boss = new THREE.Mesh(new THREE.CylinderGeometry(.026, .03, .012, 32), tileSolid); boss.rotation.z = Math.PI / 2; boss.position.set(RW / 2 + .046, yR + .05, zR); roof.add(boss);
  }
  // sode-gawara: verge tiles turning down over the left edge, one per course
  for (let row = 0; row < ROWS; row++) {
    const zc = RL / 2 + .025 - row * TE - TE / 2;
    const fl = new THREE.Mesh(new RoundedBoxGeometry(.016, .07, TE + .004, 2, .004), tileSolid); fl.position.set(-RW / 2 - .004, DATUM - .028, zc); roof.add(fl);
    const lip = new THREE.Mesh(new RoundedBoxGeometry(.03, .016, TE + .004, 2, .006), tileSolid); lip.position.set(-RW / 2 + .006, DATUM + .004, zc); roof.add(lip);
  }

  /* ---------- the module's place: upper right of the slice */
  const MX = -RW / 2 + 2 * TS + (4 * TS + TW) / 2, MZ = RL / 2 + .025 - 2 * TE - (9 * TE) / 2 + .02;
  footU.uFoot.value.x = MX; footU.uFoot.value.y = MZ;

  /* ---------- rails on stainless hooks, hidden under the module but for their ends */
  const black = new THREE.MeshStandardMaterial({ color: 0x141416, metalness: .55, roughness: .4 });
  const steel = new THREE.MeshStandardMaterial({ color: 0xb9b6b0, metalness: 1, roughness: .3 });
  const tileTop = (x, z) => {
    const col = clamp(Math.floor((x + RW / 2) / TS), 0, COLS - 1), u = (x + RW / 2 - col * TS) / TW;
    const row = Math.floor((RL / 2 + .025 - z) / TE), zl = z - (RL / 2 + .025 - row * TE - TL / 2);
    return DATUM + prof(clamp(u, 0, 1)) + liftAt(clamp(zl, -TL / 2, TL / 2));
  };
  const RAIL_Y = .12, RAIL_H = .04, RAIL_L = PW - .06, railZ = [MZ - PL * .28, MZ + PL * .28];
  for (const z of railZ) {
    const rail = new THREE.Mesh(new RoundedBoxGeometry(RAIL_L, RAIL_H, .04, 2, .004), black); rail.position.set(MX, RAIL_Y + RAIL_H / 2, z); roof.add(rail);
    for (const col of [3, 5]) {
      const hx = colX(col) + TW * .3, zz = z + .03, foot = tileTop(hx, zz), hgt = RAIL_Y - foot + .004;
      const riser = new THREE.Mesh(new RoundedBoxGeometry(.03, hgt, .006, 1, .002), steel); riser.position.set(hx, foot + hgt / 2 - .002, zz); roof.add(riser);
      const seat = new THREE.Mesh(new RoundedBoxGeometry(.034, .006, .056, 1, .002), steel); seat.position.set(hx, RAIL_Y - .002, z); roof.add(seat);
    }
  }

  /* ---------- the module */
  const mod = new THREE.Group(); mod.position.set(MX, RAIL_Y + RAIL_H, MZ); roof.add(mod);
  const frameMat = new THREE.MeshStandardMaterial({ color: 0x0c0c0e, metalness: .6, roughness: .34 });
  const LIP = .012;
  const barL = new RoundedBoxGeometry(LIP * 2.4, FR, PL, 2, .003), barW = new RoundedBoxGeometry(PW, FR, LIP * 2.4, 2, .003);
  for (const s of [-1, 1]) {
    const a = new THREE.Mesh(barL, frameMat); a.position.set(s * (PW / 2 - LIP * 1.2), FR / 2, 0); mod.add(a);
    const b = new THREE.Mesh(barW, frameMat); b.position.set(0, FR / 2, s * (PL / 2 - LIP * 1.2)); mod.add(b);
  }
  // cells under a real glass layer: clearcoat (F0 .04, roughness .12) reflecting a soft dusk dome that moves with the view
  const dusk = duskEnv(renderer);
  const { map, mr } = cellTextures();
  const MID = .02, IN_W = PW - LIP * 2.8, HALF = (PL - LIP * 2.8 - MID) / 2;
  const glass = new THREE.MeshPhysicalMaterial({ map, roughnessMap: mr, roughness: 1, metalness: 0, color: new THREE.Color(.3, .34, .48), specularIntensity: .25, clearcoat: .6, clearcoatRoughness: .08, envMap: env.studio || dusk, envMapIntensity: .9 });
  for (const t of [glass.map, glass.roughnessMap]) { t.repeat.set(6, 10); t.needsUpdate = true; }
  for (const sgn of [-1, 1]) {
    const g = new THREE.PlaneGeometry(IN_W, HALF); g.translate(0, sgn * (HALF / 2 + MID / 2), 0);
    const pl = new THREE.Mesh(g, glass); pl.rotation.x = -Math.PI / 2; pl.position.y = FR - .003; mod.add(pl); pl.userData.glass = true;
  }
  const mid = new THREE.Mesh(new THREE.PlaneGeometry(IN_W, MID), new THREE.MeshPhysicalMaterial({ color: 0x14171e, roughness: .7, specularIntensity: .25, clearcoat: .6, clearcoatRoughness: .08, envMap: env.studio || dusk, envMapIntensity: .9 }));
  mid.rotation.x = -Math.PI / 2; mid.position.y = FR - .003; mod.add(mid); mid.userData.glass = true;
  const back = new THREE.Mesh(new THREE.PlaneGeometry(PW - .01, PL - .01), new THREE.MeshStandardMaterial({ color: 0x0b0b0c, roughness: .8, side: THREE.DoubleSide }));
  back.rotation.x = Math.PI / 2; back.position.y = .003; mod.add(back);
  for (const z of railZ) for (const s of [-1, 1]) {     // low end clamps tucked under the frame lip
    const cl = new THREE.Mesh(new RoundedBoxGeometry(.012, FR + .002, .04, 1, .002), black); cl.position.set(s * (PW / 2 + .005), (FR + .002) / 2, z - MZ); mod.add(cl);
  }

  root.traverse(o => { if (o.isMesh) { o.castShadow = !o.userData.glass; o.receiveShadow = true; } });

  /* ---------- light, paper, lens */
  const box = new THREE.Box3().setFromObject(root);
  cardLights(scene, env, box);
  const { foot } = bakeGround(renderer, scene, root);
  const rig = cardCamera(silhouettePoints(root), { shadow: foot });

  return { scene, camera: rig.camera, tone: 'aces', exposure: 1, update(dt, t, s) { rig.update(dt, t, s); } };
}
