/* Final call to action: the Sunset house at blue hour. Deep indigo sky with the last vermilion band on the western
   horizon and a moon, layered hills with a few lit windows far off, the house glowing from inside, the battery LED on,
   the array mirroring the dusk, the sakura lit from below by the garden lantern, a few petals drifting down.
   A calm, cinematic "the lights stay on" still with slow, small motion. */
import { THREE, pbrMaterial, rng, clamp, lerp, damp, smooth, REDUCED } from '../core.js';

const SKY = /* glsl */`
uniform vec3 uMoonDir, uWest; uniform float uTime, uBand;
float nH(vec2 p){ vec3 p3 = fract(vec3(p.xyx) * .1031); p3 += dot(p3, p3.yzx + 33.33); return fract((p3.x + p3.y) * p3.z); }
float nN(float x){ float i = floor(x), f = fract(x); f = f * f * (3. - 2. * f); return mix(nH(vec2(i, 3.1)), nH(vec2(i + 1., 3.1)), f); }
float nF(float x){ return nN(x) * .55 + nN(x * 2.3 + 7.) * .28 + nN(x * 5.1 + 3.) * .12 + nN(x * 11.7) * .05; }
float nN2(vec2 p){ vec2 i = floor(p), f = fract(p); f = f * f * (3. - 2. * f); return mix(mix(nH(i), nH(i + vec2(1,0)), f.x), mix(nH(i + vec2(0,1)), nH(i + vec2(1,1)), f.x), f.y); }
float nF2(vec2 p){ return nN2(p) * .5 + nN2(p * 2.1 + 5.) * .3 + nN2(p * 4.3 + 9.) * .2; }
vec3 upperSky(vec3 d, float detail){
  float el = asin(clamp(d.y, -1., 1.)), e = max(el, 0.);
  float az = atan(d.x, -d.z);
  vec2 dh = normalize(d.xz + vec2(1e-5));
  float tw = dot(dh, normalize(uWest.xz)) * .5 + .5;              // 1 toward where the sun went down
  vec3 zen = vec3(.004, .006, .026);
  vec3 hi  = vec3(.011, .016, .062);
  vec3 mid = mix(vec3(.03, .034, .105), vec3(.075, .045, .125), pow(tw, 2.2));
  vec3 low = mix(vec3(.06, .058, .14), vec3(.62, .19, .065), pow(tw, 4.5));
  vec3 c = mix(low, mid, smoothstep(0., .1, e));
  c = mix(c, hi, smoothstep(.07, .42, e));
  c = mix(c, zen, smoothstep(.35, 1.2, e));
  c += vec3(1.05, .33, .08) * exp(-e / .018) * pow(tw, 9.) * uBand;   // the last hot band on the horizon
  c += vec3(.14, .06, .1) * exp(-e / .09) * pow(tw, 3.) * uBand;
  // thin high cirrus catching the afterglow on the west, blue-grey elsewhere
  if (detail > 0.) {
    vec2 q = vec2(az * 2.4, e * 26.);
    float cl = smoothstep(.55, .85, nF2(q + vec2(uTime * .002, 0.))) * smoothstep(.03, .12, e) * smoothstep(.45, .18, e);
    c = mix(c, mix(vec3(.05, .05, .1), vec3(.32, .12, .1), pow(tw, 3.)) * (.8 + .4 * nF2(q * 3.)), cl * .55);
  }
  // a young moon: a lit sphere (the terminator is a half-ellipse), faint earthshine, a soft halo
  float r = acos(clamp(dot(d, uMoonDir), -1., 1.));
  c += vec3(.5, .56, .74) * (exp(-r / .03) * .06 + exp(-r / .16) * .02);
  vec3 mu = normalize(cross(uMoonDir, vec3(0., 1., 0.))), mv = cross(mu, uMoonDir);
  vec2 mp = vec2(dot(d, mu), dot(d, mv)) / .0085;
  float front = step(0., dot(d, uMoonDir));
  float rr = length(mp), disc = smoothstep(1., .9, rr) * front;
  vec3 mn = vec3(mp, sqrt(max(0., 1. - rr * rr)));
  vec2 sunIn = normalize(vec2(dot(uWest, mu), dot(uWest + vec3(0., -.6, 0.), mv)));
  vec3 sL = normalize(vec3(sunIn * .62, -.78));
  float lit = smoothstep(-.04, .12, dot(mn, sL));
  float maria = smoothstep(.45, .75, nN2(mp * 2.2 + 3.) * .65 + nN2(mp * 5.) * .35);
  float limb = .7 + .3 * mn.z;
  c = mix(c, mix(vec3(.045, .05, .085), vec3(3.6, 3.45, 3.1) * (1. - .22 * maria) * limb, lit), disc);
  // stars: sparse, fading toward the horizon, the west glow and the moon
  if (detail > 0.) {
    vec2 g = vec2(az * cos(el), el) / .012;
    vec2 cell = floor(g), f = fract(g) - .5;
    float h = nH(cell), h2 = nH(cell + 17.3);
    vec2 o = vec2(nH(cell + 3.7), nH(cell + 9.1)) - .5;
    float st = step(.93, h) * (.2 + .8 * pow(h2, 3.)) * smoothstep(.07, .018, length(f - o * .7));
    st *= .75 + .25 * sin(uTime * (1.2 + h2 * 2.5) + h * 50.);
    st *= smoothstep(.07, .3, e) * (1. - .9 * pow(tw, 5.) * exp(-e / .22)) * smoothstep(.03, .12, r);
    c += vec3(.8, .85, 1.) * st * 1.8;
  }
  // three ridgelines, each lighter and hazier with distance; a few village lights on the nearest
  vec3 haze = mix(vec3(.07, .065, .15), vec3(.36, .15, .11), pow(tw, 5.));
  float r1 = .01 + .03 * pow(nF(az * 6.5 + 1.3), 1.5) + .004 * nN(az * 40.);
  float r2 = .006 + .022 * pow(nF(az * 9.5 + 8.), 1.5) + .003 * nN(az * 60. + 3.);
  float r3 = .003 + .013 * pow(nF(az * 13. + 21.), 1.4) + .002 * nN(az * 90. + 7.);
  if (el < r1) c = mix(c, haze * .9 + vec3(.012, .012, .03), .8);
  if (el < r2) c = mix(haze * .55, vec3(.02, .021, .05), .55);
  if (el < r3) {
    c = mix(haze * .25, vec3(.012, .013, .03), .7);
    if (detail > 0.) {
      vec2 lg = vec2(az * 300., el * 1100.);
      vec2 lc = floor(lg); float lh = nH(lc + 41.);
      float village = smoothstep(.62, .75, nF(az * 6. + 2.));
      float win = step(.975, lh) * village * step(el, r3 - .003) * step(-.002, el);
      c += vec3(1.5, .72, .3) * win * (.35 + .65 * nH(lc + 7.));
    }
  }
  float tl = .0025 + .004 * nF(az * 38.) + .0025 * nF(az * 130. + 3.);
  if (el < tl) c = vec3(.011, .012, .026);
  return c;
}
vec3 nightSky(vec3 d, float detail){
  if (d.y >= 0.) return upperSky(d, detail);
  // the lake: a mirror of the sky and hills, broken into horizontal streaks that lengthen toward the viewer
  float el = -asin(clamp(d.y, -1., 1.)), az = atan(d.x, -d.z);
  float k = clamp(el / .06, 0., 1.);
  float rip = (nN2(vec2(az * 520., log(el + 1e-4) * 70. + uTime * .3)) - .5) * (.0006 + .006 * k) + (nN2(vec2(az * 90., log(el + 1e-4) * 22.)) - .5) * .002 * k;
  vec3 r = normalize(vec3(d.x, max(el + rip, .0002), d.z));
  vec3 c = upperSky(r, 0.) * (.78 - .2 * k);
  return mix(c, vec3(.012, .013, .03), smoothstep(.02, .25, el));
}`;

