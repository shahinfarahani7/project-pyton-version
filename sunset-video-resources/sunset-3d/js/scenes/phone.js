// Hardware card 3 — the Sunset app. The iPhone stands in a low hinoki block, its foot 9 mm down a real slanted slot,
// leaned back so its screen is square to the card's lens (the UI is never seen in perspective; the camera only trucks).
// The screen is a canvas UI in the page's own type, sized so every label is at least ~11 CSS px on the page.
// Shared card rig (hw-rig.js): one lens, one sun, baked soft ground shadow with contact AO.
import { THREE, canvasTexture, makeCanvas, clamp, E, REDUCED } from '../core.js';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import { HW, cardLights, cardCamera, bakeGround, silhouettePoints, boxUV, hinokiMaterial, hinokiEndMaterial } from './hw-rig.js';

const C = { bg: '#FBF6EE', card: '#F1E6D4', ink: '#1E1916', ink2: '#51463D', ink3: '#7E7165', sun: '#EC6A3C', verm: '#D5452B', gold: '#E7B266', cream: '#FBF5EA' };
const S = .0715 / 3.035;                       // GLB units -> metres (the body is 3.035 units wide)

/* ---------------------------------------------------------------- the app UI: a dark evening screen (600 × 1306)
   On the page the screen is ~110 CSS px wide on desktop and ~95 on a phone, so 72 canvas px ≥ 11 CSS px. Three
   things only: the greeting, the battery ring, the month's saving. The bottom ~10 % sits down in the stand's slot. */
const UW = 600, UH = 1306, MIN = 72;
async function loadFonts() {
  try {
    await Promise.all(['400 100px "Instrument Serif"', 'italic 400 100px "Instrument Serif"', '500 72px "Instrument Sans"', '600 72px "Instrument Sans"'].map(f => document.fonts.load(f)));
    await document.fonts.ready;
  } catch (e) { /* fall back */ }
}
const rr = (g, x, y, w, h, r) => { g.beginPath(); g.roundRect(x, y, w, h, r); };
const hoursLeft = ring => Math.round(ring * 13.5 / 1.05);          // 13.5 kWh at an evening draw of ~1 kW
function drawUI(g, st) {
  g.save();
  const bg = g.createLinearGradient(0, 0, 0, UH); bg.addColorStop(0, '#2a1d2b'); bg.addColorStop(.55, '#1b1420'); bg.addColorStop(1, '#130f17');
  g.fillStyle = bg; g.fillRect(0, 0, UW, UH);
  const glow = g.createRadialGradient(UW * .85, 60, 10, UW * .85, 60, 520); glow.addColorStop(0, 'rgba(236,106,60,.28)'); glow.addColorStop(1, 'rgba(236,106,60,0)');
  g.fillStyle = glow; g.fillRect(0, 0, UW, UH);
  g.textBaseline = 'alphabetic';
  g.fillStyle = C.cream; g.font = `600 ${MIN - 6}px "Instrument Sans"`; g.fillText('18:42', 50, 96);
  for (let i = 0; i < 4; i++) g.fillRect(424 + i * 15, 82 - i * 9, 11, 16 + i * 9);
  rr(g, 492, 58, 60, 34, 10); g.lineWidth = 4; g.strokeStyle = C.cream; g.stroke(); rr(g, 498, 64, 40, 22, 5); g.fill();
  // greeting
  g.fillStyle = C.cream; g.font = '400 132px "Instrument Serif"'; g.fillText('Good', 44, 258);
  g.fillStyle = '#F08A4B'; g.font = 'italic 400 132px "Instrument Serif"'; g.fillText('evening', 44, 368);
  // battery ring
  const cx = UW / 2, cy = 600, R = 140, lw = 36;
  g.lineCap = 'round'; g.lineWidth = lw; g.strokeStyle = 'rgba(251,245,234,.1)';
  g.beginPath(); g.arc(cx, cy, R, 0, Math.PI * 2); g.stroke();
  const a0 = -Math.PI / 2, a1 = a0 + Math.PI * 2 * st.ring;
  if (st.ring > .003) {
    const cg = g.createConicGradient(a0 - .25, cx, cy);
    cg.addColorStop(0, C.gold); cg.addColorStop(.06, C.gold); cg.addColorStop(.5, C.sun); cg.addColorStop(.92, C.verm); cg.addColorStop(1, C.verm);
    g.strokeStyle = cg; g.beginPath(); g.arc(cx, cy, R, a0, a1); g.stroke();
  }
  const pct = Math.round(st.ring * 100);
  g.textAlign = 'center'; g.fillStyle = C.cream; g.font = '400 168px "Instrument Serif"';
  const pw = g.measureText(String(pct)).width; g.fillText(String(pct), cx - 20, cy + 54);
  g.textAlign = 'left'; g.font = '400 76px "Instrument Serif"'; g.fillText('%', cx - 20 + pw / 2 + 6, cy + 54);
  g.textAlign = 'center'; g.fillStyle = 'rgba(251,245,234,.72)'; g.font = `500 ${MIN}px "Instrument Sans"`; g.fillText(`${hoursLeft(st.ring)} h left`, cx, cy + R + lw / 2 + 78);
  // the month's saving
  g.textAlign = 'left';
  g.strokeStyle = 'rgba(251,245,234,.14)'; g.lineWidth = 3; g.beginPath(); g.moveTo(44, 880); g.lineTo(UW - 44, 880); g.stroke();
  g.fillStyle = 'rgba(251,245,234,.72)'; g.font = `500 ${MIN}px "Instrument Sans"`; g.fillText('This month', 44, 954);
  g.fillStyle = C.gold; g.font = '400 138px "Instrument Serif"'; g.fillText(st.saved, 40, 1068);
  g.fillStyle = 'rgba(251,245,234,.72)'; g.font = `500 ${MIN}px "Instrument Sans"`; g.fillText('saved', 46, 1156);
  g.restore();
}

