/* Hero — a minka with a solar roof and a somei-yoshino in the last of the golden hour.
   The sun sits low behind the cherry on the right; its light rakes toward the viewer, shafts stream through the
   canopy and past the ridge, the far hills stand in layered lavender haze, the shoji start to glow.
   Composition (1440x900): left ~45% is calm, light sky for the dark headline; the house + tree hold the right;
   the foreground garden lies in the long evening shadow so the cream stats strip reads along the bottom. */
import { THREE, rng, clamp, lerp, damp, smooth, REDUCED, makeCanvas } from '../core.js';
import { buildHouse, paint, translucencyGLSL, bledTexture } from '../models/house.js';
import { buildSakura } from '../models/sakura.js';
import { buildGarden } from '../models/garden.js';

const Q = new URLSearchParams(location.search);
const qv = (k, d) => Q.has(k) ? Q.get(k).split(',').map(Number) : d;
const qn = (k, d) => Q.has(k) ? +Q.get(k) : d;
const deg = Math.PI / 180;

/* ------------------------------------------------------------------ sky (shared by the dome and the hills' haze) */
const SKY_GLSL = /* glsl */`
uniform vec3 uSun; uniform float uSunK, uDusk, uCore;
vec3 skyCol(vec3 v){
  float h = v.y, mu = dot(v, uSun);
  vec2 hv = normalize(v.xz + 1e-5), hs = normalize(uSun.xz);
  float ang = acos(clamp(dot(hv, hs), -1., 1.));           // horizontal angle from the sun
  float az = exp(-ang * ang / .09);                          // ~17 deg wide warm sector around the sun
  float e = max(h, 0.);
  vec3 horAway = mix(vec3(2.15, 1.45, 1.22), vec3(1.25, .7, .78), uDusk);   // pale peach
  vec3 horSun  = mix(vec3(4.4, 2.75, 1.45), vec3(4.2, 1.5, .55), uDusk);    // apricot-gold
  vec3 midAway = mix(vec3(1.42, 1.12, 1.46), vec3(.62, .5, .82), uDusk);    // lavender-pink haze
  vec3 midSun  = mix(vec3(2.35, 1.7, 1.3), vec3(1.5, .82, .7), uDusk);
  vec3 top     = mix(vec3(.95, .86, 1.3), vec3(.34, .32, .62), uDusk);      // lavender
  float k = az;
  vec3 hor = mix(horAway, horSun, k), mid = mix(midAway, midSun, k * .8);
  vec3 col = mix(hor, mid, smoothstep(0., .16, pow(e, .8)));
  col = mix(col, top, smoothstep(.12, .6, e));
  // a faint pink band just above the horizon away from the sun (belt of Venus on the far side)
  col += vec3(.18, .06, .1) * exp(-pow((e - .05) / .05, 2.)) * (1. - k);
  // forward scattering around the sun
  float m = max(mu, 0.);
  col += uSunK * (vec3(.85, .45, .18) * pow(m, 14.) + vec3(2.3, 2.05, 1.75) * pow(m, 60.) + vec3(30., 28., 25.) * pow(m, 4000.) + vec3(10., 9.5, 8.6) * pow(m, uCore));
  // below the horizon: haze deepening toward the ground
  col = mix(col, hor * vec3(.72, .66, .7), smoothstep(0., -.04, h));
  return col;
}`;

function skyDome(U) {
  const m = new THREE.ShaderMaterial({
    side: THREE.BackSide, depthWrite: false, depthTest: false, uniforms: U,
    vertexShader: `varying vec3 vDir; void main(){ vDir = position; vec4 p = projectionMatrix * modelViewMatrix * vec4(position, 1.); gl_Position = p.xyww; }`,
    fragmentShader: `${SKY_GLSL}
      varying vec3 vDir;
      float hh(vec2 p){ vec3 p3 = fract(vec3(p.xyx) * .1031); p3 += dot(p3, p3.yzx + 33.33); return fract((p3.x + p3.y) * p3.z); }
      float vn(vec2 p){ vec2 i = floor(p), f = fract(p); f = f * f * (3. - 2. * f); return mix(mix(hh(i), hh(i + vec2(1,0)), f.x), mix(hh(i + vec2(0,1)), hh(i + vec2(1,1)), f.x), f.y); }
      void main(){ vec3 v = normalize(vDir); vec3 col = skyCol(v);
        col += vec3(40., 38.5, 36.) * uSunK * smoothstep(.99992, .99996, dot(v, uSun));   // the disc
        gl_FragColor = vec4(col, 1.); }`,
  });
  const s = new THREE.Mesh(new THREE.SphereGeometry(2500, 64, 32), m);
  s.frustumCulled = false; s.renderOrder = -10; return s;
}

