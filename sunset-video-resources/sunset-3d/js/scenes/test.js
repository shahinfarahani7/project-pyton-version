// Pipeline smoke test: scanned wood + plaster, the sunset HDRI, a sun behind a slab for god rays.
import { THREE, pbrMaterial } from '../core.js';
export async function create({ env }) {
  const scene = new THREE.Scene();
  scene.environment = env.texture; scene.environmentIntensity = .6;
  const camera = new THREE.PerspectiveCamera(30, 1, .1, 200); camera.position.set(0, 1.4, 8); camera.lookAt(0, 1, 0);
  const sky = new THREE.Mesh(new THREE.SphereGeometry(90, 32, 16), new THREE.MeshBasicMaterial({ map: env.equirect, side: THREE.BackSide, depthWrite: false }));
  scene.add(sky);
  const wood = await pbrMaterial('hinoki', { repeat: [1, 1] });
  const plaster = await pbrMaterial('plaster', { repeat: [2, 2], tint: 0xf4efe6 });
  const box = new THREE.Mesh(new THREE.BoxGeometry(2.2, 2.2, 2.2), wood); box.position.set(-1.4, 1.1, 0); box.castShadow = true; scene.add(box);
  const wall = new THREE.Mesh(new THREE.BoxGeometry(1.6, 3, .3), plaster); wall.position.set(1.5, 1.5, -1); wall.castShadow = true; scene.add(wall);
  const floor = new THREE.Mesh(new THREE.PlaneGeometry(40, 40), await pbrMaterial('deck', { repeat: [8, 8] })); floor.rotation.x = -Math.PI / 2; floor.receiveShadow = true; scene.add(floor);
  const sun = new THREE.DirectionalLight(0xffc38a, 3); sun.position.set(-4, 3, -8); sun.castShadow = true; sun.shadow.mapSize.set(2048, 2048); scene.add(sun);
  const sunPos = new THREE.Vector3(-30, 8, -80);
  return { scene, camera, post: { rays: { sun: sunPos, strength: 1.2 }, bloom: { strength: .4 } }, update(dt, t) { box.rotation.y = t * .3; } };
}