/* ---------------------------------------------------------------- a fallen somei-yoshino petal */
function petalCanvas() {
  const c = makeCanvas(256, 256), g = c.getContext('2d');
  g.beginPath();
  g.moveTo(128, 250);
  g.bezierCurveTo(84, 226, 40, 150, 50, 70); g.bezierCurveTo(56, 22, 100, 6, 121, 18);
  g.lineTo(128, 30); g.lineTo(135, 18);
  g.bezierCurveTo(156, 6, 200, 22, 206, 70); g.bezierCurveTo(216, 150, 172, 226, 128, 250);
  g.closePath();
  const gr = g.createRadialGradient(128, 250, 10, 128, 150, 190);
  gr.addColorStop(0, '#E07F97'); gr.addColorStop(.35, '#F2BCC8'); gr.addColorStop(1, '#FCEBEE');
  g.fillStyle = gr; g.fill();
  g.strokeStyle = 'rgba(214,120,146,.16)'; g.lineWidth = 1.4;
  for (let i = -3; i <= 3; i++) { g.beginPath(); g.moveTo(128, 240); g.quadraticCurveTo(128 + i * 16, 150, 128 + i * 26, 60); g.stroke(); }
  return c;
}
function petalGeometry(len, wid) {
  const g = new THREE.PlaneGeometry(wid, len, 10, 12), p = g.attributes.position;
  for (let i = 0; i < p.count; i++) { const x = p.getX(i) / (wid / 2), y = p.getY(i) / (len / 2); p.setZ(i, .0016 * x * x + .0022 * Math.max(0, y) ** 2); }
  g.rotateX(-Math.PI / 2); g.computeVertexNormals();
  return g;
}

