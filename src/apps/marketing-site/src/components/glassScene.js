import {
  ACESFilmicToneMapping,
  BoxGeometry,
  CanvasTexture,
  CatmullRomCurve3,
  CircleGeometry,
  Color,
  CylinderGeometry,
  DirectionalLight,
  ExtrudeGeometry,
  Group,
  InstancedMesh,
  Mesh,
  MeshBasicMaterial,
  MeshPhysicalMaterial,
  MeshStandardMaterial,
  Object3D,
  PerspectiveCamera,
  PlaneGeometry,
  PMREMGenerator,
  PointLight,
  Scene,
  Shape,
  ShapeGeometry,
  SphereGeometry,
  SRGBColorSpace,
  TorusGeometry,
  TubeGeometry,
  Vector3,
  WebGLRenderer,
} from 'three';
import { RoomEnvironment } from 'three/examples/jsm/environments/RoomEnvironment.js';
import { RoundedBoxGeometry } from 'three/examples/jsm/geometries/RoundedBoxGeometry.js';

const TEAL = '#19c7b4';
const STEEL = '#a6c0cb';
const UI_FONT = '"Geist Sans", "Geist", system-ui, sans-serif';
const MASCOT_SRC = '/mascot/working.webp';

function metal(color, roughness = 0.3) {
  return new MeshPhysicalMaterial({
    color: new Color(color),
    metalness: 1,
    roughness,
    envMapIntensity: 1,
  });
}

function roundedRect(width, height, radius) {
  const x = -width / 2;
  const y = -height / 2;
  const shape = new Shape();
  shape.moveTo(x + radius, y);
  shape.lineTo(x + width - radius, y);
  shape.quadraticCurveTo(x + width, y, x + width, y + radius);
  shape.lineTo(x + width, y + height - radius);
  shape.quadraticCurveTo(x + width, y + height, x + width - radius, y + height);
  shape.lineTo(x + radius, y + height);
  shape.quadraticCurveTo(x, y + height, x, y + height - radius);
  shape.lineTo(x, y + radius);
  shape.quadraticCurveTo(x, y, x + radius, y);
  return shape;
}

function fitUv(geometry, width, height) {
  const uv = geometry.attributes.uv;
  const pos = geometry.attributes.position;
  for (let i = 0; i < uv.count; i += 1) {
    uv.setXY(i, pos.getX(i) / width + 0.5, pos.getY(i) / height + 0.5);
  }
}

function roundRectPath(ctx, x, y, w, h, r) {
  ctx.beginPath();
  ctx.roundRect(x, y, w, h, r);
}

function checkMark(ctx, x, y, size) {
  ctx.save();
  ctx.fillStyle = 'rgba(25, 199, 180, 0.16)';
  ctx.beginPath();
  ctx.arc(x, y, size, 0, Math.PI * 2);
  ctx.fill();
  ctx.strokeStyle = TEAL;
  ctx.lineWidth = 3.5;
  ctx.lineCap = 'round';
  ctx.lineJoin = 'round';
  ctx.beginPath();
  ctx.moveTo(x - size * 0.42, y + size * 0.02);
  ctx.lineTo(x - size * 0.1, y + size * 0.34);
  ctx.lineTo(x + size * 0.46, y - size * 0.3);
  ctx.stroke();
  ctx.restore();
}

