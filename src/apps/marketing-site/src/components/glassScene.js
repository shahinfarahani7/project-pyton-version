import {
  ACESFilmicToneMapping,
  BoxGeometry,
  CanvasTexture,
  CatmullRomCurve3,
  Color,
  CylinderGeometry,
  ExtrudeGeometry,
  Group,
  InstancedMesh,
  Mesh,
  MeshBasicMaterial,
  MeshPhysicalMaterial,
  Object3D,
  Path,
  PerspectiveCamera,
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

function glass(options) {
  return new MeshPhysicalMaterial({
    transmission: 1,
    thickness: 1.2,
    ior: 1.45,
    roughness: 0.12,
    metalness: 0,
    iridescence: 0.6,
    iridescenceIOR: 1.3,
    iridescenceThicknessRange: [120, 640],
    clearcoat: 1,
    clearcoatRoughness: 0.08,
    envMapIntensity: 1,
    ...options,
  });
}

function metal(color, roughness = 0.22) {
  return new MeshPhysicalMaterial({
    color: new Color(color),
    metalness: 1,
    roughness,
    clearcoat: 0.4,
    clearcoatRoughness: 0.2,
    envMapIntensity: 1.2,
  });
}

function glow(radius, color) {
  return new Mesh(new SphereGeometry(radius, 32, 16), new MeshBasicMaterial({ color: new Color(color) }));
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

function roundedRectPath(width, height, radius) {
  const shape = roundedRect(width, height, radius);
  const path = new Path();
  path.curves = shape.curves;
  return path;
}

function wallpaperTexture() {
  const canvas = document.createElement('canvas');
  canvas.width = 256;
  canvas.height = 512;
  const ctx = canvas.getContext('2d');
  ctx.fillStyle = '#05060c';
  ctx.fillRect(0, 0, 256, 512);
  const bloomA = ctx.createRadialGradient(70, 150, 10, 70, 150, 260);
  bloomA.addColorStop(0, 'rgba(90, 140, 255, 0.95)');
  bloomA.addColorStop(0.45, 'rgba(60, 70, 200, 0.45)');
  bloomA.addColorStop(1, 'rgba(10, 10, 30, 0)');
  ctx.fillStyle = bloomA;
  ctx.fillRect(0, 0, 256, 512);
  const bloomB = ctx.createRadialGradient(200, 400, 10, 200, 400, 240);
  bloomB.addColorStop(0, 'rgba(200, 120, 255, 0.85)');
  bloomB.addColorStop(0.5, 'rgba(110, 60, 190, 0.35)');
  bloomB.addColorStop(1, 'rgba(10, 10, 30, 0)');
  ctx.fillStyle = bloomB;
  ctx.fillRect(0, 0, 256, 512);
  const texture = new CanvasTexture(canvas);
  texture.colorSpace = SRGBColorSpace;
  return texture;
}

function createPhone(textures) {
  const group = new Group();
  const width = 0.98;
  const height = 2.02;
  const depth = 0.1;

  const frameShape = roundedRect(width, height, 0.17);
  frameShape.holes.push(roundedRectPath(width - 0.06, height - 0.06, 0.145));
  const frame = new Mesh(
    new ExtrudeGeometry(frameShape, {
      depth,
      bevelEnabled: true,
      bevelThickness: 0.02,
      bevelSize: 0.015,
      bevelSegments: 6,
      curveSegments: 32,
    }),
    metal('#a7adba', 0.32),
  );
  frame.position.z = -depth / 2;

  const back = new Mesh(
    new ExtrudeGeometry(roundedRect(width - 0.05, height - 0.05, 0.15), {
      depth: 0.02,
      bevelEnabled: false,
      curveSegments: 32,
    }),
    glass({
      thickness: 0.4,
      roughness: 0.34,
      color: new Color('#d9d2f2'),
      attenuationColor: new Color('#8f86b8'),
      attenuationDistance: 1.2,
      iridescence: 0.4,
    }),
  );
  back.position.z = -depth / 2 - 0.005;

  const wallpaper = wallpaperTexture();
  textures.push(wallpaper);
  const screen = new Mesh(
    new ShapeGeometry(roundedRect(width - 0.08, height - 0.08, 0.14), 32),
    new MeshPhysicalMaterial({
      color: new Color('#05060a'),
      emissive: new Color('#ffffff'),
      emissiveMap: wallpaper,
      emissiveIntensity: 0.9,
      roughness: 0.05,
      metalness: 0,
      clearcoat: 1,
      clearcoatRoughness: 0.03,
      envMapIntensity: 1.1,
    }),
  );
  const uv = screen.geometry.attributes.uv;
  const pos = screen.geometry.attributes.position;
  for (let i = 0; i < uv.count; i += 1) {
    uv.setXY(i, pos.getX(i) / (width - 0.08) + 0.5, pos.getY(i) / (height - 0.08) + 0.5);
  }
  screen.position.z = depth / 2 + 0.012;

  const island = new Mesh(
    new RoundedBoxGeometry(0.26, 0.07, 0.01, 4, 0.035),
    new MeshPhysicalMaterial({ color: new Color('#000000'), roughness: 0.2, clearcoat: 1 }),
  );
  island.position.set(0, height / 2 - 0.12, depth / 2 + 0.02);

  const cameraIsland = new Group();
  const plate = new Mesh(
    new RoundedBoxGeometry(0.42, 0.42, 0.04, 4, 0.08),
    glass({ thickness: 0.2, roughness: 0.2, color: new Color('#e2dcf5') }),
  );
  cameraIsland.add(plate);
  const lensRing = metal('#c9ced8', 0.18);
  const lensGlass = new MeshPhysicalMaterial({
    color: new Color('#0a0c14'),
    roughness: 0.02,
    clearcoat: 1,
    iridescence: 1,
    iridescenceThicknessRange: [200, 600],
    envMapIntensity: 1.6,
  });
  [[-0.09, 0.09], [-0.09, -0.09], [0.1, 0]].forEach(([x, y]) => {
    const ring = new Mesh(new CylinderGeometry(0.075, 0.075, 0.05, 40), lensRing);
    ring.rotation.x = Math.PI / 2;
    ring.position.set(x, y, -0.03);
    const lens = new Mesh(new CylinderGeometry(0.055, 0.055, 0.052, 40), lensGlass);
    lens.rotation.x = Math.PI / 2;
    lens.position.set(x, y, -0.031);
    cameraIsland.add(ring, lens);
  });
  cameraIsland.position.set(-width / 2 + 0.29, height / 2 - 0.29, -depth / 2 - 0.03);

  const buttonMaterial = metal('#a7adba', 0.3);
  [[0.42, 0.24], [0.12, 0.16]].forEach(([y, length]) => {
    const button = new Mesh(new RoundedBoxGeometry(0.03, length, 0.05, 3, 0.012), buttonMaterial);
    button.position.set(width / 2 + 0.018, y, 0);
    group.add(button);
  });

  group.add(back, frame, screen, island, cameraIsland);
  group.scale.setScalar(1.12);
  return { group };
}

function createChip() {
  const group = new Group();

  const substrate = new Mesh(
    new RoundedBoxGeometry(1.5, 1.5, 0.1, 4, 0.03),
    new MeshPhysicalMaterial({
      color: new Color('#15171c'),
      roughness: 0.45,
      metalness: 0.2,
      clearcoat: 0.8,
      clearcoatRoughness: 0.25,
    }),
  );

  const spreader = new Mesh(
    new RoundedBoxGeometry(1.02, 1.02, 0.2, 6, 0.05),
    glass({
      thickness: 0.6,
      roughness: 0.1,
      color: new Color('#cfdcff'),
      attenuationColor: new Color('#6f84c8'),
      attenuationDistance: 1.4,
    }),
  );
  spreader.position.z = 0.14;

  const die = new Mesh(new BoxGeometry(0.46, 0.46, 0.04), new MeshBasicMaterial({ color: new Color('#e9efff') }));
  die.position.z = 0.1;
  const dieHalo = new Mesh(new BoxGeometry(0.62, 0.62, 0.02), new MeshBasicMaterial({ color: new Color('#5f7fe0') }));
  dieHalo.position.z = 0.09;

  const pinCount = 11;
  const pins = new InstancedMesh(new BoxGeometry(0.045, 0.16, 0.025), metal('#d8b46a', 0.24), pinCount * 4);
  const dummy = new Object3D();
  let index = 0;
  for (let side = 0; side < 4; side += 1) {
    for (let i = 0; i < pinCount; i += 1) {
      const offset = -0.6 + (1.2 / (pinCount - 1)) * i;
      dummy.position.set(offset, 0.82, 0);
      dummy.rotation.set(0, 0, 0);
      dummy.position.applyAxisAngle(new Vector3(0, 0, 1), (side * Math.PI) / 2);
      dummy.rotation.z = (side * Math.PI) / 2;
      dummy.updateMatrix();
      pins.setMatrixAt(index, dummy.matrix);
      index += 1;
    }
  }
  pins.instanceMatrix.needsUpdate = true;

  const padMaterial = metal('#d8b46a', 0.3);
  [[-0.58, -0.58], [0.58, -0.58], [-0.58, 0.58], [0.58, 0.58]].forEach(([x, y]) => {
    const pad = new Mesh(new CylinderGeometry(0.035, 0.035, 0.012, 24), padMaterial);
    pad.rotation.x = Math.PI / 2;
    pad.position.set(x, y, 0.056);
    group.add(pad);
  });

  group.add(substrate, pins, dieHalo, die, spreader);
  group.scale.setScalar(1.1);
  return { group };
}

function createPadlock() {
  const group = new Group();

  const bodyDepth = 0.42;
  const body = new Mesh(
    new ExtrudeGeometry(roundedRect(1.25, 1.0, 0.2), {
      depth: bodyDepth,
      bevelEnabled: true,
      bevelThickness: 0.08,
      bevelSize: 0.07,
      bevelSegments: 10,
      curveSegments: 40,
    }),
    glass({
      thickness: 1.4,
      roughness: 0.22,
      color: new Color('#e7e2f6'),
      attenuationColor: new Color('#9d92c4'),
      attenuationDistance: 2.2,
    }),
  );
  body.position.set(0, -0.3, -bodyDepth / 2);

  const core = glow(0.2, '#f4efff');
  core.position.set(0, -0.32, 0);

  const radius = 0.36;
  const points = [new Vector3(-radius, -0.05, 0), new Vector3(-radius, 0.3, 0)];
  for (let i = 0; i <= 24; i += 1) {
    const angle = Math.PI - (Math.PI * i) / 24;
    points.push(new Vector3(Math.cos(angle) * radius, 0.3 + Math.sin(angle) * radius, 0));
  }
  points.push(new Vector3(radius, 0.3, 0), new Vector3(radius, -0.05, 0));
  const shackle = new Mesh(
    new TubeGeometry(new CatmullRomCurve3(points, false, 'centripetal'), 160, 0.085, 24, false),
    metal('#dfe3ea', 0.12),
  );

  const keyMaterial = metal('#3a3f4c', 0.35);
  const keyFront = bodyDepth / 2 + 0.085;
  const keyRing = new Mesh(new TorusGeometry(0.1, 0.022, 16, 48), metal('#c9ced8', 0.18));
  keyRing.position.set(0, -0.22, keyFront);
  const keyHole = new Mesh(new CylinderGeometry(0.07, 0.07, 0.02, 32), keyMaterial);
  keyHole.rotation.x = Math.PI / 2;
  keyHole.position.set(0, -0.22, keyFront);
  const keySlot = new Mesh(new BoxGeometry(0.05, 0.18, 0.02), keyMaterial);
  keySlot.position.set(0, -0.35, keyFront);

  group.add(core, shackle, body, keyRing, keyHole, keySlot);
  group.scale.setScalar(1.12);
  return { group };
}

export function createGlassScene(canvas, { reducedMotion = false } = {}) {
  const renderer = new WebGLRenderer({ canvas, antialias: true, alpha: true, powerPreference: 'low-power' });
  renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 1.75));
  renderer.outputColorSpace = SRGBColorSpace;
  renderer.toneMapping = ACESFilmicToneMapping;
  renderer.toneMappingExposure = 1.05;
  renderer.setClearColor(0x000000, 0);

  const scene = new Scene();
  const pmrem = new PMREMGenerator(renderer);
  const room = new RoomEnvironment();
  const envTexture = pmrem.fromScene(room, 0.04).texture;
  scene.environment = envTexture;

  const camera = new PerspectiveCamera(38, 1, 0.1, 50);
  camera.position.set(0, 0, 9);

  const blue = new PointLight(0x3d7bff, 60, 14);
  blue.position.set(-3.5, 1.5, 3);
  const pink = new PointLight(0xff6fd0, 40, 14);
  pink.position.set(3.5, -0.5, 2.5);
  const white = new PointLight(0xffffff, 25, 12);
  white.position.set(0.5, 3.5, 4);
  scene.add(blue, pink, white);

  const rig = new Group();
  scene.add(rig);

  const textures = [];

  const padlock = createPadlock();
  padlock.group.rotation.set(0.18, -0.42, 0.14);

  const phone = createPhone(textures);
  phone.group.rotation.set(0.08, -0.5, -0.16);

  const chip = createChip();
  chip.group.rotation.set(-0.7, 0.32, 0.38);

  rig.add(padlock.group, phone.group, chip.group);

  const items = [
    { node: padlock.group, sway: [0.08, 0.3, 0.05], phase: 0 },
    { node: phone.group, sway: [0.06, 0.42, 0.04], phase: 2.1 },
    { node: chip.group, sway: [0.1, 0.18, 0.0], spinZ: 0.1, phase: 4.2 },
  ];
  items.forEach((item) => { item.baseRot = item.node.rotation.clone(); });

  const pointer = { x: 0, y: 0, tx: 0, ty: 0 };
  let width = 0;
  let height = 0;
  let frame = 0;
  let running = false;
  let last = 0;
  let elapsed = 0;

  function layout() {
    const aspect = width / Math.max(height, 1);
    const spread = Math.min(1, aspect / 0.85);
    padlock.group.position.set(-0.8 * spread, 2.25, 0);
    phone.group.position.set(1.0 * spread, 0.05, 0.2);
    chip.group.position.set(-0.6 * spread, -2.3, 0);
    items.forEach((item) => { item.baseY = item.node.position.y; });
    camera.position.z = aspect < 0.75 ? 12 : 10.5;
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

  function tick(now) {
    if (!running) return;
    const dt = Math.min(0.05, (now - (last || now)) / 1000);
    last = now;
    elapsed += dt;

    items.forEach((item) => {
      const wave = Math.sin(elapsed * 0.5 + item.phase);
      const wave2 = Math.cos(elapsed * 0.4 + item.phase);
      item.node.rotation.x = item.baseRot.x + item.sway[0] * wave;
      item.node.rotation.y = item.baseRot.y + item.sway[1] * wave2;
      item.node.rotation.z = item.baseRot.z + item.sway[2] * wave + (item.spinZ || 0) * Math.sin(elapsed * 0.3);
      item.node.position.y = item.baseY + Math.sin(elapsed * 0.6 + item.phase) * 0.12;
    });

    pointer.x += (pointer.tx - pointer.x) * 0.06;
    pointer.y += (pointer.ty - pointer.y) * 0.06;
    rig.rotation.y = pointer.x * 0.35;
    rig.rotation.x = pointer.y * 0.22;

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
      rig.rotation.y = x * 0.2;
      rig.rotation.x = y * 0.12;
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
    disposeTree(scene);
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