export async function create(ctx) {
  const { env, renderer } = ctx;
  const scene = new THREE.Scene();
  const el = HW.el;

  /* ---------- the phone, leaned back so its screen is square to the shared lens */
  const gltf = await new GLTFLoader().loadAsync('assets/models/iphone18.glb');
  const model = gltf.scene;
  const titanium = new THREE.MeshStandardMaterial({ color: 0xd4cdc3, metalness: 1, roughness: .32 });
  const polished = new THREE.MeshStandardMaterial({ color: 0xe6e0d8, metalness: 1, roughness: .14 });
  const blackGlass = new THREE.MeshPhysicalMaterial({ color: 0x050506, roughness: .1, clearcoat: 1, clearcoatRoughness: .05 });
  const dark = new THREE.MeshStandardMaterial({ color: 0x1b1b1d, roughness: .5, metalness: .3 });
  const backMat = new THREE.MeshStandardMaterial({ color: 0xd8d0c6, roughness: .45, metalness: .1 });
  const cvs = makeCanvas(UW, UH), g = cvs.getContext('2d');
  const uiTex = canvasTexture(cvs); uiTex.generateMipmaps = true; uiTex.minFilter = THREE.LinearMipmapLinearFilter;
  const screenMat = new THREE.MeshBasicMaterial({ map: uiTex, toneMapped: false });
  model.traverse(o => {
    if (!o.isMesh) return;
    const n = o.name.toLowerCase();
    if (n.includes('oled')) {
      o.geometry.computeBoundingBox(); const bb = o.geometry.boundingBox, p = o.geometry.attributes.position, uv = new Float32Array(p.count * 2);
      for (let i = 0; i < p.count; i++) { uv[i * 2] = (p.getX(i) - bb.min.x) / (bb.max.x - bb.min.x); uv[i * 2 + 1] = (bb.max.z - p.getZ(i)) / (bb.max.z - bb.min.z); }
      o.geometry.setAttribute('uv', new THREE.BufferAttribute(uv, 2));
      o.material = screenMat; o.userData.screen = true;
    } else if (n.includes('glass bezel') || n.includes('dynamic island') || n.includes('front camera')) o.material = blackGlass;
    else if (n.includes('polished')) o.material = polished;
    else if (n.includes('antenna')) o.material = dark;
    else if (n.includes('chassis') || n.includes('key')) o.material = titanium;
    else if (n.includes('back insert') || n.includes('enclosure')) o.material = backMat;
    else o.material = dark;
  });
  // screen centre at the origin, screen facing +y, top toward -z
  model.scale.setScalar(S); model.position.set(.0535 * S, -.3 * S, -.068 * S);
  const phone = new THREE.Group(); phone.add(model);
  const tilt = new THREE.Group(); tilt.add(phone); tilt.rotation.x = Math.PI / 2 - el;
  const U0 = new THREE.Vector3(0, Math.cos(el), -Math.sin(el)), N0 = new THREE.Vector3(0, Math.sin(el), Math.cos(el));
  const HALF = .0742, BACK = .0082;                      // screen centre to bottom edge; screen plane to back

  /* ---------- the hinoki stand: one solid block, chamfered top edges, a real slanted slot; the foot sits 8 mm down */
  const SW = .11, SD = .05, SH = .016, SINK = .008, CH = .0022, SLOT_L = .084;
  const lipY = SH, footY = SH - SINK;
  const zFoot = -Math.sin(el) * footY / Math.cos(el);
  const base = new THREE.Vector3(0, footY, zFoot).addScaledVector(U0, HALF);
  tilt.position.copy(base);
  const cF = .0008, cB = -BACK - .0012, cBot = U0.dot(new THREE.Vector3(0, footY, zFoot)) - .0006;
  const onPlanes = (c1, n1, c2, n2) => { const det = n1.z * n2.y - n1.y * n2.z; return [(c1 * n2.y - n1.y * c2) / det, (n1.z * c2 - c1 * n2.z) / det]; };
  const top = { z: 0, y: 1 }, nN = { z: N0.z, y: N0.y }, nU = { z: U0.z, y: U0.y };
  const zc = zFoot + .004, zf = zc + SD / 2, zb = zc - SD / 2;
  const P1 = onPlanes(cF, nN, lipY, top), P2 = onPlanes(cF, nN, cBot, nU), P3 = onPlanes(cB, nN, cBot, nU), P4 = onPlanes(cB, nN, lipY, top);
  const M = ([z, y]) => [-z, y];                        // shape x = -z (the extrusion is turned to run along x)
  const outline = (slot) => {
    const s = new THREE.Shape();
    s.moveTo(...M([zf, 0])); s.lineTo(...M([zf, SH - CH])); s.lineTo(...M([zf - CH, SH]));
    if (slot) { s.lineTo(...M(P1)); s.lineTo(...M(P2)); s.lineTo(...M(P3)); s.lineTo(...M(P4)); }
    s.lineTo(...M([zb + CH, SH])); s.lineTo(...M([zb, SH - CH])); s.lineTo(...M([zb, 0])); s.closePath();
    return s;
  };
  const piece = (slot, x0, len) => {
    let g = new THREE.ExtrudeGeometry(outline(slot), { depth: len, bevelEnabled: false, curveSegments: 1 });
    g.rotateY(Math.PI / 2); g.translate(x0, 0, 0);
    return boxUV(g, 1, { u0: .13, v0: .41, swap: true });
  };
  const standMat = hinokiMaterial({ tint: 1.02, seed: 11, contrast: .26 }); standMat.clearcoat = 0;
  const endMat = hinokiEndMaterial({ tint: .95, seed: 12 });
  const mid = piece(true, -SLOT_L / 2, SLOT_L);
  { // occlusion baked into the slot: darker with depth below the lip
    const P = mid.attributes.position, col = new Float32Array(P.count * 3), v = new THREE.Vector3();
    for (let i = 0; i < P.count; i++) {
      v.fromBufferAttribute(P, i); const nd = N0.dot(v), inSlot = nd < cF + .0004 && nd > cB - .0004 && v.y < lipY - .0005;
      const k = inSlot ? .22 + .55 * clamp((v.y - (footY - .001)) / (SINK + .001)) ** 2 : 1;
      col[i * 3] = col[i * 3 + 1] = col[i * 3 + 2] = k;
    }
    mid.setAttribute('color', new THREE.BufferAttribute(col, 3));
  }
  const midMats = [endMat.clone(), standMat.clone()]; midMats.forEach(m => { m.vertexColors = true; });
  const stands = [new THREE.Mesh(mid, midMats), new THREE.Mesh(piece(false, -SW / 2, (SW - SLOT_L) / 2), [endMat, standMat]), new THREE.Mesh(piece(false, SLOT_L / 2, (SW - SLOT_L) / 2), [endMat, standMat])];
  const stand = stands[0];
  // the slot's end walls, in the slot's own shade (lit wood there read as a wedge)
  const wallShape = new THREE.Shape(); wallShape.moveTo(...M(P1)); wallShape.lineTo(...M(P2)); wallShape.lineTo(...M(P3)); wallShape.lineTo(...M(P4)); wallShape.closePath();
  const wallMat = new THREE.MeshStandardMaterial({ color: 0x4a3526, roughness: 1, side: THREE.DoubleSide });
  for (const sx of [-1, 1]) { const w = new THREE.Mesh(new THREE.ShapeGeometry(wallShape), wallMat); w.rotation.y = Math.PI / 2; w.position.x = sx * (SLOT_L / 2 - .0002); stands.push(w); }
  // a felt pad in the slot and a soft contact shadow where the glass meets the wood
  const felt = new THREE.Mesh(new THREE.PlaneGeometry(SLOT_L - .002, (cF - cB) * .9), new THREE.MeshStandardMaterial({ color: 0x2b2522, roughness: 1 }));
  felt.position.set(0, footY - .0004, zFoot - (BACK / 2) * Math.cos(el)); felt.rotation.x = -Math.PI / 2; stands.push(felt);
  const cc = makeCanvas(256, 64), cgx = cc.getContext('2d'), cgr = cgx.createLinearGradient(0, 0, 0, 64);
  cgr.addColorStop(0, 'rgba(255,255,255,1)'); cgr.addColorStop(1, 'rgba(255,255,255,0)'); cgx.fillStyle = cgr; cgx.fillRect(8, 0, 240, 64);
  const contact = new THREE.Mesh(new THREE.PlaneGeometry(SLOT_L + .006, .007), new THREE.MeshBasicMaterial({ color: 0x3a2414, alphaMap: canvasTexture(cc, { srgb: false }), transparent: true, opacity: .5, depthWrite: false, polygonOffset: true, polygonOffsetFactor: -2 }));
  contact.rotation.x = -Math.PI / 2; contact.position.set(0, lipY + .0002, P1[0] + .0035); stands.push(contact);
  const group = new THREE.Group(); group.add(...stands, tilt); group.rotation.y = HW.az; scene.add(group);
  group.traverse(o => { if (o.isMesh) { o.castShadow = !o.userData.screen && o !== contact && o !== felt; o.receiveShadow = true; } });
  model.traverse(o => { if (o.isMesh) o.receiveShadow = false; });

  /* ---------- light, paper, lens */
  scene.updateMatrixWorld(true);
  const root = new THREE.Group(); scene.add(root); root.attach(group);
  cardLights(scene, env, new THREE.Box3().setFromObject(group), { radius: 3 });
  const { foot } = bakeGround(renderer, scene, root, { keyK: .46, aoK: .34 });
  // frame by the real silhouette (screen corners and the stand), the view never turns: the camera trucks
  const pts = [];
  for (const [x, y] of [[-1, -1], [1, -1], [-1, 1], [1, 1]]) pts.push(new THREE.Vector3(x * .0358, 0, y * .0742).applyMatrix4(tilt.matrixWorld));
  pts.push(...silhouettePoints(stand, 400));
  const rig = cardCamera(pts, { shadow: foot, mode: 'truck', HF: .7, HFn: .76, XC: -.08 });   // the screen fills ~70 % of the image height, so its type stays ≥ 11 px

  /* ---------- UI state */
  await loadFonts();
  const st = { ring: REDUCED ? .86 : 0, kwh: 18.4, saved: '¥20,900' };
  let drawn = '', lastTick = 0, revealAt = -1;
  const redraw = () => { const k = `${Math.round(st.ring * 100)}|${st.kwh.toFixed(1)}`; if (k === drawn) return; drawn = k; drawUI(g, st); uiTex.needsUpdate = true; };
  drawUI(g, { ...st, ring: .86 }); uiTex.needsUpdate = true;

  return {
    scene, camera: rig.camera, tone: 'aces', exposure: 1,
    update(dt, t, s) {
      rig.update(dt, t, s);
      if (revealAt < 0) revealAt = s.age;
      if (!REDUCED) st.ring = .86 * E.outCubic(clamp((s.age - revealAt - .25) / 1.5));
      if (t - lastTick > 2.4) { lastTick = t; if (!REDUCED && st.ring > .85) st.kwh = Math.min(18.9, st.kwh + .1); }
      redraw();
    },
  };
}