export async function create(ctx) {
  const { renderer, env } = ctx;
  const scene = new THREE.Scene();
  const camera = new THREE.PerspectiveCamera(30, 1.2, .3, 900);
  const R = rng(77);

  /* ------------------------------------------------------------ sky, and an environment made from it */
  const west = new THREE.Vector3(.3, 0, -.95).normalize();
  const moonDir = new THREE.Vector3(.36, .19, -.91).normalize();
  const skyU = { uMoonDir: { value: moonDir }, uWest: { value: west }, uTime: { value: 0 }, uDetail: { value: 1 }, uBand: { value: 1 } };
  const skyMat = new THREE.ShaderMaterial({
    uniforms: skyU, side: THREE.BackSide, depthWrite: false,
    vertexShader: 'varying vec3 vDir; void main(){ vec4 w = modelMatrix * vec4(position, 1.); vDir = w.xyz - cameraPosition; gl_Position = projectionMatrix * viewMatrix * w; gl_Position.z = gl_Position.w; }',
    fragmentShader: SKY + 'uniform float uDetail; varying vec3 vDir; void main(){ gl_FragColor = vec4(nightSky(normalize(vDir), uDetail), 1.); }',
  });
  const sky = new THREE.Mesh(new THREE.SphereGeometry(600, 48, 24), skyMat);
  sky.frustumCulled = false; sky.renderOrder = -10; scene.add(sky);
  const envScene = new THREE.Scene();
  const envMat = skyMat.clone(); envMat.uniforms.uMoonDir.value = moonDir; envMat.uniforms.uWest.value = west; envMat.uniforms.uDetail.value = 0; envMat.uniforms.uBand.value = .3;
  envScene.add(new THREE.Mesh(new THREE.SphereGeometry(50, 64, 32), envMat));
  const pm = new THREE.PMREMGenerator(renderer);
  const envRT = pm.fromScene(envScene, 0, .1, 200); pm.dispose();
  scene.environment = envRT.texture; scene.environmentIntensity = 1.1;

  /* ------------------------------------------------------------ models */
  const [HM, SM, GM] = (await Promise.allSettled([import('../models/house.js'), import('../models/sakura.js'), import('../models/garden.js')])).map(r => r.status === 'fulfilled' ? r.value : null);
  let house = null;
  if (HM?.buildHouse) house = await HM.buildHouse({ env, detail: 'high', panels: true, glow: 1, seed: 1 });
  else {
    const g = new THREE.Group(); const m = new THREE.Mesh(new THREE.BoxGeometry(10, 4, 5), new THREE.MeshStandardMaterial({ color: 0x8a8378 })); m.position.y = 2; g.add(m);
    house = { group: g, panels: [], setGlow() {}, anchors: {}, sunCatchers: [] };
  }
  scene.add(house.group);
  house.setGlow(.5);
  const M = house.materials || {};

  // shoji: one lamp deep in the left room, a paper andon on the right, a six-fold byobu standing between lamp and paper
  if (M.paper) {
    const prev = M.paper.onBeforeCompile;
    M.paper.onBeforeCompile = (sh, r) => {
      prev?.(sh, r);
      sh.vertexShader = sh.vertexShader.replace('#include <common>', '#include <common>\nvarying vec3 vNPW;').replace('#include <worldpos_vertex>', '#include <worldpos_vertex>\nvNPW = (modelMatrix * vec4(transformed, 1.)).xyz;');
      sh.fragmentShader = sh.fragmentShader.replace('#include <common>', '#include <common>\nvarying vec3 vNPW;').replace('totalEmissiveRadiance *= vColor.rgb;', `totalEmissiveRadiance *= vColor.rgb;
        { vec2 q = vNPW.xy;
          float lamp = .2 + 1.75 * exp(-dot((q - vec2(-1.5, 1.25)) / vec2(2.4, 1.4), (q - vec2(-1.5, 1.25)) / vec2(2.4, 1.4)))
                           + .85 * exp(-dot((q - vec2(2.3, .85)) / vec2(1.3, 1.0), (q - vec2(2.3, .85)) / vec2(1.3, 1.0)));
          lamp *= .75 + .25 * smoothstep(2.35, 1.2, q.y);                                 // the ceiling is darker than the floor lamp
          float bx = (q.x + 2.55) / 2.7;                                                 // byobu: six leaves, alternately facing the lamp
          float top = 1.42 + .02 * sin(bx * 37.7);
          float inB = step(0., bx) * step(bx, 1.) * smoothstep(top + .03, top - .03, q.y);
          float leaf = mod(floor(bx * 6.), 2.);
          float shade = inB * mix(.72, .86, leaf) * (1. - .35 * smoothstep(.5, .6, abs(fract(bx * 6.) - .5)));
          totalEmissiveRadiance *= lamp * (1. - shade); }`);
    };
    M.paper.customProgramCacheKey = () => 'night-paper';
  }

  // the array: dark cells under glass that mirrors a lavender-to-peach dusk (its own static environment)
  const duskEnv = (() => {
    const sc = new THREE.Scene();
    sc.add(new THREE.Mesh(new THREE.SphereGeometry(50, 48, 24), new THREE.ShaderMaterial({ side: THREE.BackSide, depthWrite: false,
      vertexShader: 'varying vec3 vD; void main(){ vD = position; gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.); }',
      fragmentShader: `varying vec3 vD; void main(){ vec3 d = normalize(vD); float y = d.y;
        vec3 c = mix(vec3(.95, .5, .32), vec3(.46, .37, .68), smoothstep(.15, .6, y));
        c = mix(c, vec3(.07, .07, .18), smoothstep(.72, 1., y));
        c *= .55 + .45 * smoothstep(-1., .2, -d.z);                         // brighter toward the west, behind the house
        c = mix(c, vec3(.02, .02, .04), smoothstep(.02, -.1, y));
        gl_FragColor = vec4(c, 1.); }` })));
    const g = new THREE.PMREMGenerator(renderer); const rt = g.fromScene(sc, 0, .1, 100); g.dispose(); return rt.texture;
  })();
  { const seen = new Set(); for (const p of house.panels || []) p.traverse(o => { if (o.isMesh && o.material && !seen.has(o.material)) { seen.add(o.material);
      if (o.material.map) { o.material.color.setRGB(2.2, 2.4, 3.2); o.material.envMap = duskEnv; o.material.envMapIntensity = 1.35; o.material.metalness = .1; }
      else { o.material.envMap = duskEnv; o.material.envMapIntensity = .9; } } }); }

  const TREE = new THREE.Vector3(6.4, 0, 3.4), LANT = new THREE.Vector3(3.3, 0, 6.6);
  let sakura = null, garden = null;
  if (GM?.buildGarden) {
    garden = await GM.buildGarden({
      seed: 6, size: [44, 34], rake: 'x', court: [-7.6, -5.6, 9.6, 13.5], mossGround: true, glow: 1, edge: [[30, -9.5], [-30, -9.5]],
      sand: { color: [.5, .49, .47], pitch: .1, amp: .012 },
      lantern: [LANT.x, LANT.z], pine: [-8.8, 2.6, .6],
      path: [[2.2, 12.6], [1.7, 11.7], [2.0, 10.8], [1.4, 9.9], [1.7, 9.0], [1.2, 8.1], [1.5, 7.2], [.9, 6.3], [1.1, 5.3], [.6, 4.2]],
      rocks: [[4.4, 8.6, .95, .4], [5.5, 9.4, .5, 1.2], [3.5, 7.9, .36, 2.2], [-3.6, 9.4, .6, .8], [-1.6, 12.4, .75, 1.7], [-.4, 13.0, .38, .4]],
      moss: [[4.5, 8.7, 2.0, 1.4], [6.9, 3.9, 2.2, 1.9], [-7.0, -3.4, 1.8, 1.2], [-1.4, 12.5, 1.6, 1.0]],
      shrubs: [[10.6, -3.2, 1.4, .9, 1.1], [11.2, -1.1, .8, .55, .7], [10.4, 1.2, 1.7, 1.15, 1.2], [11.4, 3.6, .9, .6, .8], [10.7, 5.8, 1.25, .8, 1.0], [11.3, 8.4, .7, .45, .6],
               [-10.2, 5.6, 1.5, .95, 1.2], [-9.4, 8.2, .8, .5, .7], [-11.0, 10.5, 1.3, .85, 1.1], [-8.9, -2.0, 1.0, .7, .9]],
    });
    garden.gravel.material.normalScale.set(.55, .55);
    const slab = garden.group.getObjectByName('slab'); if (slab) slab.material.color.setRGB(.5, .5, .52);
    const rock = garden.group.getObjectByName('rock'); if (rock) { rock.material.envMapIntensity = 2.2; }
    if (garden.mossMaterial) { garden.mossMaterial.envMapIntensity = 1.6; }   // moss albedo is calibrated in garden.js now (was ×4.2 here)
    garden.setGlow?.(.4);
    scene.add(garden.group);
  }
  if (SM?.buildSakura) {
    sakura = await SM.buildSakura({ seed: 3, height: 6.6, bloom: 1, spread: .95, lean: -.04, avoid: q => { const x = q.x + TREE.x, z = q.z + TREE.z; return (x < 5.9 && z < 3.5 && q.y < 7.8) || x > 10.5; } });
    sakura.group.position.copy(TREE); scene.add(sakura.group);
    sakura.setTranslucency?.(new THREE.Color(1, .78, .84), .45);
    // a pale, low-contrast mass: cool sky on top, warm window and lantern light underneath, sky through the gaps
    const bm = sakura.blossoms.material, bg = sakura.blossoms.geometry, P = bg.attributes.position;
    for (let i = 0; i < P.count; i += 4) {           // thin the clumps: shrink each card toward its centre
      let cx = 0, cy = 0, cz = 0; for (let k = 0; k < 4; k++) { cx += P.getX(i + k); cy += P.getY(i + k); cz += P.getZ(i + k); }
      cx /= 4; cy /= 4; cz /= 4;
      for (let k = 0; k < 4; k++) P.setXYZ(i + k, cx + (P.getX(i + k) - cx) * .84, cy + (P.getY(i + k) - cy) * .84, cz + (P.getZ(i + k) - cz) * .84);
    }
    P.needsUpdate = true;
    const box = new THREE.Box3().setFromBufferAttribute(P);
    const bu = { uY: { value: new THREE.Vector2(box.min.y + TREE.y, box.max.y + TREE.y) }, uLant: { value: new THREE.Vector3(LANT.x, 1.1, LANT.z) }, uHouseX: { value: 5.2 } };
    const prevB = bm.onBeforeCompile;
    bm.onBeforeCompile = (sh, r) => {
      prevB?.(sh, r); Object.assign(sh.uniforms, bu);
      sh.vertexShader = sh.vertexShader.replace('#include <common>', '#include <common>\nvarying vec3 vBW;').replace('#include <worldpos_vertex>', '#include <worldpos_vertex>\nvBW = (modelMatrix * vec4(transformed, 1.)).xyz;');
      sh.fragmentShader = sh.fragmentShader.replace('#include <common>', '#include <common>\nvarying vec3 vBW; uniform vec2 uY; uniform vec3 uLant; uniform float uHouseX;')
        .replace('#include <opaque_fragment>', `{
          float h = clamp((vBW.y - uY.x) / (uY.y - uY.x), 0., 1.);
          float lum = dot(diffuseColor.rgb, vec3(.3, .55, .15));
          vec3 pale = mix(vec3(lum), diffuseColor.rgb, .55) * .5 + vec3(.3, .25, .27);     // pale petals, faint pink eyes
          vec3 sky = vec3(.05, .06, .14) * (.2 + .8 * h);
          vec3 win = vec3(1.0, .5, .22) * pow(1. - h, 2.) * exp(-max(vBW.x - uHouseX, 0.) / 2.4) * .45;
          vec3 lan = vec3(1.0, .6, .32) * exp(-distance(vBW, uLant) / 3.2) * 1.7 * pow(1. - h, 1.5);
          outgoingLight = (pale * (sky + win + lan) * mix(.35, 1., vShade) + outgoingLight * .1) * .72;
        }
        #include <opaque_fragment>`);
    };
    bm.customProgramCacheKey = () => 'night-blossom';
    bm.alphaTest = .56; bm.polygonOffset = true; bm.polygonOffsetFactor = -1; bm.polygonOffsetUnits = -60;   // petals win over the twigs just behind them
    if (sakura.trunk?.material) sakura.trunk.material.color.multiplyScalar(1.8);
  }
  // wide dark ground beyond the garden, out to the hills
  const groundMat = await pbrMaterial('forest_ground_04', { repeat: [1 / 2.5, 1 / 2.5], normal: .8, roughness: 1 });
  groundMat.color.setRGB(2.2, 2.2, 2.3);
  groundMat.onBeforeCompile = sh => {
    sh.vertexShader = sh.vertexShader.replace('#include <common>', '#include <common>\nvarying vec3 vGW;').replace('#include <worldpos_vertex>', '#include <worldpos_vertex>\nvGW = (modelMatrix * vec4(transformed, 1.)).xyz;');
    sh.fragmentShader = sh.fragmentShader.replace('#include <common>', '#include <common>\nvarying vec3 vGW;').replace('#include <dithering_fragment>', 'if (vGW.z < -9.) discard;\ngl_FragColor.rgb = mix(gl_FragColor.rgb, vec3(.03, .03, .066), smoothstep(22., 60., length(vGW.xz)));\n#include <dithering_fragment>');
  };
  groundMat.customProgramCacheKey = () => 'night-ground';
  const ground = new THREE.Mesh(new THREE.CircleGeometry(62, 64).rotateX(-Math.PI / 2), groundMat);
  { const uv = ground.geometry.attributes.uv, p = ground.geometry.attributes.position; for (let i = 0; i < uv.count; i++) uv.setXY(i, p.getX(i), p.getZ(i)); }
  ground.position.y = garden ? -.06 : 0; ground.receiveShadow = true; scene.add(ground);
  house.group.traverse(o => { if (o.isMesh) o.receiveShadow = true; });

  /* ------------------------------------------------------------ light: moon key (the one shadow), warm house, lantern */
  const moon = new THREE.DirectionalLight(0xb4b8ff, 1.5);
  moon.position.set(10, 26, -26); moon.target.position.set(1, 0, 2);
  moon.castShadow = true; moon.shadow.mapSize.set(2048, 2048); moon.shadow.radius = 4; moon.shadow.bias = -.0004; moon.shadow.normalBias = .03;
  Object.assign(moon.shadow.camera, { left: -16, right: 16, top: 15, bottom: -12, near: 1, far: 100 });
  moon.shadow.autoUpdate = false; moon.shadow.needsUpdate = true;
  scene.add(moon, moon.target);
  // the blue sky behind the camera: a faint cool fill, no shadow
  const fill = new THREE.DirectionalLight(0x8ea4ff, .45); fill.position.set(-10, 14, 24); scene.add(fill);
  const skyFill = new THREE.HemisphereLight(0x6f7fc4, 0x1a1620, .55); scene.add(skyFill);
  const topLight = new THREE.DirectionalLight(0x9fb0ff, .55); topLight.position.set(4, 30, 10); scene.add(topLight);
  const warm = 0xffa45a;
  const spills = [[-2.4, .95, 3.3], [.9, .95, 3.3], [3.0, .95, 3.2]].map(p => { const l = new THREE.PointLight(warm, 2.2, 5, 2); l.position.set(...p); scene.add(l); return l; });
  // the lit shoji throw a broad warm wash onto the sand and the rocks' house-facing sides
  const wash = new THREE.SpotLight(0xffa860, 60, 18, 1.15, 1, 2); wash.position.set(-.3, 1.3, 2.6); wash.target.position.set(-.3, 0, 10); scene.add(wash, wash.target);
  const lantern = new THREE.PointLight(0xff9a45, 4, 5, 2); lantern.position.set(LANT.x, 1.05, LANT.z); scene.add(lantern);
  const uplight = new THREE.SpotLight(0xffb878, 16, 22, .55, .9, 2); uplight.position.set(LANT.x - .2, .45, LANT.z + .6);
  { const cc = sakura ? sakura.crown.centre.clone().add(TREE) : new THREE.Vector3(TREE.x, 4.6, TREE.z); uplight.target.position.copy(cc); }
  scene.add(uplight, uplight.target);

  /* ------------------------------------------------------------ a few petals drifting down past the lantern */
  const NP = 40, petalGeo = new THREE.PlaneGeometry(.07, .085);
  { const p = petalGeo.attributes.position; for (let i = 0; i < p.count; i++) { const x = p.getX(i), y = p.getY(i); p.setZ(i, (x * x) * 6 - Math.abs(y) * .1); } petalGeo.computeVertexNormals(); }
  const pc = document.createElement('canvas'); pc.width = pc.height = 64;
  { const g = pc.getContext('2d'); g.translate(32, 32); g.fillStyle = '#fbe3e8';
    const pp = new Path2D(); pp.moveTo(0, 28); pp.bezierCurveTo(16, 18, 22, -6, 14, -22); pp.quadraticCurveTo(6, -28, 0, -20); pp.quadraticCurveTo(-6, -28, -14, -22); pp.bezierCurveTo(-22, -6, -16, 18, 0, 28);
    g.fill(pp); g.fillStyle = 'rgba(226,130,156,.45)'; g.beginPath(); g.ellipse(0, 20, 5, 8, 0, 0, 7); g.fill(); }
  const petalTex = new THREE.CanvasTexture(pc); petalTex.colorSpace = THREE.SRGBColorSpace;
  const petalMat = new THREE.MeshStandardMaterial({ map: petalTex, alphaTest: .5, color: new THREE.Color(1, .9, .93), roughness: .7, side: THREE.DoubleSide, emissive: new THREE.Color(.03, .012, .02) });
  const petals = new THREE.InstancedMesh(petalGeo, petalMat, NP); petals.frustumCulled = false; scene.add(petals);
  const pd = Array.from({ length: NP }, () => ({ x: TREE.x - 3.2 + R() * 5, z: TREE.z - 1 + R() * 4.5, y0: R() * 6.2, sp: .22 + R() * .2, ph: R() * 6.28, sw: .3 + R() * .5, rs: 1 + R() * 2 }));
  const _m = new THREE.Matrix4(), _q = new THREE.Quaternion(), _e = new THREE.Euler(), _p = new THREE.Vector3(), _s = new THREE.Vector3(1, 1, 1);

  /* ------------------------------------------------------------ camera */
  const look = new THREE.Vector3(2.5, 3.1, 1.6);
  const par = { x: 0, y: 0 };
  let moonAspect = 0; const _mv = new THREE.Vector3(), _lk = new THREE.Vector3();
  const post = {
    exposure: 1.2, tone: 'aces', hue: .4, sat: 1.05, contrast: 1.06, vignette: .32, grain: .02, ss: 1,
    shadowTint: [.9, .95, 1.1], highTint: [1.05, 1, .93],
    bloom: { strength: .4, radius: 1, threshold: 1.5, knee: .8 }, rays: null,
  };
  return {
    scene, camera, post,
    update(dt, t, s) {
      const a = s.w / Math.max(1, s.h), narrow = a < 1.05;
      const tx = REDUCED ? 0 : clamp(s.pointer.x, -1, 1), ty = REDUCED ? 0 : clamp(s.pointer.y, -1, 1);
      par.x = damp(par.x, s.hover ? tx : 0, 1.6, dt); par.y = damp(par.y, s.hover ? ty : 0, 1.6, dt);
      const tt = REDUCED ? 0 : t;
      const drift = Math.sin(tt * .06) * .5;
      const dist = narrow ? 37 : 31, p0 = narrow ? .13 : .06, pitch = p0 + par.y * .012;
      const yaw = (narrow ? -.52 : -.6) + par.x * .04 + drift * .02;
      const lx = look.x + (narrow ? .7 : 0);
      camera.position.set(lx + Math.sin(yaw) * Math.cos(pitch) * dist, look.y + Math.sin(pitch) * dist, look.z + Math.cos(yaw) * Math.cos(pitch) * dist);
      camera.fov = narrow ? 38 : 31; camera.updateProjectionMatrix();
      _lk.set(lx, look.y, look.z); camera.lookAt(_lk);
      if (Math.abs(moonAspect - a) > .01) {   // park the crescent in the upper left of the frame, from the resting pose
        moonAspect = a; const save = camera.position.clone(), q0 = camera.quaternion.clone();
        const y0 = narrow ? -.52 : -.6; camera.position.set(lx + Math.sin(y0) * Math.cos(p0) * dist, look.y + Math.sin(p0) * dist, look.z + Math.cos(y0) * Math.cos(p0) * dist); camera.lookAt(_lk); camera.updateMatrixWorld();
        _mv.set(narrow ? -.5 : -.62, narrow ? .74 : .7, .5).unproject(camera).sub(camera.position).normalize(); moonDir.copy(_mv);
        camera.position.copy(save); camera.quaternion.copy(q0); camera.updateMatrixWorld();
      }
      skyU.uTime.value = tt;
      sakura?.update?.(tt, REDUCED ? 0 : .3);
      // petals: slow fall with sway, recycled at the top
      for (let i = 0; i < NP; i++) {
        const q = pd[i], yy = 5.3 - ((tt * q.sp + q.y0) % 5.3) + .04;
        _p.set(q.x + Math.sin(tt * .7 + q.ph) * q.sw, yy, q.z + Math.cos(tt * .5 + q.ph * 1.3) * q.sw * .6);
        _e.set(tt * q.rs + q.ph, tt * .8 + q.ph * 2, Math.sin(tt + q.ph)); _q.setFromEuler(_e);
        _m.compose(_p, _q, _s); petals.setMatrixAt(i, _m);
      }
      petals.instanceMatrix.needsUpdate = true;
    },
  };
}