/** Android worker app screen: status bar, mascot, running task, verification checks. */
function createScreenUi() {
  const canvas = document.createElement('canvas');
  canvas.width = 512;
  canvas.height = 1112;
  const ctx = canvas.getContext('2d');
  const texture = new CanvasTexture(canvas);
  texture.colorSpace = SRGBColorSpace;
  texture.anisotropy = 4;

  const mascot = new Image();
  let mascotReady = false;

  function draw(progress) {
    const W = canvas.width;
    const H = canvas.height;
    const bg = ctx.createLinearGradient(0, 0, 0, H);
    bg.addColorStop(0, '#11161a');
    bg.addColorStop(0.45, '#0b0d10');
    bg.addColorStop(1, '#090a0c');
    ctx.fillStyle = bg;
    ctx.fillRect(0, 0, W, H);

    // Status bar
    ctx.fillStyle = '#e9ecef';
    ctx.font = `500 24px ${UI_FONT}`;
    ctx.textBaseline = 'middle';
    ctx.fillText('12:30', 34, 40);
    const right = W - 34;
    ctx.fillRect(right - 34, 30, 30, 18);
    ctx.fillRect(right - 3, 35, 4, 8);
    ctx.fillStyle = '#0b0d10';
    ctx.fillRect(right - 31, 33, 8, 12);
    ctx.fillStyle = '#e9ecef';
    [6, 10, 14, 18].forEach((h, i) => ctx.fillRect(right - 82 + i * 7, 48 - h, 5, h));
    ctx.strokeStyle = '#e9ecef';
    ctx.lineWidth = 3;
    [8, 14].forEach((r) => {
      ctx.beginPath();
      ctx.arc(right - 108, 50, r, Math.PI * 1.25, Math.PI * 1.75);
      ctx.stroke();
    });

    // App bar
    ctx.fillStyle = '#ffffff';
    ctx.font = `600 30px ${UI_FONT}`;
    ctx.fillText('FibonAI Worker', 34, 118);
    ctx.fillStyle = '#9ea4ad';
    ctx.font = `400 19px ${UI_FONT}`;
    ctx.fillText('Opted in · Wi-Fi only · Battery above 40%', 34, 152);

    // Mascot
    const glow = ctx.createRadialGradient(W / 2, 330, 10, W / 2, 330, 230);
    glow.addColorStop(0, 'rgba(25, 199, 180, 0.16)');
    glow.addColorStop(1, 'rgba(25, 199, 180, 0)');
    ctx.fillStyle = glow;
    ctx.fillRect(0, 180, W, 300);
    if (mascotReady) {
      const w = 440;
      const h = (w * mascot.height) / mascot.width;
      ctx.drawImage(mascot, (W - w) / 2, 196, w, h);
    }

    // Status chip
    roundRectPath(ctx, 34, 480, 210, 44, 22);
    ctx.fillStyle = 'rgba(25, 199, 180, 0.12)';
    ctx.fill();
    ctx.strokeStyle = 'rgba(25, 199, 180, 0.55)';
    ctx.lineWidth = 1.5;
    ctx.stroke();
    ctx.fillStyle = TEAL;
    ctx.beginPath();
    ctx.arc(58, 502, 6, 0, Math.PI * 2);
    ctx.fill();
    ctx.fillStyle = '#d8f5f1';
    ctx.font = `500 19px ${UI_FONT}`;
    ctx.fillText('Running a task', 74, 503);

    // Task card
    roundRectPath(ctx, 26, 548, W - 52, 196, 26);
    ctx.fillStyle = '#15181c';
    ctx.fill();
    ctx.strokeStyle = 'rgba(255, 255, 255, 0.08)';
    ctx.stroke();
    ctx.fillStyle = '#ffffff';
    ctx.font = `600 23px ${UI_FONT}`;
    ctx.fillText('document.ocr', 54, 592);
    ctx.fillStyle = '#9ea4ad';
    ctx.font = `400 18px ${UI_FONT}`;
    ctx.fillText('invoice-0042.pdf · EU region', 54, 624);
    roundRectPath(ctx, 54, 660, W - 108, 12, 6);
    ctx.fillStyle = '#23272d';
    ctx.fill();
    const bar = ctx.createLinearGradient(54, 0, W - 54, 0);
    bar.addColorStop(0, STEEL);
    bar.addColorStop(1, TEAL);
    roundRectPath(ctx, 54, 660, Math.max(12, (W - 108) * progress), 12, 6);
    ctx.fillStyle = bar;
    ctx.fill();
    ctx.fillStyle = '#9ea4ad';
    ctx.font = `400 17px ${UI_FONT}`;
    ctx.fillText(`Chunk ${Math.min(4, 1 + Math.floor(progress * 4))} of 4`, 54, 704);
    ctx.textAlign = 'right';
    ctx.fillText(`${Math.round(progress * 100)}%`, W - 54, 704);
    ctx.textAlign = 'left';

    // Verification card
    roundRectPath(ctx, 26, 768, W - 52, 236, 26);
    ctx.fillStyle = '#15181c';
    ctx.fill();
    ctx.strokeStyle = 'rgba(255, 255, 255, 0.08)';
    ctx.stroke();
    ctx.fillStyle = '#9ea4ad';
    ctx.font = `500 16px ${UI_FONT}`;
    ctx.fillText('SECURITY CHECKS', 54, 806);
    const checks = ['Model signature verified', 'SHA-256 matches pinned hash', 'Customer identity hidden'];
    checks.forEach((label, i) => {
      const y = 850 + i * 52;
      checkMark(ctx, 70, y, 16);
      ctx.fillStyle = '#e9ecef';
      ctx.font = `400 19px ${UI_FONT}`;
      ctx.fillText(label, 100, y + 1);
    });

    // Gesture bar
    roundRectPath(ctx, W / 2 - 70, H - 30, 140, 7, 4);
    ctx.fillStyle = 'rgba(233, 236, 239, 0.75)';
    ctx.fill();

    texture.needsUpdate = true;
  }

  return { texture, draw, mascot, setMascotReady: () => { mascotReady = true; } };
}

