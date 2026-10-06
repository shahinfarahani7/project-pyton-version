/* How it works (pinned 330vh): a garden plot lifted out of the earth on a dry-laid ishigaki base, floating in a dusk
   void, carrying the Sunset house, a sakura and its karesansui. One colour script runs down the pin:
   golden sunset (p 0–.4) → the sun goes down (.4–.52) → blue hour (.52–.72, the CTA's palette) → night (.75–1).
   01 Check    (0–.33)   a hairline survey grid sweeps down the roof and inks the panel positions onto the tiles.
   02 Install  (.33–.66) the outlines lift away; the panels arrive one by one on low arcs from the sunlit side.
   03 Power on (.66–1)   the shoji warm from ~.6, the lantern lights, the battery gauge fills, a pulse runs down the
                         gable into the cabinet, stars come out and the moon takes over the key light.
   The visible glow behind the plot is the key light (world-fixed, behind-right): faces toward the camera get only
   cool sky fill. The camera orbits ~22° and eases closer each chapter; the plot sits in the right 60 % (desktop)
   or in a band above the copy (mobile). */
import { THREE, rng, clamp, lerp, damp, smooth, inv, E, REDUCED } from '../core.js';

const V3 = (x = 0, y = 0, z = 0) => new THREE.Vector3(x, y, z);
const TILE = { x0: -8.6, x1: 8.6, z0: -6.2, z1: 7.9, base: 1.7, batter: .7, rc: .6 };
const CLOUD_Y = -2.25;
const ADD = { transparent: true, depthWrite: false, blending: THREE.CustomBlending, blendEquation: THREE.AddEquation,
  blendSrc: THREE.OneFactor, blendDst: THREE.OneFactor, blendSrcAlpha: THREE.ZeroFactor, blendDstAlpha: THREE.OneFactor };
const OVER = { transparent: true, depthWrite: false, blending: THREE.CustomBlending, blendEquation: THREE.AddEquation,
  blendSrc: THREE.OneFactor, blendDst: THREE.OneMinusSrcAlphaFactor, blendSrcAlpha: THREE.OneFactor, blendDstAlpha: THREE.OneMinusSrcAlphaFactor };

/* ------------------------------------------------------------------ shared: sky colours, calm mask over the copy column */
const SKYCOMMON = /* glsl */`
uniform vec3 uHorSun, uHorAway, uZen, uSunCol, uSunDirV; uniform float uHorEl, uCalmX, uCalmY, uResX, uResY;
float h21(vec2 p){ vec3 p3 = fract(vec3(p.xyx) * .1031); p3 += dot(p3, p3.yzx + 33.33); return fract((p3.x + p3.y) * p3.z); }
float n2(vec2 p){ vec2 i = floor(p), f = fract(p); f = f * f * (3. - 2. * f); return mix(mix(h21(i), h21(i + vec2(1,0)), f.x), mix(h21(i + vec2(0,1)), h21(i + vec2(1,1)), f.x), f.y); }
float calm(){ vec2 s = gl_FragCoord.xy / vec2(uResX, uResY);                    // 0 over the copy, 1 over the scene
  return uCalmX > 0. ? mix(.26, 1., smoothstep(uCalmX - .16, uCalmX + .14, s.x)) * smoothstep(-.05, .12, s.x) : smoothstep(uCalmY - .14, uCalmY + .05, s.y); }
vec3 skyAt(vec3 d){
  float el = asin(clamp(d.y, -1., 1.)) - uHorEl;                                   // elevation above the cloud horizon
  float tw = dot(normalize(d.xz + vec2(1e-5)), normalize(uSunDirV.xz + vec2(1e-5))) * .5 + .5;
  vec3 hor = mix(uHorAway, uHorSun, pow(tw, 2.5));
  vec3 c = mix(hor, uZen, smoothstep(0., .13, max(el, 0.)));
  c += uSunCol * .3 * exp(-max(el, 0.) / .03) * pow(tw, 8.);                     // the band of light on the horizon under the sun
  return c;
}`;

/* the sky behind the plot: a gradient down to the cloud horizon, the sun disc setting into it, stars and a moon at night */
const VOID_FS = /* glsl */`
uniform vec3 uMoonDir; uniform float uNight, uTime, uSunK, uMoon;
varying vec3 vDir;
${SKYCOMMON}
void main(){
  vec3 d = normalize(vDir);
  vec3 c = skyAt(d);
  float r = acos(clamp(dot(d, uSunDirV), -1., 1.));
  float above = smoothstep(-.002, .004, asin(clamp(d.y, -1., 1.)) - uHorEl);        // the cloud sea hides the lower limb
  c += uSunCol * (exp(-r / .02) * .9 + exp(-r / .07) * .25) * uSunK * above;
  c += uSunCol * 7. * smoothstep(.0115, .0095, r) * uSunK * above;
  // stars
  float el = asin(clamp(d.y, -1., 1.)), az = atan(d.x, -d.z);
  vec2 g = vec2(az * cos(el), el) / .016;
  vec2 cell = floor(g), f = fract(g) - .5;
  float h = h21(cell), h2 = h21(cell + 17.3);
  vec2 o = vec2(h21(cell + 3.7), h21(cell + 9.1)) - .5;
  float st = step(.935, h) * (.2 + .8 * h2 * h2 * h2) * smoothstep(.06, .015, length(f - o * .7));
  st *= (.7 + .3 * sin(uTime * (1. + h2 * 2.5) + h * 40.)) * smoothstep(.02, .12, el - uHorEl);
  float sx = gl_FragCoord.x / uResX;
  c += vec3(.8, .84, 1.) * st * 1.2 * uNight * (uCalmX > 0. ? smoothstep(uCalmX - .02, uCalmX + .1, sx) : 1.);   // no stars over the copy
  // a young moon
  float mr = acos(clamp(dot(d, uMoonDir), -1., 1.));
  vec3 mu = normalize(cross(uMoonDir, vec3(0., 1., 0.))), mv = cross(mu, uMoonDir);
  vec2 mp = vec2(dot(d, mu), dot(d, mv)) / .0085;
  float disc = smoothstep(1., .86, length(mp)) * step(0., dot(d, uMoonDir));
  float lit = smoothstep(0., .12, length(mp + vec2(.55, -.25)) - .88);
  c += (vec3(.45, .5, .72) * exp(-mr / .05) * .06 + disc * mix(vec3(.03, .035, .06), vec3(3.2, 3.1, 2.9), lit)) * uMoon;
  float a = calm();
  gl_FragColor = vec4(c * a, a);
}`;

