// Hardware card 2 — the 13.5 kWh wall battery: a hinoki cabinet whose front is four vertical boards with crisp 2.5 mm
// chamfers and hairline joints over a slim bottom rail; the rail carries a recessed louvre vent and a steady status
// light, and a small burned sun brand (焼印) sits high on the front. A grey conduit drops from the cabinet into the
// wall. The wall is a short section of yakisugi (charred cedar) board-and-batten on a concrete footing. Shared rig.
import { THREE, makeCanvas, damp, lerp, pbrMaterial } from '../core.js';
import { RoundedBoxGeometry } from 'three/addons/geometries/RoundedBoxGeometry.js';
import { cardLights, cardCamera, bakeGround, silhouettePoints, maskTex, boxUV, hinokiMaterial, hinokiEndMaterial, yakisugiMaterial } from './hw-rig.js';

// footing + wall (m): 5 boards of 150 mm, battens over the joints
const FOOT = .06, BW = .15, NB = 7, WW = BW * NB, WH = 1.06, WT = .05;
// cabinet: body, a bottom rail, four front boards
const CW = .6, CH = .84, CD = .15, FT = .02, CHF = .0025, STANDOFF = .014, CAB_Y = FOOT + .14, RAIL = .085;

export async function create(ctx) {
  const { env, renderer } = ctx;
  const scene = new THREE.Scene();
  const root = new THREE.Group(); scene.add(root);

  /* ---------- concrete footing, yakisugi wall */
  const concrete = await pbrMaterial('plaster', { repeat: [3, 3], tint: new THREE.Color(.56, .6, .68), roughness: 1, normal: 1.4 });
  const footing = new THREE.Mesh(new RoundedBoxGeometry(WW + .06, FOOT, WT + .08, 2, .004), concrete); footing.position.set(0, FOOT / 2, .01); root.add(footing);
  const yaki = yakisugiMaterial(), yakiB = yakisugiMaterial({ tint: 1.12 });
  const backer = new THREE.Mesh(new THREE.BoxGeometry(WW - .01, WH - .01, WT - .02), new THREE.MeshStandardMaterial({ color: 0x0d0c0c, roughness: 1 }));
  backer.position.set(0, FOOT + WH / 2, -.01); root.add(backer);
  for (let i = 0; i < NB; i++) {
    const g = boxUV(new RoundedBoxGeometry(BW - .003, WH, .02, 2, .002), 1, { u0: i * .137, v0: i * .291 });
    const b = new THREE.Mesh(g, yaki); b.position.set(-WW / 2 + BW * (i + .5), FOOT + WH / 2, WT / 2 - .01); root.add(b);
  }
  for (let i = 1; i < NB; i++) {
    const g = boxUV(new RoundedBoxGeometry(.028, WH - .004, .016, 2, .003), 1, { u0: i * .21, v0: i * .17 });
    const bt = new THREE.Mesh(g, yakiB); bt.position.set(-WW / 2 + BW * i, FOOT + WH / 2, WT / 2 + .008); root.add(bt);
  }
  const WALL_FACE = WT / 2 + .016;

  /* ---------- the cabinet */
  const cab = new THREE.Group(); cab.position.set(-.06, CAB_Y, WALL_FACE + STANDOFF); root.add(cab);
  const side = hinokiMaterial({ tint: .95, seed: 4, contrast: .42 }), ends = hinokiEndMaterial({ tint: .94 });
  const dark = new THREE.MeshStandardMaterial({ color: 0x120d09, roughness: 1 });
  const cham = (w, h, d) => new RoundedBoxGeometry(w, h, d, 1, CHF);          // one segment: a true chamfer
  const BD = CD - FT;
  const body = new THREE.Mesh(boxUV(cham(CW, CH, BD), 1, { u0: .11, v0: .37 }), side); body.position.set(0, CH / 2, BD / 2); cab.add(body);
  const back = new THREE.Mesh(new THREE.PlaneGeometry(CW - .006, CH - .006), dark); back.position.set(0, CH / 2, BD + .0004); cab.add(back);
  // bottom rail (horizontal grain) with a recessed louvre vent and the status light
  const FZ = BD + FT;
  const VW = .3, VH = .03, VD = .014, VY = RAIL * .46;
  // the rail is built round the vent opening, so the louvres sit in a real recess
  const railPart = (w, h, x, y, u0) => { const m = new THREE.Mesh(boxUV(cham(w, h, FT), 1, { u0, v0: .1, swap: true }), side); m.position.set(x, y, BD + FT / 2); cab.add(m); return m; };
  const yb = VY - VH / 2, yt = VY + VH / 2;
  railPart(CW, yb, 0, yb / 2, .2); railPart(CW, RAIL - yt, 0, (yt + RAIL) / 2, .27);
  railPart((CW - VW) / 2, VH, -(CW + VW) / 4, VY, .31); railPart((CW - VW) / 2, VH, (CW + VW) / 4, VY, .41);
  const pocket = new THREE.Mesh(new THREE.BoxGeometry(VW, VH, VD), new THREE.MeshStandardMaterial({ color: 0x140e09, roughness: 1, side: THREE.BackSide }));
  pocket.position.set(0, VY, FZ - VD / 2 + .0002); cab.add(pocket);
  const slatMat = hinokiMaterial({ tint: .78, seed: 9, contrast: .3 });
  for (let i = 0; i < 4; i++) { const sl = new THREE.Mesh(new THREE.BoxGeometry(VW - .002, .0022, .013), slatMat); sl.position.set(0, VY - VH / 2 + VH * (i + .6) / 4.2, FZ - VD * .55); sl.rotation.x = -.7; cab.add(sl); }
  const ledMat = new THREE.MeshBasicMaterial({ color: new THREE.Color(1, .3, .02) });
  const led = new THREE.Mesh(new THREE.PlaneGeometry(.036, .003), ledMat); led.position.set(CW / 2 - .065, VY, FZ + .0004); cab.add(led);
  const lc = makeCanvas(128, 64), lg = lc.getContext('2d'), grd = lg.createRadialGradient(64, 32, 0, 64, 32, 64);
  grd.addColorStop(0, 'rgba(255,255,255,1)'); grd.addColorStop(.35, 'rgba(255,255,255,.3)'); grd.addColorStop(1, 'rgba(255,255,255,0)');
  lg.fillStyle = grd; lg.save(); lg.scale(1, .5); lg.fillRect(0, 0, 128, 128); lg.restore();
  const glowMat = new THREE.MeshBasicMaterial({ color: new THREE.Color(1, .42, .1), alphaMap: maskTex(lc), transparent: true, depthWrite: false, opacity: .3 });
  const glow = new THREE.Mesh(new THREE.PlaneGeometry(.06, .016), glowMat); glow.position.copy(led.position).setZ(FZ + .0006); cab.add(glow);
  // four vertical front boards, chamfered, hairline joints between them
  const NBF = 4, fbW = (CW - .003 * (NBF - 1)) / NBF, fbH = CH - RAIL - .002;
  const boards = [];
  for (let i = 0; i < NBF; i++) {
    const m = hinokiMaterial({ tint: .97 + (i % 2) * .03, seed: 20 + i, contrast: .42 });
    const b = new THREE.Mesh(boxUV(cham(fbW, fbH, FT), 1, { u0: i * .173, v0: i * .31 }), m);
    b.position.set(-CW / 2 + fbW / 2 + i * (fbW + .003), RAIL + .002 + fbH / 2, BD + FT / 2); cab.add(b); boards.push(b);
  }
  // 焼印: a small burned sun brand, low contrast, high on the second board's joint line
  const bc = makeCanvas(256, 160), bg = bc.getContext('2d');
  bg.filter = 'blur(1.5px)'; bg.fillStyle = '#fff';
  bg.beginPath(); bg.arc(128, 112, 62, Math.PI, 0); bg.closePath(); bg.fill(); bg.fillRect(40, 124, 176, 10);
  const brand = new THREE.Mesh(new THREE.PlaneGeometry(.052, .0325), new THREE.MeshStandardMaterial({ color: 0x5a3218, alphaMap: maskTex(bc), transparent: true, opacity: .6, roughness: .95, depthWrite: false, polygonOffset: true, polygonOffsetFactor: -2 }));
  brand.position.set(-CW / 2 + fbW * 1.5 + .003, CH * .82, FZ + .0003); cab.add(brand);
  const cleat = new THREE.Mesh(new THREE.BoxGeometry(CW - .12, CH - .16, STANDOFF), dark); cleat.position.set(0, CH / 2, -STANDOFF / 2); cab.add(cleat);

  /* ---------- a grey conduit from the cabinet's underside, straight down, then into the wall */
  const metal = new THREE.MeshStandardMaterial({ color: 0x7c8088, metalness: .5, roughness: .45 });
  const gx = CW / 2 - .085, gz = BD * .5, CRAD = .011, DROP = CAB_Y - FOOT - .055, BEND = .04;
  const gland = new THREE.Mesh(new THREE.CylinderGeometry(.016, .016, .016, 6), metal); gland.position.set(gx, -.008, gz); cab.add(gland);
  const path = new THREE.CurvePath(), V = (x, y, z) => new THREE.Vector3(x, y, z);
  path.add(new THREE.LineCurve3(V(gx, -.016, gz), V(gx, -DROP, gz)));
  path.add(new THREE.QuadraticBezierCurve3(V(gx, -DROP, gz), V(gx, -DROP - BEND, gz), V(gx, -DROP - BEND, gz - BEND)));
  path.add(new THREE.LineCurve3(V(gx, -DROP - BEND, gz - BEND), V(gx, -DROP - BEND, -STANDOFF - .01)));
  cab.add(new THREE.Mesh(new THREE.TubeGeometry(path, 96, CRAD, 20), metal));
  const esc = new THREE.Mesh(new THREE.CylinderGeometry(.024, .026, .006, 40), metal); esc.rotation.x = Math.PI / 2; esc.position.set(gx, -DROP - BEND, -STANDOFF + .003); cab.add(esc);

  const noCast = new Set([back, brand, glow, led, pocket]);
  root.traverse(o => { if (o.isMesh) { o.castShadow = !noCast.has(o) && o.material !== dark; o.receiveShadow = true; } });
  body.castShadow = cleat.castShadow = true;

  /* ---------- light, paper, lens */
  cardLights(scene, env, new THREE.Box3().setFromObject(root));
  const { foot } = bakeGround(renderer, scene, root);
  const rig = cardCamera(silhouettePoints(root), { shadow: foot, XC: -.05 });

  let hov = 0;
  return {
    scene, camera: rig.camera, tone: 'aces', exposure: 1,
    update(dt, t, s) {
      rig.update(dt, t, s);
      hov = damp(hov, s.hover ? 1 : 0, 4, dt);
      const k = lerp(1.2, 1.6, hov);                     // steady: brighter on hover, never blinking
      ledMat.color.setRGB(k, .26 * k, .015 * k);
      glowMat.opacity = .28 + .12 * hov;
    },
  };
}