function chipLabelTexture() {
  const canvas = document.createElement('canvas');
  canvas.width = 512;
  canvas.height = 512;
  const ctx = canvas.getContext('2d');
  ctx.clearRect(0, 0, 512, 512);
  ctx.fillStyle = 'rgba(70, 76, 86, 0.9)';
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  ctx.font = `600 64px ${UI_FONT}`;
  ctx.fillText('FIBONAI', 256, 220);
  ctx.font = `500 34px ${UI_FONT}`;
  ctx.fillText('EDGE NPU', 256, 284);
  ctx.font = `400 26px ${UI_FONT}`;
  ctx.fillText('EM-26 · SIGNED', 256, 336);
  ctx.beginPath();
  ctx.arc(70, 70, 16, 0, Math.PI * 2);
  ctx.fill();
  const texture = new CanvasTexture(canvas);
  texture.colorSpace = SRGBColorSpace;
  return texture;
}

/** Pixel-style Android phone: flat aluminium rail, punch-hole camera, edge-to-edge camera bar. */
function createPhone(screenUi) {
  const group = new Group();
  const width = 0.96;
  const height = 2.06;
  const depth = 0.085;
  const radius = 0.12;

  const body = new Mesh(
    new ExtrudeGeometry(roundedRect(width, height, radius), {
      depth,
      bevelEnabled: true,
      bevelThickness: 0.012,
      bevelSize: 0.012,
      bevelSegments: 4,
      curveSegments: 24,
    }),
    metal('#8f959e', 0.38),
  );
  body.position.z = -depth / 2;

  const back = new Mesh(
    new ShapeGeometry(roundedRect(width - 0.02, height - 0.02, radius - 0.01), 24),
    new MeshPhysicalMaterial({ color: new Color('#1b1e23'), roughness: 0.62, clearcoat: 0.4, clearcoatRoughness: 0.5 }),
  );
  back.rotation.y = Math.PI;
  back.position.z = -depth / 2 - 0.013;

  const glass = new Mesh(
    new ShapeGeometry(roundedRect(width - 0.02, height - 0.02, radius - 0.01), 24),
    new MeshPhysicalMaterial({ color: new Color('#030405'), roughness: 0.04, clearcoat: 1, clearcoatRoughness: 0.02 }),
  );
  glass.position.z = depth / 2 + 0.013;

  const screenW = width - 0.075;
  const screenH = height - 0.075;
  const screenGeometry = new ShapeGeometry(roundedRect(screenW, screenH, radius - 0.035), 24);
  fitUv(screenGeometry, screenW, screenH);
  const screen = new Mesh(
    screenGeometry,
    new MeshPhysicalMaterial({
      color: new Color('#000000'),
      emissive: new Color('#ffffff'),
      emissiveMap: screenUi.texture,
      emissiveIntensity: 1,
      roughness: 0.06,
      clearcoat: 1,
      clearcoatRoughness: 0.02,
    }),
  );
  screen.position.z = depth / 2 + 0.015;

  const punchHole = new Mesh(new CircleGeometry(0.026, 32), new MeshBasicMaterial({ color: new Color('#000000') }));
  punchHole.position.set(0, height / 2 - 0.085, depth / 2 + 0.017);
  const lensGlint = new Mesh(new CircleGeometry(0.011, 24), metal('#1c2a3a', 0.08));
  lensGlint.position.set(0.004, height / 2 - 0.082, depth / 2 + 0.018);

  const visor = new Mesh(
    new RoundedBoxGeometry(width - 0.01, 0.2, 0.055, 4, 0.025),
    new MeshPhysicalMaterial({ color: new Color('#0c0d10'), roughness: 0.18, clearcoat: 1, clearcoatRoughness: 0.05 }),
  );
  visor.position.set(0, height / 2 - 0.36, -depth / 2 - 0.035);
  const lensMaterial = new MeshPhysicalMaterial({ color: new Color('#05070a'), roughness: 0.02, clearcoat: 1, envMapIntensity: 1.6 });
  const ringMaterial = metal('#6d737c', 0.25);
  [-0.26, -0.1].forEach((x) => {
    const ring = new Mesh(new CylinderGeometry(0.062, 0.062, 0.02, 40), ringMaterial);
    ring.rotation.x = Math.PI / 2;
    ring.position.set(x, height / 2 - 0.36, -depth / 2 - 0.065);
    const lens = new Mesh(new CylinderGeometry(0.046, 0.046, 0.022, 40), lensMaterial);
    lens.rotation.x = Math.PI / 2;
    lens.position.set(x, height / 2 - 0.36, -depth / 2 - 0.066);
    group.add(ring, lens);
  });

  const buttonMaterial = metal('#8f959e', 0.34);
  [[0.52, 0.12], [0.24, 0.26]].forEach(([y, length]) => {
    const button = new Mesh(new RoundedBoxGeometry(0.022, length, 0.04, 3, 0.009), buttonMaterial);
    button.position.set(width / 2 + 0.014, y, 0);
    group.add(button);
  });

  group.add(body, back, glass, screen, punchHole, lensGlint, visor);
  group.scale.setScalar(1.4);
  return { group, edge: new Vector3(-width / 2, 0.15, 0) };
}