/* the sea of clouds under the plot: billows lit by the key light, hazing into the horizon colour at the rim */
const CLOUD_FS = /* glsl */`
uniform vec3 uKeyDir, uKeyCol, uFill, uTileMin, uTileMax; uniform float uTime, uRim;
varying vec3 vW;
${SKYCOMMON}
float bill(vec2 p){ return n2(p) * .55 + n2(p * 2.07 + 5.3) * .3 + n2(p * 4.3 + 1.7) * .15; }
void main(){
  vec2 p = vW.xz / 11. + vec2(uTime * .004, uTime * .0015);
  float e = .04, h0 = bill(p), hx = bill(p + vec2(e, 0.)), hz = bill(p + vec2(0., e));
  vec3 n = normalize(vec3(-(hx - h0) / e * .5, 1., -(hz - h0) / e * .5));
  vec3 V = normalize(cameraPosition - vW);
  float dist = length(cameraPosition.xz - vW.xz);
  float lam = clamp(dot(n, uKeyDir) * .6 + .4, 0., 1.);
  float fwd = pow(max(dot(-V, uKeyDir), 0.), 6.);
  float tops = smoothstep(.4, .7, h0);
  vec3 c = uFill * (.55 + .55 * tops) + uKeyCol * (lam * tops + fwd * .5) * .55;
  // the plot's shadow falls on the clouds (soft, offset away from the key light)
  vec2 sh = vW.xz + uKeyDir.xz / max(uKeyDir.y, .15) * (vW.y - .0) * -1.;
  vec2 dq = max(max(uTileMin.xz - sh, sh - uTileMax.xz), 0.);
  c *= 1. - .3 * exp(-length(dq) / 2.4) * smoothstep(.02, .1, uKeyDir.y) * smoothstep(.3, .05, dot(uKeyCol, vec3(.33)) < .01 ? 1. : 0.);
  c *= 1. - .35 * exp(-length(max(max(uTileMin.xz - vW.xz, vW.xz - uTileMax.xz), 0.)) / .9);   // contact darkening under the base
  float haze = pow(smoothstep(.5, 1., dist / uRim), 1.8);
  c = mix(c, skyAt(normalize(vec3(vW.x - cameraPosition.x, 0., vW.z - cameraPosition.z)) * vec3(1., 0., 1.) + vec3(0., sin(uHorEl) + .001, 0.)), haze);
  float a = calm();
  gl_FragColor = vec4(c * a, a);
}`;

/* ------------------------------------------------------------------ roof survey: washi-white hairline outlines with corner ticks, drawn on */
const SURVEY_FS = /* glsl */`
uniform float uSweep, uFade, uOut, uW, uL, uPW, uPH; uniform vec2 uPan[18]; uniform float uDraw[18]; uniform vec3 uInk;
varying vec2 vP;
void main(){
  float x = vP.x, s = vP.y;
  float px = length(fwidth(vP)) * .7;
  float front = uSweep * (uL + .3);
  float scan = (1. - smoothstep(px * .25, px * .9, abs(s - front))) * step(front, uL) * step(.001, uSweep) * .45;
  float edge = smoothstep(0., .5, x + uW * .5) * smoothstep(0., .5, uW * .5 - x);
  float a = scan * edge * uFade;
  float rect = 0.;
  for (int k = 0; k < 18; k++) {
    vec2 c = uPan[k]; if (c.x > 1e3) continue;
    vec2 p = vec2(x, s) - c, hsz = vec2(uPW, uPH) * .5 - .025;
    vec2 dq = abs(p) - hsz;
    // corner ticks: short marks beyond each corner, along both edges
    vec2 ap = abs(p);
    float tickL = .12, tw = px * .9;
    float tick = max((1. - smoothstep(tw * .3, tw, abs(ap.y - hsz.y))) * step(hsz.x, ap.x) * step(ap.x, hsz.x + tickL),
                     (1. - smoothstep(tw * .3, tw, abs(ap.x - hsz.x))) * step(hsz.y, ap.y) * step(ap.y, hsz.y + tickL));
    float dd = max(dq.x, dq.y);
    if (abs(dd) > .15 && tick == 0.) continue;
    float per = 4. * (hsz.x + hsz.y), t;
    if (abs(dq.y) < abs(dq.x)) t = p.y < 0. ? (p.x + hsz.x) : 2. * hsz.x + 2. * hsz.y + (hsz.x - p.x);
    else t = p.x > 0. ? 2. * hsz.x + (p.y + hsz.y) : 4. * hsz.x + 2. * hsz.y + (hsz.y - p.y);
    float on = step(t / per, uDraw[k]);
    float ln = (1. - smoothstep(px * .3, px * .9, abs(dd))) * step(dd, .001) * on;
    rect = max(rect, max(ln, tick * step(.02, uDraw[k])));
  }
  a = max(a, rect * .4 * uOut);
  if (a < .003) discard;
  gl_FragColor = vec4(uInk * a, a);
}`;

/* ------------------------------------------------------------------ ishigaki: ONE lofted wall round the whole plot.
   The plan is a rounded rectangle; the profile is musha-gaeshi (vertical at the top, flaring out toward the foot).
   Four wandering courses of irregular knapped blocks, each pillowed out of the wall with deep dark joints (vertex AO),
   long corner stones. Stone relief is real geometry, so the key light rakes across it. */