/* ------------------------------------------------------------------ hills: arcs of layered ridgelines, hazed toward the sky */
function hills(U, origin, fwdAz, R) {
  const layers = [
    { r: 2600, h0: 40, amp: 210, f: 1.1, haze: .8, trees: 0, tint: [.5, .4, .62] },
    { r: 1600, h0: 20, amp: 120, f: 1.8, haze: .66, trees: 0, tint: [.4, .3, .5] },
    { r: 950, h0: 8, amp: 60, f: 2.7, haze: .5, trees: .7, tint: [.3, .22, .36] },
    { r: 520, h0: 3, amp: 24, f: 3.8, haze: .36, trees: 1.1, tint: [.18, .13, .2] },
    { r: 260, h0: -1, amp: 9, f: 5.5, haze: .24, trees: 1.4, tint: [.08, .065, .075] },
  ];
  const mat = new THREE.ShaderMaterial({
    uniforms: U, depthWrite: true,
    vertexShader: `attribute float aHaze; attribute vec3 aTint; varying float vHaze; varying vec3 vTint; varying vec3 vW; varying float vTop;
      attribute float aTop;
      void main(){ vHaze = aHaze; vTint = aTint; vTop = aTop; vec4 w = modelMatrix * vec4(position, 1.); vW = w.xyz; gl_Position = projectionMatrix * viewMatrix * w; }`,
    fragmentShader: `${SKY_GLSL}
      uniform vec3 uCam; varying float vHaze; varying vec3 vTint; varying vec3 vW; varying float vTop;
      void main(){ vec3 v = normalize(vW - uCam); vec3 sk = skyCol(vec3(v.x, max(v.y, .002), v.z));
        float mu = max(dot(v, uSun), 0.);
        // ridge rim: the sun side of each crest catches a little light through the haze
        float haze = vHaze + (1. - vHaze) * .55 * pow(mu, 6.) * uSunK;
        float depth = mix(1., .82, vTop);                       // a touch of mist pooling in the valleys
        vec3 base = vTint * (.55 + .45 * vTop) * mix(vec3(1.), vec3(1.2, .95, .8), pow(mu, 4.));
        vec3 col = mix(base, sk * depth, clamp(haze + (1. - vTop) * .12, 0., 1.));
        gl_FragColor = vec4(col, 1.); }`,
  });
  const group = new THREE.Group();
  const n2 = (x, s) => { const a = Math.sin(x * 1.7 + s) * .5 + Math.sin(x * 3.9 + s * 2.1) * .25 + Math.sin(x * 8.3 + s * .7) * .125 + Math.sin(x * 17.1 + s * 3.3) * .07; return a; };
  for (const [li, L] of layers.entries()) {
    const seg = 1400, span = 150 * deg, pos = [], haze = [], tint = [], top = [], idx = [];
    const s0 = R() * 10;
    for (let i = 0; i <= seg; i++) {
      const t = i / seg, a = fwdAz - span / 2 + t * span;
      const x = Math.cos(a), z = Math.sin(a);
      let hgt = L.h0 + L.amp * (.5 + .5 * n2(t * 6.28 * L.f, s0));
      // keep the headline side low and calm: the ridges fall away on the left of the view
      if (L.trees) {   // rounded canopy bumps (a soft forest edge), not per-vertex spikes
        let cr = 0;
        for (const [fr, am] of [[97, .5], [211, .3], [433, .2]]) { const q = t * fr * L.f / 3.6 + s0 * fr, fq = q - Math.floor(q), hh = .5 + .5 * Math.sin(Math.floor(q) * 12.9898 + s0);
          cr += am * Math.sqrt(Math.max(0, 1 - (fq * 2 - 1) ** 2)) * hh; }
        hgt += L.trees * cr * (L.r / 230) * .8 * (.5 + .5 * Math.sin(t * 11 + s0) * Math.sin(t * 5.3 + 1));
      }
      pos.push(origin.x + x * L.r, hgt + origin.y, origin.z + z * L.r); haze.push(L.haze); tint.push(...L.tint); top.push(1);
      pos.push(origin.x + x * L.r, -L.r * .08 + origin.y, origin.z + z * L.r); haze.push(L.haze); tint.push(...L.tint); top.push(0);
    }
    for (let i = 0; i < seg; i++) { const a = i * 2, b = a + 1, c = a + 2, d = a + 3; idx.push(a, b, c, c, b, d); }
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
    g.setAttribute('aHaze', new THREE.Float32BufferAttribute(haze, 1));
    g.setAttribute('aTint', new THREE.Float32BufferAttribute(tint, 3));
    g.setAttribute('aTop', new THREE.Float32BufferAttribute(top, 1));
    g.setIndex(idx);
    const m = new THREE.Mesh(g, mat); m.frustumCulled = false; m.renderOrder = -5 + li; group.add(m);
  }
  return { group, mat };
}