/** QFP package on a dark substrate: brushed spreader with laser-etched label, gold leads, SMD parts. */
function createChip(textures) {
  const group = new Group();

  const substrate = new Mesh(
    new RoundedBoxGeometry(1.5, 1.5, 0.06, 3, 0.02),
    new MeshPhysicalMaterial({ color: new Color('#13221b'), roughness: 0.62, clearcoat: 0.5, clearcoatRoughness: 0.4 }),
  );

  const spreader = new Mesh(new RoundedBoxGeometry(0.98, 0.98, 0.09, 4, 0.03), metal('#b7bcc4', 0.32));
  spreader.position.z = 0.07;

  const label = chipLabelTexture();
  textures.push(label);
  const etch = new Mesh(
    new PlaneGeometry(0.9, 0.9),
    new MeshStandardMaterial({ map: label, transparent: true, metalness: 0.4, roughness: 0.5 }),
  );
  etch.position.z = 0.116;

  const pinCount = 12;
  const pins = new InstancedMesh(new BoxGeometry(0.04, 0.14, 0.018), metal('#d3b169', 0.26), pinCount * 4);
  const dummy = new Object3D();
  let index = 0;
  for (let side = 0; side < 4; side += 1) {
    for (let i = 0; i < pinCount; i += 1) {
      const offset = -0.6 + (1.2 / (pinCount - 1)) * i;
      dummy.position.set(offset, 0.8, 0);
      dummy.rotation.set(0, 0, 0);
      dummy.position.applyAxisAngle(new Vector3(0, 0, 1), (side * Math.PI) / 2);
      dummy.rotation.z = (side * Math.PI) / 2;
      dummy.updateMatrix();
      pins.setMatrixAt(index, dummy.matrix);
      index += 1;
    }
  }
  pins.instanceMatrix.needsUpdate = true;

  const parts = [[-0.62, -0.3], [-0.62, 0.05], [0.62, 0.3], [0.62, -0.1], [-0.2, 0.62], [0.25, -0.62]];
  const smd = new InstancedMesh(new BoxGeometry(0.07, 0.035, 0.03), new MeshPhysicalMaterial({ color: new Color('#8b7154'), roughness: 0.5 }), parts.length);
  parts.forEach(([x, y], i) => {
    dummy.position.set(x, y, 0.045);
    dummy.rotation.set(0, 0, Math.abs(x) > 0.5 ? Math.PI / 2 : 0);
    dummy.updateMatrix();
    smd.setMatrixAt(i, dummy.matrix);
  });
  smd.instanceMatrix.needsUpdate = true;

  group.add(substrate, pins, smd, spreader, etch);
  group.scale.setScalar(0.92);
  return { group, port: new Vector3(0.45, 0.62, 0.12) };
}