function ishigakiGeometry() {
  const T = TILE, H = T.base, B = T.batter, RC = T.rc, STEP = .034, COURSES = 4;
  const hsh = (i, j) => { let n = (i * 374761393 + j * 668265263) | 0; n = Math.imul(n ^ (n >>> 13), 1274126177); return ((n ^ (n >>> 16)) >>> 0) / 4294967296; };
  // perimeter of the top rounded rectangle, sampled by arc length: position + outward normal
  const W = T.x1 - T.x0 - 2 * RC, D = T.z1 - T.z0 - 2 * RC, P = 2 * (W + D) + 2 * Math.PI * RC;
  const cx0 = T.x0 + RC, cx1 = T.x1 - RC, cz0 = T.z0 + RC, cz1 = T.z1 - RC;
  const at = u => {                          // u in [0, P): front edge left->right, right edge, back edge, left edge
    u = ((u % P) + P) % P;
    const q = Math.PI * RC / 2, segs = [[W, 'f'], [q, 'c1'], [D, 'r'], [q, 'c2'], [W, 'b'], [q, 'c3'], [D, 'l'], [q, 'c0']];
    for (const [len, id] of segs) {
      if (u <= len) {
        const t = u / len;
        if (id === 'f') return [cx0 + W * t, T.z1, 0, 1];
        if (id === 'r') return [T.x1, cz1 - D * t, 1, 0];
        if (id === 'b') return [cx1 - W * t, T.z0, 0, -1];
        if (id === 'l') return [T.x0, cz0 + D * t, -1, 0];
        const a0 = { c1: 0, c2: -Math.PI / 2, c3: Math.PI, c0: Math.PI / 2 }[id] + (id === 'c3' ? 0 : 0);
        const cc = { c1: [cx1, cz1], c2: [cx1, cz0], c3: [cx0, cz0], c0: [cx0, cz1] }[id];
        const start = { c1: Math.PI / 2, c2: 0, c3: -Math.PI / 2, c0: Math.PI }[id];
        const ang = start - t * Math.PI / 2;
        const nx = Math.cos(ang), nz = Math.sin(ang);
        return [cc[0] + nx * RC, cc[1] + nz * RC, nx, nz];
      }
      u -= len;
    }
    return [cx0, T.z1, 0, 1];
  };
  const corners = [W, W + Math.PI * RC / 2 + D, 2 * W + Math.PI * RC + D, 2 * (W + D) + 1.5 * Math.PI * RC].map(v => v + Math.PI * RC / 4);   // mid-arc of each corner
  // stone field on (u, v): v = height from the foot
  const courseH = H / COURSES;
  const field = (u, v) => {
    const wav = .1 * Math.sin(u * .7 + 1.3) + .06 * Math.sin(u * 1.9 + .4) + .03 * Math.sin(u * 4.1 + 2.);
    const cv = v + wav, c = Math.max(0, Math.min(COURSES - 1, Math.floor(cv / courseH))), inC = cv - c * courseH;
    // blocks in this course: lengths .6..1.4 m; the stones that straddle a corner are long, alternating side by course
    let edgeV = Math.min(inC, courseH - inC);
    let dc = 1e9, near = 0; for (const cu of corners) { const d = Math.abs(((u - cu + P / 2) % P + P) % P - P / 2); if (d < dc) { dc = d; near = cu; } }
    let s0, s1, id;
    if (dc < .95) { const sh = (c % 2 ? .5 : -.5); s0 = near - .95 + sh * .4; s1 = near + .95 + sh * .4; id = (near * 97 + c) | 0; }
    else {
      let s = -hsh(c, 11) * 1.2, k = 0; const uu = ((u % P) + P) % P;
      while (true) { const len = .6 + .8 * hsh(c, k); if (s + len > uu) { s0 = s; s1 = s + len; id = c * 1000 + k; break; } s += len; k++; if (k > 400) { s0 = s; s1 = s + 1; id = k; break; } }
      // joints lean a little
      const lean = (hsh(id, 5) - .5) * .25 * (inC - courseH / 2);
      s0 += lean; s1 += lean;
      edgeV = Math.min(edgeV, uu - s0, s1 - uu);
      if (hsh(id, 7) < .5) {                                                        // some blocks are two stones stacked, split on a slant
        const hs = (.3 + .4 * hsh(id, 8)) * courseH + (uu - s0) * (hsh(id, 9) - .5) * .35, dv = inC - hs;
        edgeV = Math.min(edgeV, Math.abs(dv)); id = id * 2 + (dv > 0 ? 1 : 0);
      }
      return [Math.max(0, edgeV), id, c];
    }
    const uu = ((u - near + P / 2) % P + P) % P - P / 2 + near;
    edgeV = Math.min(edgeV, uu - s0, s1 - uu);
    return [Math.max(0, edgeV), id, c];
  };
  const NU = Math.ceil(P / STEP), NV = Math.ceil(H / STEP);
  const pos = new Float32Array((NU + 1) * (NV + 1) * 3), col = new Float32Array((NU + 1) * (NV + 1) * 3), ao = new Float32Array((NU + 1) * (NV + 1)), uv = new Float32Array((NU + 1) * (NV + 1) * 2);
  let vi = 0;
  for (let j = 0; j <= NV; j++) {
    const v = j * H / NV, y = -H + v, k = 1 - v / H;                               // k: 0 at the top .. 1 at the foot
    const out = B * Math.pow(k, 2.2);                                               // musha-gaeshi: vertical at the top, flaring at the foot
    for (let i = 0; i <= NU; i++) {
      const u = i * P / NU;
      const [px, pz, nx, nz] = at(u);
      const [ed, id, c] = field(u, v);
      const r1 = hsh(id, 1), r2 = hsh(id, 2);
      const topK = Math.min(1, (H - v) / .06), footK = Math.min(1, v / .05);
      const pillow = (.02 + .065 * r1) * Math.pow(Math.min(1, ed / .16), .55) - .035 * (1 - Math.min(1, ed / .022));
      const bump = (hsh(Math.floor(u * 9), Math.floor(v * 9) + id) - .5) * .006;
      const d = out + (pillow + bump) * topK * footK;
      pos[vi * 3] = px + nx * d; pos[vi * 3 + 1] = y; pos[vi * 3 + 2] = pz + nz * d;
      const t = .62 + .55 * r2, warm = (r1 - .5) * .14, joint = Math.min(1, ed / .03);
      col[vi * 3] = t * (1 + warm) * (.35 + .65 * joint); col[vi * 3 + 1] = t * (.35 + .65 * joint); col[vi * 3 + 2] = t * (1 - warm * .6) * (.35 + .65 * joint);
      ao[vi] = (.25 + .75 * joint) * (1 - .3 * Math.exp(-v / .3));
      uv[vi * 2] = u; uv[vi * 2 + 1] = y;
      vi++;
    }
  }
  const idx = [];
  for (let j = 0; j < NV; j++) for (let i = 0; i < NU; i++) { const a = j * (NU + 1) + i, b = a + 1, c2 = a + NU + 1, d2 = c2 + 1; idx.push(a, b, c2, b, d2, c2); }
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.BufferAttribute(pos, 3)); g.setAttribute('color', new THREE.BufferAttribute(col, 3));
  g.setAttribute('ao', new THREE.BufferAttribute(ao, 1)); g.setAttribute('uv', new THREE.BufferAttribute(uv, 2));
  g.setIndex(idx); g.computeVertexNormals();
  return g;
}