/* ------------------------------------------------------------------ near-tree falling petals (instanced, tumble edge-on) */
function petalField(U, count, box) {
  const R = rng(515);
  const g = new THREE.InstancedBufferGeometry();
  const base = new THREE.PlaneGeometry(.045, .052);
  g.index = base.index; g.attributes.position = base.attributes.position; g.attributes.uv = base.attributes.uv;
  const seed = new Float32Array(count * 4), rate = new Float32Array(count * 4);
  for (let i = 0; i < count; i++) {
    seed.set([R(), R(), R(), R()], i * 4);
    rate.set([.35 + R() * .45, (1.4 + R() * 2.4) * (R() < .5 ? -1 : 1), (R() - .5) * 1.4, .25 + R() * .35], i * 4);
  }
  g.setAttribute('aSeed', new THREE.InstancedBufferAttribute(seed, 4));
  g.setAttribute('aRate', new THREE.InstancedBufferAttribute(rate, 4));
  g.instanceCount = count;
  const m = new THREE.ShaderMaterial({
    uniforms: Object.assign({ uMin: { value: box.min }, uSize: { value: box.getSize(new THREE.Vector3()) }, uT: { value: 0 }, uWindV: { value: new THREE.Vector3(-.55, 0, .18) }, uSunC: { value: new THREE.Color() }, uAmb: { value: new THREE.Color() } }, U),
    side: THREE.DoubleSide,
    vertexShader: `uniform vec3 uMin, uSize, uWindV; uniform float uT; uniform vec3 uSun;
      attribute vec4 aSeed, aRate; varying vec2 vUv; varying float vFace; varying float vBack;
      void main(){ vUv = uv;
        float t = uT; float spin = aSeed.w * 6.2832 + t * aRate.y, roll = aSeed.w * 12.566 + t * aRate.z;
        vec3 drift = uWindV * t * (.7 + aRate.w) + vec3(0., -aRate.x * t, 0.);
        vec3 p0 = uMin + mod(vec3(aSeed.x, aSeed.y, aSeed.z) * uSize + drift, uSize);
        p0.x += sin(spin) * aRate.w * .35; p0.z += cos(spin * .7) * .15;
        vec3 p = position;
        float cs = cos(spin), sn = sin(spin); p = vec3(p.x * cs, p.y, p.x * sn);
        float cr = cos(roll), sr = sin(roll); p = vec3(p.x * cr - p.y * sr, p.x * sr + p.y * cr, p.z);
        vec3 nrm = normalize(vec3(sn * cr, sn * sr, -cs));
        vFace = abs(cs);
        vec4 w = vec4(p0 + p, 1.);
        vec3 vd = normalize(w.xyz - cameraPosition);
        vBack = pow(max(dot(vd, uSun), 0.), 4.);
        gl_Position = projectionMatrix * viewMatrix * w; }`,
    fragmentShader: `uniform vec3 uSunC, uAmb; varying vec2 vUv; varying float vFace; varying float vBack;
      void main(){ vec2 q = vUv * 2. - 1.; q.y *= 1.1;
        float r = length(q * vec2(1.25, 1.)); float notch = smoothstep(.12, .0, abs(q.x)) * smoothstep(.55, .95, q.y);
        if (r > .98 || (q.y > .75 && notch > .5)) discard;
        vec3 base = mix(vec3(.96, .5, .62), vec3(1., .82, .86), smoothstep(-.9, .6, q.y));
        vec3 col = base * (uAmb * (.55 + .45 * vFace) + uSunC * (.08 + .8 * vBack) * (.4 + .6 * (1. - vFace * .5))) * vec3(1., .9, .94);
        gl_FragColor = vec4(col, 1.); }`,
  });
  const mesh = new THREE.Mesh(g, m); mesh.frustumCulled = false;
  return { mesh, m };
}



/* ------------------------------------------------------------------ meadow grass: tuft cards (a 2 x 2 atlas of 40-70
   tapered blades each) scattered with screen-uniform density over the foreground. Roots sit in the ground's shade,
   upper blades catch the low sun through their backs (gold where the view looks toward the sun), and the tufts take
   the house's and trees' cast shadows, so long shadow stripes run across the field toward the viewer. */