/** Compact closed padlock with a verification seal ring around it. */
function createLock() {
  const group = new Group();

  const body = new Mesh(new RoundedBoxGeometry(0.4, 0.32, 0.15, 5, 0.05), metal('#c2c7ce', 0.26));
  body.position.y = -0.08;

  const radius = 0.12;
  const points = [new Vector3(-radius, -0.02, 0), new Vector3(-radius, 0.12, 0)];
  for (let i = 0; i <= 20; i += 1) {
    const angle = Math.PI - (Math.PI * i) / 20;
    points.push(new Vector3(Math.cos(angle) * radius, 0.12 + Math.sin(angle) * radius, 0));
  }
  points.push(new Vector3(radius, 0.12, 0), new Vector3(radius, -0.02, 0));
  const shackle = new Mesh(
    new TubeGeometry(new CatmullRomCurve3(points, false, 'centripetal'), 96, 0.032, 16, false),
    metal('#e4e7ec', 0.1),
  );

  const keyMaterial = new MeshPhysicalMaterial({ color: new Color('#16181c'), roughness: 0.4, metalness: 0.6 });
  const keyHole = new Mesh(new CylinderGeometry(0.032, 0.032, 0.01, 24), keyMaterial);
  keyHole.rotation.x = Math.PI / 2;
  keyHole.position.set(0, -0.05, 0.078);
  const keySlot = new Mesh(new BoxGeometry(0.022, 0.07, 0.01), keyMaterial);
  keySlot.position.set(0, -0.1, 0.078);

  const seal = new Group();
  const sealMaterial = new MeshBasicMaterial({ color: new Color(TEAL), transparent: true, opacity: 0.5 });
  seal.add(new Mesh(new TorusGeometry(0.38, 0.004, 8, 96), sealMaterial));
  const tickCount = 36;
  const ticks = new InstancedMesh(new BoxGeometry(0.006, 0.035, 0.004), sealMaterial, tickCount);
  const dummy = new Object3D();
  for (let i = 0; i < tickCount; i += 1) {
    const angle = (i / tickCount) * Math.PI * 2;
    dummy.position.set(Math.cos(angle) * 0.42, Math.sin(angle) * 0.42, 0);
    dummy.rotation.set(0, 0, angle - Math.PI / 2);
    dummy.scale.setScalar(i % 3 === 0 ? 1.6 : 1);
    dummy.updateMatrix();
    ticks.setMatrixAt(i, dummy.matrix);
  }
  ticks.instanceMatrix.needsUpdate = true;
  seal.add(ticks);
  seal.position.y = -0.02;

  group.add(body, shackle, keyHole, keySlot, seal);
  return { group, seal };
}