export async function create(ctx) {
  const { renderer, env, VP } = ctx;
  const scene = new THREE.Scene();
  const camera = new THREE.PerspectiveCamera(25, 16 / 9, .5, 900);
  const R = rng(31);

  /* ------------------------------------------------------------ sky behind the plot, sea of clouds under it (shared uniforms) */
  const sunDirV = V3(0, 0, -1), moonDir = V3(-.4, .5, -.8).normalize();
  const skyU = { uHorSun: { value: new THREE.Color() }, uHorAway: { value: new THREE.Color() }, uZen: { value: new THREE.Color() }, uSunCol: { value: new THREE.Color() },
    uSunDirV: { value: sunDirV }, uHorEl: { value: -.3 }, uCalmX: { value: .5 }, uCalmY: { value: -1 }, uResX: { value: 1 }, uResY: { value: 1 } };
  const voidU = { ...skyU, uMoonDir: { value: moonDir }, uNight: { value: 0 }, uTime: { value: 0 }, uSunK: { value: 1 }, uMoon: { value: 0 } };
  const voidMesh = new THREE.Mesh(new THREE.SphereGeometry(500, 48, 24), new THREE.ShaderMaterial({
    uniforms: voidU, side: THREE.BackSide, depthWrite: false,
    vertexShader: 'varying vec3 vDir; void main(){ vec4 w = modelMatrix * vec4(position, 1.); vDir = w.xyz - cameraPosition; gl_Position = projectionMatrix * viewMatrix * w; gl_Position.z = gl_Position.w; }',
    fragmentShader: VOID_FS,
  }));
  voidMesh.frustumCulled = false; voidMesh.renderOrder = -10; scene.add(voidMesh);
  const cloudU = { ...skyU, uKeyDir: { value: V3(0, 1, 0) }, uKeyCol: { value: new THREE.Color() }, uFill: { value: new THREE.Color() }, uTime: voidU.uTime, uRim: { value: 80 },
    uTileMin: { value: V3(TILE.x0 - TILE.batter, 0, TILE.z0 - TILE.batter) }, uTileMax: { value: V3(TILE.x1 + TILE.batter, 0, TILE.z1 + TILE.batter) } };
  const clouds = new THREE.Mesh(new THREE.CircleGeometry(1, 96).rotateX(-Math.PI / 2), new THREE.ShaderMaterial({
    uniforms: cloudU,
    vertexShader: 'varying vec3 vW; void main(){ vec4 w = modelMatrix * vec4(position, 1.); vW = w.xyz; gl_Position = projectionMatrix * viewMatrix * w; }',
    fragmentShader: CLOUD_FS,
  }));
  clouds.frustumCulled = false; clouds.renderOrder = -5; clouds.position.y = CLOUD_Y; scene.add(clouds);

  /* ------------------------------------------------------------ one environment, re-baked as the colour script moves */
  const SUN_AZ = Math.atan2(.85, -.55);                          // right and a little behind the plot as the camera sees it
  const sunDir = V3();
  const envU = { uSun: { value: sunDir }, uHorSun: { value: new THREE.Color() }, uHorAway: { value: new THREE.Color() }, uZen: { value: new THREE.Color() }, uGlowC: { value: new THREE.Color() } };
  const envScene = new THREE.Scene();
  envScene.add(new THREE.Mesh(new THREE.SphereGeometry(50, 48, 24), new THREE.ShaderMaterial({ uniforms: envU, side: THREE.BackSide, depthWrite: false,
    vertexShader: 'varying vec3 vD; void main(){ vD = position; gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.); }',
    fragmentShader: `uniform vec3 uSun, uHorSun, uHorAway, uZen, uGlowC; varying vec3 vD;
      void main(){ vec3 d = normalize(vD); float e = max(d.y, 0.);
        float tw = dot(normalize(d.xz + vec2(1e-5)), normalize(uSun.xz + vec2(1e-5))) * .5 + .5;
        vec3 c = mix(mix(uHorAway, uHorSun, pow(tw, 2.)), uZen, smoothstep(0., .55, e));
        c += uGlowC * exp(-acos(clamp(dot(d, uSun), -1., 1.)) / .3);
        c = mix(c, mix(uHorAway, uHorSun, pow(tw, 2.)) * .55, smoothstep(.0, -.12, d.y));      // the sea of clouds below
        gl_FragColor = vec4(c, 1.); }` })));
  const pmg = new THREE.PMREMGenerator(renderer);
  let envRT = null, envKey = -1;
  const bakeEnv = () => { const old = envRT; envRT = pmg.fromScene(envScene, 0, .1, 100); scene.environment = envRT.texture; old?.dispose(); };

  /* ------------------------------------------------------------ models */
  const [HM, SM, GM] = (await Promise.allSettled([import('../models/house.js'), import('../models/sakura.js'), import('../models/garden.js')])).map(r => r.status === 'fulfilled' ? r.value : null);
  const tile = new THREE.Group(); scene.add(tile);
  const tw = TILE.x1 - TILE.x0, td = TILE.z1 - TILE.z0, tcx = (TILE.x0 + TILE.x1) / 2, tcz = (TILE.z0 + TILE.z1) / 2;

  // the base: ishigaki around a dark core
  if (HM?.stoneMaterial) {
    const stoneM = HM.stoneMaterial({ tint: [.15, .15, .158], moss: .18, lichen: .45, key: 'ishigaki', rough: .86 });
    const m = new THREE.Mesh(ishigakiGeometry(), stoneM); m.castShadow = true; m.receiveShadow = true; tile.add(m);
  }
  const core = new THREE.Mesh(new THREE.BoxGeometry(tw - .4, TILE.base - .02, td - .4), new THREE.MeshStandardMaterial({ color: 0x0c0a09, roughness: 1 }));
  core.position.set(tcx, -TILE.base / 2 - .01, tcz); tile.add(core);

  let house;
  if (HM?.buildHouse) house = await HM.buildHouse({ env, detail: 'mid', panels: true, glow: 0, seed: 1 });
  else { const g = new THREE.Group(); const m = new THREE.Mesh(new THREE.BoxGeometry(10, 4, 6), new THREE.MeshStandardMaterial({ color: 0x8a8378 })); m.position.y = 2; g.add(m); house = { group: g, panels: [], setGlow() {}, anchors: {}, dims: null }; }
  tile.add(house.group);
  const HMat = house.materials || {};

  // panels: silver frames, glass that mirrors the sky (clearcoat), cells lifted enough that the grid reads
  const panels = house.panels || [];
  // the glass mirrors a dusk gradient (lavender overhead, peach low on the sunset side) from the moment it arrives
  const duskEnv = (() => {
    const sc = new THREE.Scene();
    sc.add(new THREE.Mesh(new THREE.SphereGeometry(50, 48, 24), new THREE.ShaderMaterial({ side: THREE.BackSide, depthWrite: false,
      vertexShader: 'varying vec3 vD; void main(){ vD = position; gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.); }',
      fragmentShader: `varying vec3 vD; void main(){ vec3 d = normalize(vD); float y = d.y;
        vec3 c = mix(vec3(.95, .52, .34), vec3(.44, .38, .7), smoothstep(.08, .55, y));
        c = mix(c, vec3(.08, .08, .2), smoothstep(.7, 1., y));
        c *= .6 + .4 * smoothstep(-.8, .6, d.x - d.z * .4);
        c = mix(c, vec3(.03, .03, .05), smoothstep(.02, -.12, y));
        gl_FragColor = vec4(c, 1.); }` })));
    const g = new THREE.PMREMGenerator(renderer); const rt = g.fromScene(sc, 0, .1, 100); g.dispose(); return rt.texture;
  })();
  const glassMats = [];
  { const seen = new Set(); let frameMat = null;
    for (const p of panels) p.traverse(o => { if (!o.isMesh) return;
      if (o.material.map) { if (!seen.has(o.material)) { seen.add(o.material); glassMats.push(o.material); o.material.color.setRGB(3.2, 3.4, 4.2); o.material.envMap = duskEnv; o.material.envMapIntensity = 1.2; o.material.clearcoat = 1; o.material.clearcoatRoughness = .03; } }
      else { if (!frameMat) { frameMat = o.material.clone(); frameMat.color.setRGB(.62, .63, .66); frameMat.metalness = 1; frameMat.roughness = .28; frameMat.customProgramCacheKey = o.material.customProgramCacheKey; } o.material = frameMat; } }); }

  const TREE = V3(7.15, 0, 2.3), LANT = V3(5.3, 0, 5.2);
  let garden = null, sakura = null;
  if (GM?.buildGarden) {
    const L = (x, z) => [x - tcx, z - tcz];
    const gw = tw - .42, gd = td - .42;
    garden = await GM.buildGarden({ seed: 4, size: [gw, gd], rake: 'x', mossGround: true,
      court: [-gw / 2 + 1.05, -gd / 2 + 1.0, gw / 2 - 1.05, gd / 2 - 1.0],
      sand: { color: [.62, .6, .56], pitch: .15, amp: .01 },
      lantern: L(LANT.x, LANT.z), pine: [...L(-7.35, -4.95), .5],
      path: [L(1.1, 6.4), L(.6, 5.6), L(.9, 4.8), L(.4, 4.0), L(.6, 3.3)],
      rocks: [[...L(-4.9, 5.0), .85, .4], [...L(-3.9, 5.7), .45, 1.2], [...L(-6.0, 4.4), .35, 2.2], [...L(3.4, 5.9), .5, 2.1], [...L(-1.8, 2.9), .3, .9]],
      moss: [[...L(-4.8, 5.1), 1.5, 1.0], [...L(7.1, 2.4), 1.2, 1.6]] });
    garden.group.position.set(tcx, 0, tcz); tile.add(garden.group);
    garden.gravel.material.normalScale.set(.45, .45);
    if (garden.mossMaterial) garden.mossMaterial.color.multiplyScalar(.75);
    // the rim between the square garden and the rounded wall top: a moss band
    const rr = new THREE.Shape(); { const x0 = TILE.x0, x1 = TILE.x1, z0 = TILE.z0, z1 = TILE.z1, r = TILE.rc;
      rr.moveTo(x0 + r, z0); rr.lineTo(x1 - r, z0); rr.absarc(x1 - r, z0 + r, r, -Math.PI / 2, 0); rr.lineTo(x1, z1 - r); rr.absarc(x1 - r, z1 - r, r, 0, Math.PI / 2);
      rr.lineTo(x0 + r, z1); rr.absarc(x0 + r, z1 - r, r, Math.PI / 2, Math.PI); rr.lineTo(x0, z0 + r); rr.absarc(x0 + r, z0 + r, r, Math.PI, Math.PI * 1.5); }
    const capG = new THREE.ShapeGeometry(rr, 12).rotateX(Math.PI / 2); capG.translate(0, -.012, 0);
    { const uvA = capG.attributes.uv, P2 = capG.attributes.position; for (let i = 0; i < uvA.count; i++) uvA.setXY(i, P2.getX(i), P2.getZ(i)); }
    capG.computeVertexNormals(); { const n = capG.attributes.normal; for (let i = 0; i < n.count; i++) n.setXYZ(i, 0, 1, 0); }
    const cap = new THREE.Mesh(HM.paint(capG, [1, 1, 1], () => .9), garden.mossMaterial || new THREE.MeshStandardMaterial({ color: 0x2a3020 }));
    cap.receiveShadow = true; tile.add(cap);
  } else {
    const top = new THREE.Mesh(new THREE.PlaneGeometry(tw, td).rotateX(-Math.PI / 2), new THREE.MeshStandardMaterial({ color: 0x77726a, roughness: 1 }));
    top.position.set(tcx, .001, tcz); top.receiveShadow = true; tile.add(top);
  }
  if (SM?.buildSakura) {
    sakura = await SM.buildSakura({ seed: 5, height: 6.4, bloom: 1, spread: 1, lean: .04, avoid: q => { const x = q.x + TREE.x, z = q.z + TREE.z; return (x < 5.95 && z < 3.6 && z > -4.6 && q.y < 6.6 - Math.abs(z + 1.1) * .62 + .4) || x > 8.45 || z > 7.5 || z < TILE.z0 + .5; } });
    sakura.group.position.copy(TREE); tile.add(sakura.group);
    const bm = sakura.blossoms.material, bb = new THREE.Box3().setFromBufferAttribute(sakura.blossoms.geometry.attributes.position);
    const bu = { uY: { value: new THREE.Vector2(bb.min.y, bb.max.y) }, uLant: { value: LANT.clone().setY(1.1) }, uHouseX: { value: 5.2 }, uNightK: { value: 0 } };
    const prevB = bm.onBeforeCompile;
    bm.onBeforeCompile = (sh, r) => {
      prevB?.(sh, r); Object.assign(sh.uniforms, bu);
      sh.vertexShader = sh.vertexShader.replace('#include <common>', '#include <common>\nvarying vec3 vBW;').replace('#include <worldpos_vertex>', '#include <worldpos_vertex>\nvBW = (modelMatrix * vec4(transformed, 1.)).xyz;');
      sh.fragmentShader = sh.fragmentShader.replace('#include <common>', '#include <common>\nvarying vec3 vBW; uniform vec2 uY; uniform vec3 uLant; uniform float uHouseX, uNightK;')
        .replace('#include <color_fragment>', '#include <color_fragment>\n diffuseColor.rgb = mix(vec3(dot(diffuseColor.rgb, vec3(.3, .55, .15))), diffuseColor.rgb, .5);')
        .replace('#include <opaque_fragment>', `if (uNightK > 0.) {
          float h = clamp((vBW.y - uY.x) / (uY.y - uY.x), 0., 1.);
          float lum = dot(diffuseColor.rgb, vec3(.3, .55, .15));
          vec3 pale = mix(vec3(lum), diffuseColor.rgb, .7) * .5 + vec3(.3, .23, .26);
          vec3 sky = vec3(.07, .08, .18) * (.3 + .9 * h * h);
          vec3 win = vec3(1.0, .5, .22) * (1. - h) * (1. - h) * exp(-max(vBW.x - uHouseX, 0.) / 2.6) * .6;
          vec3 lan = vec3(1.0, .68, .42) * exp(-distance(vBW, uLant) / 2.6) * 1.1;
          outgoingLight = mix(outgoingLight, pale * (sky + win + lan) * mix(.4, 1., vShade) + outgoingLight * .25, uNightK);
        }
        #include <opaque_fragment>`);
    };
    bm.customProgramCacheKey = () => 'steps-blossom';
    sakura.nightK = bu.uNightK;
  }
  tile.traverse(o => { if (o.isMesh && o.material && !o.material.isShaderMaterial) o.receiveShadow = true; });

  /* ------------------------------------------------------------ light */
  const sun = new THREE.DirectionalLight(0xffc27a, 3);
  sun.castShadow = true; sun.shadow.mapSize.set(2048, 2048); sun.shadow.radius = 3; sun.shadow.bias = -.0003; sun.shadow.normalBias = .03;
  Object.assign(sun.shadow.camera, { left: -14, right: 14, top: 14, bottom: -14, near: 1, far: 90 });
  sun.shadow.autoUpdate = false;
  scene.add(sun, sun.target); sun.target.position.set(0, 0, .8);
  const hemi = new THREE.HemisphereLight(0x8fa2d8, 0x2a2220, .3); scene.add(hemi);                // cool sky fill
  const fill = new THREE.DirectionalLight(0x9fb0e0, .35); fill.position.set(-10, 12, 26); scene.add(fill);   // the sky behind the viewer, no shadow
  const warm = [[-2.6, 1.0, 3.3], [.6, 1.0, 3.3], [2.9, 1.0, 3.3]].map(p => { const l = new THREE.PointLight(0xffa458, 0, 5, 2); l.position.set(...p); scene.add(l); return l; });
  const wash = new THREE.SpotLight(0xffa860, 0, 14, 1.1, 1, 2); wash.position.set(0, 1.3, 2.6); wash.target.position.set(0, 0, 8); scene.add(wash, wash.target);
  const lantern = new THREE.PointLight(0xff9a45, 0, 4.5, 2); lantern.position.set(LANT.x, 1.05, LANT.z); scene.add(lantern);
  const uplight = new THREE.SpotLight(0xffb070, 0, 14, .7, .9, 2); uplight.position.set(LANT.x - .3, .5, LANT.z + .5);
  uplight.target.position.copy(sakura ? sakura.crown.centre.clone().add(TREE) : V3(TREE.x, 4.4, TREE.z)); scene.add(uplight, uplight.target);

  /* ------------------------------------------------------------ overlays in the house's slope frame */
  const dims = house.dims, ink = new THREE.Color(.95, .92, .86);
  const overlay = new THREE.Group(); house.group.add(overlay);
  let survey = null;
  const PW = 1.7, PH = 1.0;
  const panCentres = [];
  if (dims?.front) {
    const invF = dims.front.clone().invert();
    for (const p of panels) { const c = p.userData.home.position.clone().applyMatrix4(invF); panCentres.push(new THREE.Vector2(c.x, c.z)); }
    while (panCentres.length < 18) panCentres.push(new THREE.Vector2(1e4, 1e4));
    const Wr = dims.Wr, Ls = dims.Ls;
    const g = new THREE.PlaneGeometry(Wr - .3, Ls - .2, 1, 1).rotateX(-Math.PI / 2).translate(0, 0, (Ls - .2) / 2 + .1);
    survey = new THREE.Mesh(g, new THREE.ShaderMaterial({
      ...OVER, polygonOffset: true, polygonOffsetFactor: -4, polygonOffsetUnits: -8,
      uniforms: { uSweep: { value: 0 }, uFade: { value: 1 }, uOut: { value: 1 }, uW: { value: Wr - .3 }, uL: { value: Ls - .2 }, uPW: { value: PW }, uPH: { value: PH },
        uPan: { value: panCentres.slice(0, 18) }, uDraw: { value: new Array(18).fill(0) }, uInk: { value: ink } },
      vertexShader: 'varying vec2 vP; void main(){ vP = position.xz; gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.); }',
      fragmentShader: SURVEY_FS,
    }));
    survey.matrixAutoUpdate = false;
    survey.matrix.copy(dims.front).multiply(new THREE.Matrix4().makeTranslation(0, .05, 0));
    survey.renderOrder = 5;
    overlay.add(survey);
  }

  /* ------------------------------------------------------------ panel flights: from the sunlit side on low arcs, eave row first */
  const order = panels.map((p, k) => k).sort((a, b) => { const [ja, ia] = panels[a].userData.index || [0, a], [jb, ib] = panels[b].userData.index || [0, b]; return (jb - ja) || (ib - ia); });
  const NF = Math.max(1, panels.length);
  const flights = order.map((k, n) => {
    const p = panels[k], home = p.userData.home;
    const start = home.position.clone().add(V3(7.5 + R() * 2, 2.6 + R() * 1.2, 1.5 + R() * 1.5));
    const mid = home.position.clone().add(V3(2.4, 2.2, .8));
    const q0 = new THREE.Quaternion().setFromEuler(new THREE.Euler((R() - .5) * .5, (R() - .5) * .7, (R() - .5) * .4)).multiply(home.quaternion);
    return { p, k, n, home, start, mid, q0, t0: .36 + (n / NF) * .2 };
  });
  const flashMat = new THREE.ShaderMaterial({
    ...ADD, uniforms: { uK: { value: 0 }, uCol: { value: new THREE.Color(.9, .75, .5) } },
    vertexShader: 'varying vec2 vUv; void main(){ vUv = uv * 2. - 1.; gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.); }',
    fragmentShader: `uniform float uK; uniform vec3 uCol; varying vec2 vUv;
      void main(){ vec2 hs = vec2(.85, .5) / vec2(1.15, .8); vec2 q = abs(vUv) - hs; float d = length(max(q, 0.)) + min(max(q.x, q.y), 0.);
        float e = exp(-pow((d - uK * .14) / (.02 + uK * .04), 2.)) * (1. - uK) * (1. - uK);
        gl_FragColor = vec4(uCol * e * .45, 1.); }`,
  });
  const flashes = flights.map(f => {
    const m = new THREE.Mesh(new THREE.PlaneGeometry(2.3, 1.6).rotateX(-Math.PI / 2), flashMat.clone());
    m.position.copy(f.home.position); m.quaternion.copy(f.home.quaternion); m.translateY(.045); m.visible = false; m.renderOrder = 7;
    overlay.add(m); return m;
  });

  /* ------------------------------------------------------------ power on: a pulse down the gable into the battery, and its gauge */
  let flow = null; const gauge = [];
  if (dims && house.anchors?.battery && HM?.HOUSE) {
    const b = house.anchors.battery.position.clone(), HH = HM.HOUSE;
    const cz = b.z + .33, wx = HH.x0 - .1;
    const curve = new THREE.CatmullRomCurve3([V3(wx, HH.plate - .05, cz), V3(wx, HH.plate - .6, cz), V3(wx, b.y + .5, cz), V3(wx, b.y + .12, cz), V3(b.x + .06, b.y + .02, cz - .02)], false, 'catmullrom', .05);
    flow = new THREE.Mesh(new THREE.TubeGeometry(curve, 120, .02, 6, false), new THREE.ShaderMaterial({
      ...ADD, uniforms: { uT: { value: 0 }, uA: { value: 0 }, uCol: { value: new THREE.Color(1.2, .8, .4) } },
      vertexShader: 'varying vec2 vUv; void main(){ vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.); }',
      fragmentShader: `uniform float uT, uA; uniform vec3 uCol; varying vec2 vUv;
        void main(){ float u = vUv.x; float pulse = pow(.5 + .5 * sin((u * 7. - uT * .9) * 6.2832), 14.);
          gl_FragColor = vec4(uCol * (.06 + 1.4 * pulse) * uA * smoothstep(0., .06, u), 1.); }`,
    }));
    flow.renderOrder = 6; house.group.add(flow);
    for (let i = 0; i < 5; i++) {
      const m = new THREE.Mesh(new THREE.BoxGeometry(.006, .075, .05), new THREE.MeshBasicMaterial({ color: 0x000000 }));
      m.position.set(b.x - .163, b.y - .95 + i * .095, b.z); house.group.add(m); gauge.push(m);
    }
  }

  /* ------------------------------------------------------------ colour script */
  const K = (...a) => new THREE.Color(...a);
  const KEYS = [   // p, sun height over the cloud horizon°, key elevation°, key colour/intensity, sun colour, sky horizon (sun side / away), zenith, sky fill
    { p: 0,   up: 4.5,    el: 14, sc: K(1, .8, .56),  si: 4.4, su: K(1.6, 1.1, .62), hs: K(.9, .56, .34),  ha: K(.26, .22, .32), zn: K(.035, .035, .075),  hm: 1.0 },
    { p: .3,  up: 2.4,  el: 9,  sc: K(1, .68, .4),  si: 4.0, su: K(1.7, .95, .48), hs: K(1.0, .47, .25), ha: K(.24, .19, .3),  zn: K(.03, .03, .07), hm: .95 },
    { p: .45, up: .5,   el: 3,  sc: K(1, .52, .27), si: 2.2, su: K(1.7, .62, .3),  hs: K(.9, .35, .2),   ha: K(.2, .16, .28),  zn: K(.026, .028, .066), hm: .95 },
    { p: .56, up: -1.6, el: -1, sc: K(1, .45, .25), si: 0,   su: K(1.1, .42, .26), hs: K(.5, .26, .26),  ha: K(.16, .15, .3),  zn: K(.022, .025, .065), hm: .9 },
    { p: .67, up: -4,   el: -4, sc: K(.6, .6, 1),   si: 0,   su: K(.5, .25, .2),   hs: K(.28, .2, .3),   ha: K(.13, .13, .27), zn: K(.018, .022, .06),  hm: .85 },
    { p: .8,  up: -8,   el: -8, sc: K(.6, .6, 1),   si: 0,   su: K(0, 0, 0),       hs: K(.09, .08, .16), ha: K(.06, .06, .14), zn: K(.018, .02, .06), hm: .7 },
    { p: 1,   up: -8,   el: -8, sc: K(.6, .6, 1),   si: 0,   su: K(0, 0, 0),       hs: K(.08, .075, .15), ha: K(.05, .05, .12), zn: K(.015, .018, .05), hm: .65 },
  ];
  const cur = { up: 0, el: 0, sc: K(), si: 0, su: K(), hs: K(), ha: K(), zn: K(), hm: 0 };
  const script = p => {
    let i = 0; while (i < KEYS.length - 2 && p > KEYS[i + 1].p) i++;
    const a = KEYS[i], b = KEYS[i + 1], t = E.inOutSine(inv(a.p, b.p, p));
    for (const k of ['up', 'el', 'si', 'hm']) cur[k] = lerp(a[k], b[k], t);
    for (const k of ['sc', 'su', 'hs', 'ha', 'zn']) cur[k].copy(a[k]).lerp(b[k], t);
    return cur;
  };

  /* ------------------------------------------------------------ camera framing: fit the plot's projected bounds into the free region */
  const FRAME_PTS = [];
  for (const y of [.1, -TILE.base]) for (const x of [TILE.x0 - TILE.batter, TILE.x1 + TILE.batter]) for (const z of [TILE.z0 - TILE.batter, TILE.z1 + TILE.batter]) FRAME_PTS.push(V3(x, y, z));
  FRAME_PTS.push(V3(0, 7.2, -1.1), V3(-4, 6.4, -1.1), V3(4, 6.4, -1.1));
  if (sakura?.bounds) { const b = sakura.bounds; for (const x of [b.min.x, b.max.x]) for (const y of [b.min.y, b.max.y]) for (const z of [b.min.z, b.max.z]) FRAME_PTS.push(V3(x, y, z).add(TREE)); }
  const target = V3(.6, .9, .8), cam = { yaw: 0, pitch: .4, dist: 40 };
  const raySun = V3(), tmp = V3(), UP = V3(0, 1, 0), right = V3(), _pp = V3();
  let lastPin = -1, lastLanded = -1;
  const place = () => { const cp = Math.cos(cam.pitch); camera.position.set(target.x + Math.sin(cam.yaw) * cp * cam.dist, target.y + Math.sin(cam.pitch) * cam.dist, target.z + Math.cos(cam.yaw) * cp * cam.dist); camera.lookAt(target); camera.updateMatrixWorld(); };
  const bounds = () => { let x0 = 9, x1 = -9, y0 = 9, y1 = -9; for (const q of FRAME_PTS) { _pp.copy(q).project(camera); x0 = Math.min(x0, _pp.x); x1 = Math.max(x1, _pp.x); y0 = Math.min(y0, _pp.y); y1 = Math.max(y1, _pp.y); } return { x0, x1, y0, y1 }; };
  const post = {
    exposure: 1.0, tone: 'aces', hue: .42, sat: 1.03, contrast: 1.05, vignette: .12, grain: .016, ss: 1,
    bloom: { strength: .38, radius: 1, threshold: 1.6, knee: .7 },
    rays: { sun: raySun, strength: .6, tint: [1, .74, .48], density: .9, decay: .95, weight: .02, threshold: 1.4, falloff: 5 },
  };

  return {
    scene, camera, post,
    update(dt, t, s) {
      const p = clamp(s.pin), mobile = s.w < 600;
      const tt = REDUCED ? 0 : t;
      const C = script(p);

      /* camera: ~22° orbit, easing closer through the chapters; fitted to the plot's projected bounds */
      const orbit = E.inOutSine(p);
      cam.yaw = lerp(.1, -.28, orbit);
      cam.pitch = mobile ? lerp(.27, .23, orbit) : lerp(.44, .36, orbit);
      const zoom = smooth(.22, .5, p) * .5 + smooth(.58, .86, p) * .5;
      camera.fov = 25; camera.aspect = s.w / Math.max(1, s.h); camera.clearViewOffset(); camera.updateProjectionMatrix();
      const reg = mobile ? { cx: .5, cy: .19, hw: .475, hh: .112 } : { cx: .765, cy: .53, hw: .215, hh: .38 };
      const zk = mobile ? 1 : lerp(.88, 1, zoom);                                   // the plot grows toward the full region through the chapters
      for (let it = 0; it < 4; it++) {
        place(); const bb = bounds();
        cam.dist *= Math.max((bb.x1 - bb.x0) / (4 * reg.hw * zk), (bb.y1 - bb.y0) / (4 * reg.hh * zk));
      }
      place();
      { const bb = bounds(), cxN = (bb.x0 + bb.x1) / 2, cyN = (bb.y0 + bb.y1) / 2, rx = reg.cx * 2 - 1, ry = 1 - reg.cy * 2;
        camera.setViewOffset(s.w, s.h, -(rx - cxN) / 2 * s.w, (ry - cyN) / 2 * s.h, s.w, s.h); }
      if (!REDUCED) { camera.position.y += Math.sin(tt * .45) * .06; }
      camera.updateProjectionMatrix();

      /* key light: the sun behind-right in world space (low, setting); after sunset the same light is the moon */
      const el = C.el * Math.PI / 180;
      sunDir.set(Math.sin(SUN_AZ) * Math.cos(el), Math.sin(el), Math.cos(SUN_AZ) * Math.cos(el));
      const night = smooth(.66, .82, p);
      if (C.si > .01) { sun.position.copy(sunDir).multiplyScalar(40); sun.color.copy(C.sc); sun.intensity = C.si; }
      else { sun.position.set(-14, 26, -6); sun.color.setRGB(.6, .68, 1); sun.intensity = 1.7 * night; }
      sun.target.position.set(0, 0, .8);
      sun.shadow.radius = lerp(3, 10, smooth(.3, .52, p)) * (1 - night) + 4 * night;       // the light softens as the sun sinks into the haze
      sakura?.setSunColor?.(sun.color.clone().multiplyScalar(sun.intensity));
      // sky fill: the shadow floor, tinted by the sky overhead
      hemi.intensity = C.hm * lerp(1.5, 1.1, night); hemi.color.setRGB(.6, .64, .86).lerp(C.hs, .15 * (1 - night)); hemi.groundColor.copy(C.hs).multiplyScalar(.25);
      fill.intensity = lerp(.45, .38, night);
      const ek = Math.round(p * 60);
      if (ek !== envKey) { envKey = ek; envU.uHorSun.value.copy(C.hs); envU.uHorAway.value.copy(C.ha); envU.uZen.value.copy(C.zn); envU.uGlowC.value.copy(C.su).multiplyScalar(.5 * smooth(-3, 2, C.up)); bakeEnv(); }
      scene.environmentIntensity = lerp(1.3, 1.6, night);

      /* sky + cloud horizon: pick where the horizon sits on screen, then size the cloud sea so its rim lands there */
      const hy = mobile ? .5 : .18;
      _pp.set(0, hy, .5).unproject(camera).sub(camera.position).normalize();
      const horEl = Math.min(-.03, Math.asin(_pp.y));
      const rimR = (camera.position.y - CLOUD_Y) / Math.tan(-horEl);
      clouds.position.set(camera.position.x, CLOUD_Y, camera.position.z); clouds.scale.setScalar(rimR * 1.002); cloudU.uRim.value = rimR;
      _pp.set(mobile ? .55 : .6, 0, .5).unproject(camera).sub(camera.position);
      const sAz = Math.atan2(_pp.x, _pp.z), sEl = horEl + C.up * Math.PI / 180;
      sunDirV.set(Math.sin(sAz) * Math.cos(sEl), Math.sin(sEl), Math.cos(sAz) * Math.cos(sEl));
      raySun.copy(sunDirV).multiplyScalar(300).add(camera.position);
      skyU.uHorSun.value.copy(C.hs); skyU.uHorAway.value.copy(C.ha); skyU.uZen.value.copy(C.zn); skyU.uSunCol.value.copy(C.su);
      for (const U of [voidU, cloudU]) { U.uHorEl.value = horEl; U.uCalmX.value = mobile ? -1 : .5; U.uCalmY.value = mobile ? .76 : -1; U.uResX.value = s.w * VP.dpr; U.uResY.value = s.h * VP.dpr;
        U.uHorSun.value.copy(C.hs); U.uHorAway.value.copy(C.ha); U.uZen.value.copy(C.zn); U.uSunCol.value.copy(C.su); }
      voidU.uSunK.value = smooth(-2.2, -.6, C.up);
      voidU.uNight.value = smooth(.62, .85, p); voidU.uMoon.value = smooth(.7, .86, p);
      _pp.set(mobile ? -.2 : .15, mobile ? .85 : .72, .5).unproject(camera).sub(camera.position).normalize(); moonDir.copy(_pp);
      voidU.uTime.value = tt;
      const keyDir = sun.position.clone().normalize();
      cloudU.uKeyDir.value.copy(keyDir); cloudU.uKeyCol.value.copy(sun.color).multiplyScalar(sun.intensity * .22);
      cloudU.uFill.value.copy(C.ha).lerp(C.zn, .3).multiplyScalar(.75);
      if (this.post?.o) {   // the ray pass is the most expensive part of the chain: only while the sun is up
        const rs = .5 * smooth(-1.5, 1.5, C.up);
        if (rs > .005) { this.post.o.rays = this._rays || this.post.o.rays; this.post.o.rays.strength = rs; }
        else if (this.post.o.rays) { this._rays = this.post.o.rays; this.post.o.rays = null; }
      }

      /* 01: survey grid sweeps, outlines ink on, then lift away as the panels arrive */
      if (survey) {
        const u = survey.material.uniforms;
        u.uSweep.value = E.inOutSine(inv(.03, .2, p));
        u.uFade.value = 1 - smooth(.28, .36, p);
        u.uOut.value = 1 - smooth(.34, .4, p);
        for (let k = 0; k < 18; k++) { const f = flights.find(ff => ff.k === k); const n = f ? f.n : k; u.uDraw.value[k] = smooth(.12 + n * .008, .21 + n * .008, p); }
      }

      /* 02: flights */
      let moving = false, landed = 0;
      if (house.rails) house.rails.visible = p > .35;
      for (const f of flights) {
        const k = inv(f.t0, f.t0 + .07, p);
        if (k <= 0) f.p.visible = false;
        else {
          f.p.visible = true;
          const e = E.outCubic(k), om = 1 - e, A = f.start, B = f.mid, Cc = f.home.position;
          f.p.position.set(om * om * A.x + 2 * om * e * B.x + e * e * Cc.x, om * om * A.y + 2 * om * e * B.y + e * e * Cc.y, om * om * A.z + 2 * om * e * B.z + e * e * Cc.z);
          f.p.quaternion.slerpQuaternions(f.q0, f.home.quaternion, E.outQuart(k));
          if (k < 1) moving = true; else landed++;
        }
        const fl = flashes[f.n], rk = inv(f.t0 + .064, f.t0 + .1, p);
        fl.visible = rk > 0 && rk < 1; fl.material.uniforms.uK.value = rk;
      }

      /* 03: power on (windows from ~.6) */
      const glow = smooth(.5, .68, p);
      house.setGlow?.(.12 * (1 - smooth(.4, .55, p)) + glow * .8);          // faint daytime backlight through the paper, then the lamps
      if (HMat.paper) HMat.paper.color.multiplyScalar(lerp(.42, 1, glow));
      for (const m of glassMats) m.envMapIntensity = lerp(1.2, .55, smooth(.62, .9, p));
      for (const l of warm) l.intensity = glow * 2.2;
      wash.intensity = glow * 26;
      const lk = smooth(.7, .82, p); lantern.intensity = lk * 3; uplight.intensity = lk * 14; garden?.setGlow?.(lk * .22);
      if (flow) { flow.material.uniforms.uA.value = smooth(.8, .92, p); flow.material.uniforms.uT.value = tt; }
      gauge.forEach((m, i) => { const on = smooth(.76 + i * .035, .79 + i * .035, p); m.material.color.setRGB(.35 * on + .02, 2.2 * on + .03, 1.0 * on + .03); });
      sakura?.update?.(tt, REDUCED ? 0 : .35);
      if (sakura?.nightK) sakura.nightK.value = smooth(.55, .8, p);

      if (Math.abs(p - lastPin) > 1e-4 || moving || landed !== lastLanded) { sun.shadow.needsUpdate = true; lastPin = p; lastLanded = landed; }
    },
  };
}