function grassAtlas() {
  const c = makeCanvas(1024, 1024), g = c.getContext('2d'), R = rng(313);
  for (let v = 0; v < 4; v++) {
    const ox = (v % 2) * 512, oy = (v >> 1) * 512;
    g.save(); g.beginPath(); g.rect(ox, oy, 512, 512); g.clip();
    const n = 46 + (R() * 26 | 0);
    for (let i = 0; i < n; i++) {
      const bx = ox + 256 + (R() - .5) * 300, h = 150 + R() * R() * 330, w = 3 + R() * 3.5, lean = (R() - .5) * 120, by = oy + 512;
      const tone = .55 + R() * .45;
      const grd = g.createLinearGradient(0, by, 0, by - h);
      grd.addColorStop(0, `rgb(${30 * tone | 0},${40 * tone | 0},${16 * tone | 0})`);
      grd.addColorStop(.6, `rgb(${70 * tone | 0},${92 * tone | 0},${34 * tone | 0})`);
      grd.addColorStop(1, `rgb(${150 * tone | 0},${156 * tone | 0},${52 * tone | 0})`);
      g.fillStyle = grd; g.beginPath();
      g.moveTo(bx - w, by); g.quadraticCurveTo(bx + lean * .35 - w * .4, by - h * .55, bx + lean, by - h);
      g.quadraticCurveTo(bx + lean * .35 + w * .4, by - h * .5, bx + w, by); g.fill();
    }
    g.restore();
  }
  return c;
}
function grassCards(list, U) {
  const pos = [], uv = [], nor = [], hh = [], col = [], idx = [];
  let vi = 0;
  for (const [x, y, z, w, h, yaw, cell, tone] of list) {
    const ca = Math.cos(yaw) * w / 2, sa = Math.sin(yaw) * w / 2, u0 = (cell % 2) * .5, v0 = (cell >> 1) * .5;
    pos.push(x - ca, y - .05, z - sa, x + ca, y - .05, z + sa, x + ca, y + h, z + sa, x - ca, y + h, z - sa);
    uv.push(u0, 1 - v0 - .5, u0 + .5, 1 - v0 - .5, u0 + .5, 1 - v0, u0, 1 - v0);
    for (let k = 0; k < 4; k++) { nor.push(0, 1, 0); col.push(tone, tone, tone); }
    hh.push(0, 0, 1, 1);
    idx.push(vi, vi + 1, vi + 2, vi, vi + 2, vi + 3); vi += 4;
  }
  const geo = new THREE.BufferGeometry();
  geo.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3)); geo.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2));
  geo.setAttribute('normal', new THREE.Float32BufferAttribute(nor, 3)); geo.setAttribute('color', new THREE.Float32BufferAttribute(col, 3));
  geo.setAttribute('aH', new THREE.Float32BufferAttribute(hh, 1)); geo.setIndex(idx);
  const tex = bledTexture(grassAtlas());
  const m = new THREE.MeshStandardMaterial({ map: tex, alphaTest: .45, side: THREE.DoubleSide, roughness: .8, vertexColors: true, color: new THREE.Color(.3, .32, .24) });
  const gu = { uTime: U.uTime };
  m.onBeforeCompile = sh => {
    sh.uniforms.uTime = gu.uTime;
    sh.vertexShader = sh.vertexShader.replace('#include <common>', '#include <common>\nattribute float aH; varying float vH; uniform float uTime;')
      .replace('#include <begin_vertex>', `#include <begin_vertex>
        vH = aH;
        { vec4 wp = modelMatrix * vec4(position, 1.); float sw = sin(uTime * 1.3 + wp.x * .7 + wp.z * .4) * .6 + sin(uTime * 2.9 + wp.x * 2.1) * .25;
          transformed.x += aH * aH * sw * .035; transformed.z += aH * aH * sw * .02; }`);
    sh.fragmentShader = sh.fragmentShader.replace('#include <common>', '#include <common>\nvarying float vH;')
      .replace('#include <alphatest_fragment>', `{ vec2 ts = vMapUv * 1024.; float lod = .5 * log2(max(dot(dFdx(ts), dFdx(ts)), dot(dFdy(ts), dFdy(ts)))); diffuseColor.a = clamp(diffuseColor.a * (1. + max(lod - 1., 0.) * .3), 0., 1.); }\n#include <alphatest_fragment>`)
      // one field normal (straight up) for both faces: a flipped back-face normal lit every other card differently
      .replace('#include <normal_fragment_begin>', '#include <normal_fragment_begin>\n normal = normalize(vNormal); nonPerturbedNormal = normal;')
      .replace('#include <aomap_fragment>', '#include <aomap_fragment>\n reflectedLight.indirectDiffuse *= mix(.12, .4, vH); reflectedLight.indirectSpecular *= .05 * vH;')
      .replace('#include <lights_fragment_end>', '#include <lights_fragment_end>\n reflectedLight.directDiffuse *= smoothstep(.05, .75, vH);');
    translucencyGLSL(sh, { tint: [1.8, 1.2, .25], k: 1.5 });
  };
  m.customProgramCacheKey = () => 'hero-grass-cards';
  const mesh = new THREE.Mesh(geo, m); mesh.receiveShadow = true; mesh.castShadow = false; mesh.frustumCulled = false;
  return mesh;
}


/* ------------------------------------------------------------------ sunlit haze between the house and the viewer:
   a stack of soft vertical slabs, each adding a little Mie-scattered sunlight (strong only toward the sun), faded at
   the ground and with height, so the backlight fills the air instead of arriving as lens streaks. */
function hazeSlabs(U, cam, look, dists, sunC) {
  const f = new THREE.Vector3(look[0] - cam[0], 0, look[2] - cam[2]).normalize();
  const m = new THREE.ShaderMaterial({
    uniforms: Object.assign({ uSunC: { value: sunC }, uK: { value: 1 } }, U),
    transparent: true, depthWrite: false, blending: THREE.AdditiveBlending,
    vertexShader: `varying vec3 vW; void main(){ vec4 w = modelMatrix * vec4(position, 1.); vW = w.xyz; gl_Position = projectionMatrix * viewMatrix * w; }`,
    fragmentShader: `uniform vec3 uSun, uSunC; uniform float uK; varying vec3 vW;
      void main(){ vec3 v = normalize(vW - cameraPosition); float mu = dot(v, uSun);
        float g = .72, hg = (1. - g * g) / pow(1. + g * g - 2. * g * mu, 1.5) * .0035;       // Henyey-Greenstein, forward peak
        float h = vW.y, dens = smoothstep(0., 1.1, h) * exp(-h / 3.2);                     // soft at the ground, thin with height
        gl_FragColor = vec4(uSunC * (hg + .0015) * dens * uK, 1.); }`,
  });
  const group = new THREE.Group();
  for (const d of dists) {
    const pl = new THREE.Mesh(new THREE.PlaneGeometry(90, 14), m);
    pl.position.set(cam[0] + f.x * d, 7 - .5, cam[2] + f.z * d);
    pl.lookAt(cam[0], 6.5, cam[2]); pl.renderOrder = 5; pl.frustumCulled = false;
    group.add(pl);
  }
  return { group, m };
}