export function createGlassScene(canvas, { reducedMotion = false } = {}) {
  const renderer = new WebGLRenderer({ canvas, antialias: true, alpha: true, powerPreference: 'low-power' });
  renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 1.75));
  renderer.outputColorSpace = SRGBColorSpace;
  renderer.toneMapping = ACESFilmicToneMapping;
  renderer.toneMappingExposure = 0.95;
  renderer.setClearColor(0x000000, 0);

  const scene = new Scene();
  const pmrem = new PMREMGenerator(renderer);
  const room = new RoomEnvironment();
  const envTexture = pmrem.fromScene(room, 0.04).texture;
  scene.environment = envTexture;
  scene.environmentIntensity = 0.75;

  const camera = new PerspectiveCamera(36, 1, 0.1, 50);
  camera.position.set(0, 0, 11);

  const key = new DirectionalLight(0xffffff, 2.2);
  key.position.set(3, 5, 6);
  const rim = new DirectionalLight(new Color(STEEL), 1.8);
  rim.position.set(-5, 2, -4);
  const sealGlow = new PointLight(new Color(TEAL), 4, 4);
  scene.add(key, rim, sealGlow);

  const rig = new Group();
  scene.add(rig);

  const textures = [];
  const screenUi = createScreenUi();
  textures.push(screenUi.texture);

  const phone = createPhone(screenUi);
  phone.group.rotation.set(0.04, -0.34, -0.06);

  const chip = createChip(textures);
  chip.group.rotation.set(-0.95, 0.22, 0.32);

  const lock = createLock();
  lock.group.rotation.set(0.05, 0.28, 0.02);

  rig.add(phone.group, chip.group, lock.group);

  const channelMaterial = new MeshBasicMaterial({ color: new Color(STEEL), transparent: true, opacity: 0.35 });
  let channel = null;
  let curve = null;
  let lockT = 0.5;
  const rawMaterial = new MeshBasicMaterial({ color: new Color('#e8edf2') });
  const sealedMaterial = new MeshBasicMaterial({ color: new Color(TEAL) });
  const packetGeometry = new SphereGeometry(0.022, 16, 12);
  const packets = Array.from({ length: 6 }, (_, i) => {
    const mesh = new Mesh(packetGeometry, rawMaterial);
    rig.add(mesh);
    return { mesh, offset: i / 6 };
  });

  const items = [
    { node: phone.group, sway: [0.03, 0.12, 0.02], phase: 0 },
    { node: chip.group, sway: [0.04, 0.08, 0.02], phase: 2.1 },
    { node: lock.group, sway: [0.03, 0.18, 0.02], phase: 4.2 },
  ];
  items.forEach((item) => { item.baseRot = item.node.rotation.clone(); });

  const pointer = { x: 0, y: 0, tx: 0, ty: 0 };
  let width = 0;
  let height = 0;
  let frame = 0;
  let running = false;
  let last = 0;
  let elapsed = 0;
  let progress = 0.36;
  let screenClock = 0;

  function placePackets() {
    if (!curve) return;
    packets.forEach((packet) => {
      const t = (packet.offset + elapsed * 0.09) % 1;
      packet.mesh.position.copy(curve.getPointAt(t));
      packet.mesh.material = t > lockT ? sealedMaterial : rawMaterial;
    });
  }

  function buildChannel() {
    phone.group.updateMatrixWorld(true);
    chip.group.updateMatrixWorld(true);
    const start = chip.port.clone().applyMatrix4(chip.group.matrix);
    const end = phone.edge.clone().applyMatrix4(phone.group.matrix);
    const via = lock.group.position.clone();
    const startBend = new Vector3(start.x - 0.25, (start.y + via.y) / 2, start.z + 0.2);
    const endBend = new Vector3((via.x + end.x) / 2, via.y - 0.15, (via.z + end.z) / 2);
    const points = [start, startBend, via, endBend, end];
    curve = new CatmullRomCurve3(points, false, 'centripetal');
    const lengths = curve.getLengths(200);
    const total = lengths[lengths.length - 1];
    const viaLength = new CatmullRomCurve3(points.slice(0, 3), false, 'centripetal').getLength();
    lockT = viaLength / total;
    if (channel) {
      rig.remove(channel);
      channel.geometry.dispose();
    }
    channel = new Mesh(new TubeGeometry(curve, 160, 0.007, 8, false), channelMaterial);
    rig.add(channel);
  }

  function layout() {
    const aspect = width / Math.max(height, 1);
    const spread = Math.min(1, aspect / 0.85);
    phone.group.position.set(0.78 * spread, 0.35, 0);
    chip.group.position.set(-1.1 * spread, -2.2, -0.2);
    lock.group.position.set(-1.05 * spread, 1.15, 0.45);
    sealGlow.position.set(lock.group.position.x, lock.group.position.y, lock.group.position.z + 0.6);
    items.forEach((item) => { item.baseY = item.node.position.y; });
    camera.position.z = aspect < 0.75 ? 12 : 10.8;
    buildChannel();
    placePackets();
  }

  function resize() {
    const rect = canvas.getBoundingClientRect();
    width = Math.max(1, Math.round(rect.width));
    height = Math.max(1, Math.round(rect.height));
    renderer.setSize(width, height, false);
    camera.aspect = width / height;
    camera.updateProjectionMatrix();
    layout();
    if (!running) renderer.render(scene, camera);
  }

  screenUi.draw(progress);
  screenUi.mascot.onload = () => {
    screenUi.setMascotReady();
    screenUi.draw(progress);
    if (!running) renderer.render(scene, camera);
  };
  screenUi.mascot.src = MASCOT_SRC;

  function tick(now) {
    if (!running) return;
    const dt = Math.min(0.05, (now - (last || now)) / 1000);
    last = now;
    elapsed += dt;

    items.forEach((item) => {
      const wave = Math.sin(elapsed * 0.4 + item.phase);
      const wave2 = Math.cos(elapsed * 0.32 + item.phase);
      item.node.rotation.x = item.baseRot.x + item.sway[0] * wave;
      item.node.rotation.y = item.baseRot.y + item.sway[1] * wave2;
      item.node.rotation.z = item.baseRot.z + item.sway[2] * wave;
      item.node.position.y = item.baseY + Math.sin(elapsed * 0.5 + item.phase) * 0.05;
    });
    lock.seal.rotation.z -= dt * 0.25;
    placePackets();

    screenClock += dt;
    if (screenClock > 0.25) {
      screenClock = 0;
      progress = progress >= 1 ? 0.08 : Math.min(1, progress + 0.012);
      screenUi.draw(progress);
    }

    pointer.x += (pointer.tx - pointer.x) * 0.06;
    pointer.y += (pointer.ty - pointer.y) * 0.06;
    rig.rotation.y = pointer.x * 0.25;
    rig.rotation.x = pointer.y * 0.15;

    renderer.render(scene, camera);
    frame = requestAnimationFrame(tick);
  }

  function start() {
    if (running || reducedMotion) return;
    running = true;
    last = 0;
    frame = requestAnimationFrame(tick);
  }

  function stop() {
    running = false;
    cancelAnimationFrame(frame);
  }

  function setPointer(x, y) {
    pointer.tx = x;
    pointer.ty = y;
    if (reducedMotion) {
      rig.rotation.y = x * 0.15;
      rig.rotation.x = y * 0.1;
      renderer.render(scene, camera);
    }
  }

  function disposeTree(root) {
    const materials = new Set();
    root.traverse((object) => {
      if (object.isMesh) {
        object.geometry.dispose();
        materials.add(object.material);
        if (object.isInstancedMesh) object.dispose();
      }
    });
    materials.forEach((material) => material.dispose());
  }

  function dispose() {
    stop();
    screenUi.mascot.onload = null;
    disposeTree(scene);
    rawMaterial.dispose();
    sealedMaterial.dispose();
    textures.forEach((texture) => texture.dispose());
    envTexture.dispose();
    pmrem.dispose();
    disposeTree(room);
    renderer.dispose();
  }

  resize();
  renderer.render(scene, camera);

  return { resize, start, stop, setPointer, dispose };
}