/* ------------------------------------------------------------------ scene */
export async function create(ctx) {
  const { env } = ctx;
  const scene = new THREE.Scene();
  const camera = new THREE.PerspectiveCamera(30, 1, .1, 6000);

  /* framing: desktop and mobile poses; a lens shift keeps verticals vertical */
  const POSE = {
    desk: { pos: qv('cam', [-14.5, 1.05, 31]), look: qv('look', [-6.4, 1.05, 0]), fov: qn('fov', 28), shift: qv('shift', [0, -.165]), sun: qv('sunxy', [.71, .265]), rays: qn('rays', .45) },
    mob: { pos: qv('mcam', [-7.5, 1.25, 41]), look: qv('mlook', [2.8, 1.25, -1]), fov: qn('mfov', 58), shift: qv('mshift', [0, -.19]), sun: qv('msunxy', [.7, .56]), rays: qn('mrays', .7) },
  };
  const base = POSE.desk;
  camera.position.set(...base.pos); camera.lookAt(...base.look); camera.updateMatrixWorld();

  /* sun: each pose places it on screen (fraction of the host) behind the cherry; solved into a world direction */
  const solveSun = (P, w, h) => {
    const c = new THREE.PerspectiveCamera(P.fov, w / h, .1, 100);
    c.position.set(...P.pos); c.lookAt(...P.look); c.updateMatrixWorld();
    c.setViewOffset(w, h, P.shift[0] * w, P.shift[1] * h, w, h); c.updateProjectionMatrix();
    const d = new THREE.Vector3(P.sun[0] * 2 - 1, -(P.sun[1] * 2 - 1), .5).unproject(c).sub(c.position).normalize();
    return { az: Math.atan2(d.z, d.x), el: Math.asin(d.y), dir: d };
  };
  const hostW = ctx.host.clientWidth || 1440, hostH = ctx.host.clientHeight || 900;
  let S0 = solveSun(hostW < 600 ? POSE.mob : POSE.desk, hostW, hostH);
  const sunDir = S0.dir;
  let sunAz = S0.az, sunEl = S0.el;
  const U = { uSun: { value: sunDir.clone() }, uSunK: { value: 1 }, uDusk: { value: 0 }, uCore: { value: qn('core', 900) }, uCam: { value: camera.position }, uTime: { value: 0 } };

  /* environment: the real sunset HDRI, its sun turned to ours */
  scene.environment = env.texture; scene.environmentIntensity = qn('envi', .45);
  const hdrAz = Math.atan2(.609, .793);
  const turnEnv = () => scene.environmentRotation.set(0, hdrAz - sunAz, 0);
  turnEnv();

  /* sky, hills */
  scene.add(skyDome(U));
  const fwdAz = Math.atan2(base.look[2] - base.pos[2], base.look[0] - base.pos[0]);
  const H = hills(U, new THREE.Vector3(base.pos[0], 0, base.pos[2]), fwdAz, rng(12));
  scene.add(H.group);

  /* near ground beyond the garden: dark meadow fading into haze */
  const groundMat = new THREE.MeshStandardMaterial({ color: new THREE.Color(.045, .042, .03), roughness: 1 });
  groundMat.onBeforeCompile = sh => {
    Object.assign(sh.uniforms, U);
    sh.vertexShader = sh.vertexShader.replace('#include <common>', '#include <common>\nvarying vec3 vW2;').replace('#include <worldpos_vertex>', '#include <worldpos_vertex>\n vW2 = (modelMatrix * vec4(transformed, 1.)).xyz;');
    sh.fragmentShader = sh.fragmentShader.replace('#include <common>', `#include <common>\n${SKY_GLSL}\nuniform vec3 uCam; varying vec3 vW2;`)
      .replace('#include <dithering_fragment>', `#include <dithering_fragment>
        { vec3 v = normalize(vW2 - uCam); float d = length(vW2 - uCam); float f = 1. - exp(-max(d - 35., 0.) / 90.);
          gl_FragColor.rgb = mix(gl_FragColor.rgb, skyCol(vec3(v.x, .01, v.z)) * .78, f); }`);
  };
  groundMat.customProgramCacheKey = () => 'hero-ground';
  const ground = new THREE.Mesh(new THREE.CircleGeometry(38, 64).rotateX(-Math.PI / 2), groundMat);
  ground.position.set(0, -.02, 0); ground.receiveShadow = true;
  const valley = new THREE.Mesh(new THREE.CircleGeometry(900, 64).rotateX(-Math.PI / 2), groundMat); valley.position.set(0, -26, 0); scene.add(valley);

  /* the house */
  const house = await buildHouse({ env, glow: qn('glow', .85), seed: 1 });
  scene.add(house.group);

  /* the cherry, kept clear of the roof */
  const TP = qv('tree', [8.8, -4.5]);
  const hb = house.bounds.clone().expandByScalar(.45), _p = new THREE.Vector3();
  const tree = await buildSakura({ seed: qn('tseed', 3), height: qn('th', 8.8), spread: qn('tspread', 1.25), avoid: p => hb.containsPoint(_p.copy(p).add(new THREE.Vector3(TP[0], 0, TP[1]))) });
  tree.group.position.set(TP[0], 0, TP[1]); tree.group.rotation.y = qn('trot', 0) * deg; scene.add(tree.group);

  /* the garden: gravel raked parallel to the engawa, moss banks, stones, path to the shoe stone, a tōrō, a pine */
  /* foreground bank height: low moss crests facing the viewer (the second only shows from the mobile pose) */
  const crest = (x, zc, h, z) => { const back = clamp((z - (zc - 2.6)) / 2.6), front = clamp((zc + 2.2 - z) / 2.2), t = Math.min(back, front); return h * (t < 1 && z > zc ? t * t : t * t * (3 - 2 * t)); };   // the near face drops steeper than the sun is high: it lies in the crest's shadow
  // the near crest follows the line that projects just above the stats strip in the desktop frame (solved from the camera)
  const cz1 = x => 24.05 + .26 * (x + 16) + .22 * Math.sin(x * .9 + 1) + .12 * Math.sin(x * 2.3);
  const hAt = (x, z) => Math.max(
    crest(x, cz1(x), .5 + .16 * Math.sin(x * .57 + 1.1) + .08 * Math.sin(x * 1.7), z),
    crest(x, 34.5 + .8 * Math.sin(x * .27 + 2.) + .4 * Math.sin(x * .9), .7 + .15 * Math.sin(x * .4 + .3), z)) - .03
    + .05 * Math.sin(x * 1.9 + z * 1.3) * Math.sin(x * .7 - z * 2.1) * Math.min(1, Math.max(0, z - 21) / 3);

  const GC = [1, 13];   // garden centre (world)
  const L = (x, z) => [x - GC[0], z - GC[1]];
  const garden = await buildGarden({
    seed: 4, size: [110, 100], glow: qn('lglow', .7), mossGround: true, court: [...L(-7.9, 3.55), ...L(8.5, 15.5)],
    path: [[-.9, 15.2], [-.2, 14.0], [-.8, 12.8], [-.1, 11.6], [.6, 10.4], [.1, 9.2], [.7, 8.0], [.2, 6.8], [.7, 5.6], [.1, 4.3]].map(p => L(...p)),
    rocks: [[-5.4, 8.6, 1.0, .3], [-4.1, 9.5, .52, 1.3], [-6.7, 7.6, .45, 2.2], [-2.6, 12.6, .38, .8]].map(([x, z, s, y]) => [...L(x, z), s, y]),
    lantern: L(...qv('lant', [1.9, 5.6])), pine: Q.has('nopine') ? null : [...L(...qv('pine', [-10.75, 9.5])), .6],
    moss: [[-9.6, 5.2, 2.2, 1.3], [-12.5, 12.5, 3.2, 2.0], [-10.2, 9.5, 1.8, 1.4]].map(([x, z, a, b]) => [...L(x, z), a, b]),
    shrubs: [[-7.9, 4.3, .75, .5, .6], [-6.9, 4.9, .5, .38, .45], [-12.6, 4.2, .7, .45, .55], [-15.6, 10.5, .9, .5, .7], [-14.8, 11.4, .55, .35, .45]].map(([x, z, a, b, c]) => [...L(x, z), a, b, c]),
    edge: [L(...qv('he0', [-10.5, -3])), L(...qv('he1', [-24, 22]))],
    hedge: [L(6.8, 1.6), L(19, -1.2), 1.05, .9],
    shape: (x, z, y) => {       // garden-local: the land beyond the garden drops away behind and right of the house
      const wx = x + GC[0], wz = z + GC[1], d = Math.max(-wz - 9, wx - 22, 0);
      return y - Math.min(9, d * d * .05 + d * .15);
    },
  });
  garden.group.position.set(GC[0], 0, GC[1]); scene.add(garden.group);
  garden.mossMaterial.color.setScalar(.25);   // the hero keeps its turf in deep evening shade (≈ 3 % albedo) under the stats
  // far ground hazes toward the sky along the view ray (same haze as the meadow), so the land never ends on a hard line
  {
    const m = garden.mossMaterial, prev = m.onBeforeCompile;
    m.onBeforeCompile = (sh, r) => {
      prev?.(sh, r); Object.assign(sh.uniforms, U);
      sh.vertexShader = sh.vertexShader.replace('#include <common>', '#include <common>\nvarying vec3 vHz;').replace('#include <worldpos_vertex>', '#include <worldpos_vertex>\n vHz = (modelMatrix * vec4(transformed, 1.)).xyz;');
      sh.fragmentShader = sh.fragmentShader.replace('#include <common>', `#include <common>\n${SKY_GLSL}\nuniform vec3 uCam; varying vec3 vHz;`)
        .replace('#include <dithering_fragment>', `#include <dithering_fragment>
          { vec3 v = normalize(vHz - uCam); float d = length(vHz - uCam); float f = 1. - exp(-max(d - 30., 0.) / 70.);
            gl_FragColor.rgb = mix(gl_FragColor.rgb, skyCol(vec3(v.x, .01, v.z)) * .72, f); }`);
    };
    const key = m.customProgramCacheKey; m.customProgramCacheKey = () => key() + ':hz';
  }

  /* foreground bank mesh */
  {
    const seg = 170, rows = 60, pos = [], idx = [];
    const x0 = -30, x1 = 16, z0 = 19, z1 = 52;
    for (let j = 0; j <= rows; j++) for (let i = 0; i <= seg; i++) { const x = lerp(x0, x1, i / seg), z = lerp(z0, z1, j / rows); pos.push(x, hAt(x, z), z); }
    for (let j = 0; j < rows; j++) for (let i = 0; i < seg; i++) { const a = j * (seg + 1) + i, b = a + 1, c = a + seg + 1, d = c + 1; idx.push(a, c, b, b, c, d); }
    const g = new THREE.BufferGeometry(); g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3)); g.setIndex(idx); g.computeVertexNormals();
    paint(g, [1, 1, 1], (x, y, z, nx, ny, nz) => clamp(.42 + .5 * clamp(1 - Math.max(0, z - cz1(x)) / 2.5) * ny - .1 * Math.max(0, nz)));   // the slope toward the viewer sees little sky
    const bank = new THREE.Mesh(g, garden.mossMaterial); bank.receiveShadow = true; bank.castShadow = true; scene.add(bank);   // the crest shades its own near slope: the stats band sits in shadow
    // meadow tufts over the whole foreground band, screen-uniform: dense near the camera, sparser (and bigger) far away
    const RB = rng(4242), cams = [POSE.desk.pos, POSE.mob.pos], list = [];
    const Cw = garden.court.map((v, i) => v + (i % 2 ? GC[1] : GC[0]));   // court in world
    const step = .22, dens = qn('grass', 1);
    for (let z = 3; z < 44; z += step) for (let x = -30; x < 16; x += step) {
      const px = x + RB() * step, pz = z + RB() * step;
      if (px > Cw[0] - .15 && px < Cw[2] + .15 && pz > Cw[1] - .15 && pz < Cw[3] + .15) { RB(); continue; }   // the gravel court
      if (px > -6.2 && px < 6.2 && pz < 3.6) { RB(); continue; }                                               // house, engawa, drip line
      let d = 1e9; for (const c of cams) d = Math.min(d, Math.hypot(px - c[0], pz - c[2]));
      const p = dens * 26 * (7 / Math.max(d, 5)) ** 2 * step * step;
      if (RB() > p) continue;
      const gy = garden.heightAt(px - GC[0], pz - GC[1]), y = Math.max(gy, pz > 19 && px > -30 && px < 16 ? hAt(px, pz) : -9);
      if (y < -.25) continue;                                                                                   // past the terrace edge
      const sc = clamp(d / 8, 1, 2.6), w = .34 * sc * (.8 + RB() * .4), h = .16 * Math.sqrt(sc) * (.7 + RB() * .6);
      const yaw = RB() * Math.PI, cell = (RB() * 4) | 0, tone = .75 + RB() * .4;
      list.push([px, y, pz, w, h, yaw, cell, tone], [px, y, pz, w * .85, h * .9, yaw + Math.PI / 2, (cell + 1) % 4, tone * .95]);   // crossed pair: full from every angle
    }
    const grass = grassCards(list, U); scene.add(grass);
    if (Q.has('debug')) console.log('grass cards', list.length);
  }

  /* the sun: one warm key with soft PCF shadows fitted to the garden, frozen until the light moves */
  const sun = new THREE.DirectionalLight(new THREE.Color(1, .66, .38), qn('sun', 7.5));
  sun.castShadow = true; sun.shadow.mapSize.set(4096, 4096);
  sun.shadow.bias = -.0003; sun.shadow.normalBias = .035; sun.shadow.radius = 2.5;
  sun.shadow.autoUpdate = false;
  scene.add(sun, sun.target);
  const fitBox = new THREE.Box3(new THREE.Vector3(-30, -1, -9), new THREE.Vector3(18, 11, 40));
  // light bounced off the sunlit ground: warm, from below, strongest on soffits and the shaded facade's lower half
  const bounce = new THREE.HemisphereLight(new THREE.Color(.62, .52, .86).multiplyScalar(qn('skyfill', .55)), new THREE.Color(1, .6, .36).multiplyScalar(qn('bounce', .9)), 1);
  scene.add(bounce);
  const setSun = (az, el) => {
    const d = new THREE.Vector3(Math.cos(az) * Math.cos(el), Math.sin(el), Math.sin(az) * Math.cos(el));
    U.uSun.value.copy(d);
    const c = fitBox.getCenter(new THREE.Vector3());
    sun.target.position.copy(c); sun.position.copy(c).addScaledVector(d, 80);
    sun.updateMatrixWorld(); sun.target.updateMatrixWorld();
    // fit the ortho frustum to the box in light space
    const sc = sun.shadow.camera; sc.position.copy(sun.position); sc.lookAt(c); sc.updateMatrixWorld();
    const inv = sc.matrixWorldInverse, bb = new THREE.Box3();
    for (let i = 0; i < 8; i++) bb.expandByPoint(new THREE.Vector3(i & 1 ? fitBox.max.x : fitBox.min.x, i & 2 ? fitBox.max.y : fitBox.min.y, i & 4 ? fitBox.max.z : fitBox.min.z).applyMatrix4(inv));
    sc.left = bb.min.x; sc.right = bb.max.x; sc.bottom = bb.min.y; sc.top = bb.max.y; sc.near = -bb.max.z - 40; sc.far = -bb.min.z + 5;
    sc.updateProjectionMatrix();
    sun.shadow.needsUpdate = true;
  };
  setSun(sunAz, sunEl);
  tree.setSun(U.uSun.value);
  house.setRim(qn('rim', 1.6), 3.2); garden.setRim(qn('rim', 1.6), 3.2); tree.setRim(qn('rim', 1.6) * 1.2, 2.2);
  garden.mossMaterial.userData.rim.value.set(0, 3);   // turf is seen at grazing angles everywhere: its crest glow comes from the backlit blade fringe instead

  /* sunlit haze in the air between the house and the camera */
  const haze = hazeSlabs(U, POSE.desk.pos, POSE.desk.look, [11, 14, 17, 20, 23, 26], new THREE.Color(1, .72, .45).multiplyScalar(qn('haze', .6)));
  scene.add(haze.group);

  /* petals drifting off the cherry across the garden */
  const pbox = new THREE.Box3(new THREE.Vector3(TP[0] - 16, 0, TP[1] - 4), new THREE.Vector3(TP[0] + 5, 9, TP[1] + 26));
  const petals = petalField(U, 1000, pbox); scene.add(petals.mesh);

  /* anchors */
  const battPt = house.anchors.battery.getWorldPosition(new THREE.Vector3()).add(new THREE.Vector3(0, -.42, 0));   // chip hangs on the cabinet face
  const anchors = { produced: house.anchors.roof, battery: battPt, grid: house.anchors.meter };

  const sunPos = new THREE.Vector3();
  const post = {
    exposure: qn('exp', 1), tone: 'aces', hue: .45, sat: 1.05, contrast: 1.05, vignette: .2, grain: .02,
    lift: qv('lift', [.02, .0155, .027]), shadowTint: [.95, .93, 1.07], highTint: [1.03, 1, .95],
    bloom: { strength: qn('bloom', .26), radius: .75, threshold: qn('bth', 16), knee: 4 },
    rays: Q.has('norays') ? null : { sun: sunPos, strength: qn('rays', 1.1), tint: [1, .86, .7], density: qn('rden', .5), decay: .95, weight: .03, threshold: qn('rth', 7), falloff: qn('rfall', 3) },
  };

  /* motion state */
  const cam = { yaw: 0, pitch: 0, lift: 0 };
  const _t = new THREE.Vector3(), _q = new THREE.Vector3();
  let lastSunEl = sunEl, mobile = hostW < 600, poseKey = '';
  if (Q.has('debug')) window.__hero = { camera, U, house, tree, garden, sun, scene };
  const obj = {
    scene, camera, post, anchors,
    anchorOn() { return !mobile; },   // the phone layout has no room for the chips beside the copy
    update(dt, t, s) {
      mobile = s.w < 600;
      const P = mobile ? POSE.mob : POSE.desk;
      const key = `${mobile}:${Math.round(s.w / 40)}:${Math.round(s.h / 40)}`;
      if (key !== poseKey) { poseKey = key; const S = solveSun(P, s.w, s.h); sunAz = S.az; sunEl = S.el; turnEnv(); lastSunEl = 1e9; tree.setSun(S.dir); }
      if (camera.fov !== P.fov) { camera.fov = P.fov; camera.updateProjectionMatrix(); }
      const v = camera.view;
      if (!v || v.fullWidth !== s.w || v.fullHeight !== s.h || v.offsetY !== P.shift[1] * s.h || v.offsetX !== P.shift[0] * s.w) camera.setViewOffset(s.w, s.h, P.shift[0] * s.w, P.shift[1] * s.h, s.w, s.h);
      const leave = smooth(.5, 1, s.progress);                 // scrolling away: camera lifts, the sun sinks
      const still = REDUCED;
      cam.yaw = damp(cam.yaw, still ? 0 : clamp(s.pointer.x, -1, 1) * -1.4 * deg, 3, dt);
      cam.pitch = damp(cam.pitch, still ? 0 : clamp(s.pointer.y, -1, 1) * .7 * deg, 3, dt);
      cam.lift = damp(cam.lift, leave, 6, dt);
      const breathe = still ? 0 : 1;
      _t.set(...P.look);
      _q.set(...P.pos).sub(_t);
      _q.applyAxisAngle(new THREE.Vector3(0, 1, 0), cam.yaw + Math.sin(t * .13) * .25 * deg * breathe);
      _q.y += Math.sin(t * .21) * .06 * breathe + cam.pitch * _q.length() * .6 + cam.lift * 2.2;
      camera.position.copy(_t).add(_q);
      camera.lookAt(_t.x, _t.y + cam.lift * 1.1, _t.z);
      // light deepens as the hero leaves
      const el = sunEl - leave * 3.4 * deg;
      if (Math.abs(el - lastSunEl) > .12 * deg) { setSun(sunAz, el); lastSunEl = el; }        // frozen shadow, re-baked in small steps
      U.uDusk.value = leave * .55; U.uSunK.value = 1 - leave * .35;
      sun.intensity = qn('sun', 7.5) * (1 - leave * .45);
      sun.color.setRGB(1, .66 - leave * .16, .38 - leave * .14);
      scene.environmentIntensity = qn('envi', .45) * (1 - leave * .3);
      house.setGlow(qn('glow', .85) + leave * .5); garden.setGlow(qn('lglow', .7) + leave * .6);
      sunPos.copy(U.uSun.value).multiplyScalar(2000).add(camera.position);
      if (this.post.o) { this.post.o.exposure = qn('exp', 1) * (1 - leave * .12); if (this.post.o.rays) this.post.o.rays.strength = P.rays * (1 - leave * .3); }
      // petals + wind
      const wind = .8 + .35 * Math.sin(t * .37) + .15 * Math.sin(t * 1.1);
      tree.update(t, still ? 0 : wind); U.uTime.value = still ? 0 : t;
      petals.m.uniforms.uT.value = still ? 11 : t;
      petals.m.uniforms.uSunC.value.copy(sun.color).multiplyScalar(sun.intensity * .12);
      petals.m.uniforms.uAmb.value.setRGB(.46, .3, .36).multiplyScalar(1 - leave * .3);
    },
  };
  return obj;
}
