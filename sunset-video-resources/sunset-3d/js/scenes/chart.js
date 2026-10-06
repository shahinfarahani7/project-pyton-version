/* Savings chart — 25-year electricity cost as three stacks of the same unit (one slab = ¥1M) on a hinoki tray.
   grid  : smoked kawara slabs (ibushi-gin silver-graphite with carbon patches, slightly domed) — the old way
   solar : hinoki slabs made like boxes from boards: long grain on every face, the top's grain parallel to the sides'
   sunset: a shu-urushi jūbako — one vermilion, a thin black-urushi rim line at each tier, under a solar-glass lid (the hero)
   Heights follow STATE.bill on a soft damped spring; slabs keep a fixed world size, the camera moves instead.
   Lighting: the page studio environment + the shared warm key and bounce (BRIEF). 1 world unit ≈ 10 cm. */
import { THREE, makeCanvas, canvasTexture, rng, clamp, lerp, damp, STATE, costs, REDUCED, VP } from '../core.js';
import { RoundedBoxGeometry } from 'three/addons/geometries/RoundedBoxGeometry.js';
import { hinokiTextures, hinokiEndTextures, perMetre as woodPerMetre } from '../models/woods.js';

const Q = new URLSearchParams(location.search);
const BAR_W = .6, BAR_X = [-1.0, 0, 1.0], SEAM = .003, UNIT = 1e6, U_H = .17, MAXB = 24, LID = .03, FRAC_MIN = .25;
const TRAY = { w: 3.4, d: 1.5, h: .12, y0: .05 }, TRAY_TOP = TRAY.y0 + TRAY.h;
const KEYS = ['grid', 'solar', 'sunset'];
const KEY_DIR = new THREE.Vector3(-1, 1.3, .8).normalize();

/* bar heights (world): stacks of one fixed slab per ¥1M */
const targets = bill => { const c = costs(bill); return KEYS.map(n => c[n] / UNIT * U_H); };
const HMAX = costs(40000).grid / UNIT * U_H;

/* ------------------------------------------------------------------ geometry */
/** Rounded box whose height can change without stretching its rounded edges. UVs per triangle, in world units.
    grain: 'x' — grain along x on the top and ±z faces, end grain on ±x (the tray board)
           'h' — horizontal grain round the sides (along x on ±z, along z on ±x), top in its own planar map (slabs) */
class Block {
  constructor(w, d, r, seg, grain = 'h', dome = 0) {
    this.geo = new RoundedBoxGeometry(w, 1, d, seg, r);
    this.dome = dome; this.hw = w / 2; this.hd = d / 2; this.baseN = Float32Array.from(this.geo.attributes.normal.array);
    const p = this.geo.attributes.position;
    this.base = Float32Array.from(p.array); this.sign = new Float32Array(p.count);
    for (let i = 0; i < p.count; i++) this.sign[i] = Math.sign(this.base[i * 3 + 1]) || 1;
    this.r = r; this.h = 1; this.grain = grain;
    this.setH(1, true);
  }
  setH(h, force) {
    h = Math.max(h, this.r * 2.2);
    if (!force && Math.abs(h - this.h) < 1e-5) return false;
    this.h = h;
    const a = this.geo.attributes.position.array, b = this.base, s = this.sign, dh = (h - 1) / 2;
    for (let i = 0; i < s.length; i++) {
      a[i * 3] = b[i * 3]; a[i * 3 + 1] = b[i * 3 + 1] + s[i] * dh; a[i * 3 + 2] = b[i * 3 + 2];
      if (this.dome && s[i] > 0) {
        const u = b[i * 3] / this.hw, v = b[i * 3 + 2] / this.hd, fu = Math.max(0, 1 - u * u), fv = Math.max(0, 1 - v * v);
        a[i * 3 + 1] += this.dome * fu * fv;
        const bn = this.baseN, ny = bn[i * 3 + 1];
        if (ny > .5) {   // tilt the top face's normals by the dome's slope (the rounded edges keep their own)
          const gx = this.dome * (-2 * u / this.hw) * fv, gz = this.dome * (-2 * v / this.hd) * fu, k = (ny - .5) * 2;
          const nx = bn[i * 3] - gx * k, nz = bn[i * 3 + 2] - gz * k, l = Math.hypot(nx, ny, nz), N = this.geo.attributes.normal.array;
          N[i * 3] = nx / l; N[i * 3 + 1] = ny / l; N[i * 3 + 2] = nz / l;
        }
      }
    }
    if (this.dome) this.geo.attributes.normal.needsUpdate = true;
    this.geo.attributes.position.needsUpdate = true;
    this.uv(); this.geo.computeBoundingSphere(); this.geo.computeBoundingBox();
    return true;
  }
  uv() {
    const p = this.geo.attributes.position.array, n = this.geo.attributes.normal.array, uv = this.geo.attributes.uv.array;
    for (let t = 0; t < p.length / 9; t++) {
      let nx = 0, ny = 0, nz = 0;
      for (let k = 0; k < 3; k++) { nx += n[t * 9 + k * 3]; ny += n[t * 9 + k * 3 + 1]; nz += n[t * 9 + k * 3 + 2]; }
      const ax = Math.abs(nx), ay = Math.abs(ny), az = Math.abs(nz);
      for (let k = 0; k < 3; k++) {
        const i = t * 3 + k, x = p[i * 3], y = p[i * 3 + 1] + this.h / 2, z = p[i * 3 + 2];
        let u, v;   // the wood textures' grain runs along v
        if (this.grain === 'x') { if (ay >= ax && ay >= az) { u = z; v = x; } else if (az >= ax) { u = y; v = x; } else { u = z; v = y; } }
        else { if (ay >= ax && ay >= az) { u = z; v = x; } else if (az >= ax) { u = y; v = x; } else { u = y; v = z; } }
        uv[i * 2] = u; uv[i * 2 + 1] = v;
      }
    }
    this.geo.attributes.uv.needsUpdate = true;
  }
}

/** Soft rectangle alpha texture (contact shadow): the rect fills w×h inside a (w+2p)×(h+2p) quad. */
function softRect(w, h, blur, pad) {
  const ppu = 96, W = Math.ceil((w + pad * 2) * ppu), H = Math.ceil((h + pad * 2) * ppu), cv = makeCanvas(W, H), g = cv.getContext('2d');
  g.fillStyle = '#000'; g.fillRect(0, 0, W, H);
  g.filter = `blur(${blur * ppu}px)`; g.fillStyle = '#fff'; g.fillRect(pad * ppu, pad * ppu, w * ppu, h * ppu);
  return canvasTexture(cv, { srgb: false });
}

/** A sakura petal: subdivided, notched, cupped and curled; ~1 cm. */
function petalGeometry(r) {
  const L = .095, W = .068, g = new THREE.PlaneGeometry(1, 1, 12, 14), p = g.attributes.position, col = [];
  const cup = .006 + r() * .005, curl = .006 + r() * .01, twist = (r() - .5) * .01;
  for (let i = 0; i < p.count; i++) {
    const u = p.getX(i) + .5, v = p.getY(i) + .5, s = u * 2 - 1;
    const wv = W * Math.pow(Math.sin(Math.PI * Math.min(1, v * .78 + .06)), .9) * (v < .12 ? .35 + v / .12 * .65 : 1);
    let x = s * wv * .5, y = v * L;
    y -= .009 * Math.pow(Math.max(0, 1 - Math.abs(s) * 2.2), 2) * Math.pow(v, 6);
    p.setXYZ(i, x, y, cup * s * s * Math.min(1, v * 2) + curl * v ** 3 + twist * s * v);
    const k = Math.min(1, v * 1.5);
    col.push(lerp(.9, .98, k), lerp(.5, .78, k), lerp(.58, .8, k));
  }
  g.setAttribute('color', new THREE.Float32BufferAttribute(col, 3));
  g.computeVertexNormals();
  return g;
}

const NOISE = /* glsl */`
float h13(vec3 p){ p = fract(p * .1031); p += dot(p, p.zyx + 31.32); return fract((p.x + p.y) * p.z); }
float vn3(vec3 p){ vec3 i = floor(p), f = fract(p); f = f * f * (3. - 2. * f);
  return mix(mix(mix(h13(i), h13(i + vec3(1,0,0)), f.x), mix(h13(i + vec3(0,1,0)), h13(i + vec3(1,1,0)), f.x), f.y),
             mix(mix(h13(i + vec3(0,0,1)), h13(i + vec3(1,0,1)), f.x), mix(h13(i + vec3(0,1,1)), h13(i + vec3(1,1,1)), f.x), f.y), f.z); }`;
/** varyings: object position/normal and world position (instancing-aware) */
function withVaryings(sh) {
  sh.vertexShader = sh.vertexShader.replace('#include <common>', '#include <common>\nvarying vec3 vOP; varying vec3 vON; varying vec3 vWP;')
    .replace('#include <begin_vertex>', `#include <begin_vertex>
      vOP = transformed; vON = normal;
      #ifdef USE_INSTANCING
        vWP = (modelMatrix * instanceMatrix * vec4(transformed, 1.)).xyz;
      #else
        vWP = (modelMatrix * vec4(transformed, 1.)).xyz;
      #endif`);
  sh.fragmentShader = sh.fragmentShader.replace('#include <common>', '#include <common>\nvarying vec3 vOP; varying vec3 vON; varying vec3 vWP;' + NOISE);
}
/** each slab its own piece of wood: offset map UVs by the instance (or mesh) position */
function uvJitter(sh) {
  sh.vertexShader = sh.vertexShader.replace('#include <uv_vertex>', `#include <uv_vertex>
    #ifdef USE_INSTANCING
      float jy = instanceMatrix[3].y * 5.3 + modelMatrix[3].x * 7.;
    #else
      float jy = modelMatrix[3].y * 5.3 + modelMatrix[3].x * 7. + 11.;
    #endif
    vec2 jo = vec2(fract(jy * 3.71), fract(jy * 1.37)) * 3.;
    #ifdef USE_MAP
      vMapUv += jo;
    #endif
    #ifdef USE_NORMALMAP
      vNormalMapUv += jo;
    #endif
    #ifdef USE_ROUGHNESSMAP
      vRoughnessMapUv += jo;
    #endif`);
}
/** slab faces inside a stack's 6 mm seams are hidden from the sky: occlude them (AO in the gaps) */
function seamAO(sh, U) {
  Object.assign(sh.uniforms, U);
  sh.fragmentShader = sh.fragmentShader.replace('#include <common>', '#include <common>\nuniform float uTopY;')
    .replace('#include <aomap_fragment>', `#include <aomap_fragment>
      { float inside = step(vWP.y, uTopY - .01) * step(${(TRAY_TOP + .01).toFixed(3)}, vWP.y);
        float horiz = smoothstep(.3, .85, abs(vON.y));
        float occ = 1. - horiz * inside * .7;
        reflectedLight.directDiffuse *= occ; reflectedLight.indirectDiffuse *= occ; reflectedLight.directSpecular *= occ; reflectedLight.indirectSpecular *= occ; }`);
}

export async function create(ctx) {
  const { env } = ctx;
  const studio = env.studio || env.texture;
  const scene = new THREE.Scene();
  scene.environment = studio; scene.environmentIntensity = .35;
  const camera = new THREE.PerspectiveCamera(22, 1, .1, 120);
  const R = rng(1207);
  const envOn = (m, k = .35) => { m.envMap = studio; m.envMapIntensity = k; return m; };   // r163+: envMapIntensity needs material.envMap

  /* ---- hinoki (shared generator): side grain + end grain, UVs in world units (10 cm) */
  const side = seed => woodPerMetre(hinokiTextures({ seed }), 10);
  const endg = seed => woodPerMetre(hinokiEndTextures({ seed, ringSpacing: 2.2, contrast: .7, tint: [222, 194, 168], late: [176, 136, 104], pith: [-.12, .8] }), 10);
  const woodMat = (t, nrm, extra = {}) => envOn(new THREE.MeshPhysicalMaterial({ map: t.map, normalMap: t.normalMap, normalScale: new THREE.Vector2(nrm, nrm), roughnessMap: t.roughnessMap, roughness: 1, clearcoat: .1, clearcoatRoughness: .5, ...extra }));
  const trayS = side(5), trayE = endg(5);
  const traySide = woodMat(trayS, .12), trayEnd = woodMat(trayE, .35, { roughness: 1.15 });
  const trayMats = [trayEnd, trayEnd, traySide, traySide, traySide, traySide];   // BoxGeometry groups: +x −x +y −y +z −z

  const TOPY = KEYS.map(() => ({ uTopY: { value: 1 } }));
  const hinS = side(11);
  const slabSide = woodMat(hinS, .12);
  slabSide.onBeforeCompile = sh => { withVaryings(sh); uvJitter(sh); seamAO(sh, TOPY[1]); };
  slabSide.customProgramCacheKey = () => 'chart-hinoki5';
  const hinokiMats = slabSide;   // boards on every face; the top's grain runs with the long faces' grain

  /* ---- kawara: smoked roof-tile clay (ibushi-gin) — silver-graphite with uneven carbon patches in three tones */
  const kawara = envOn(new THREE.MeshPhysicalMaterial({ color: new THREE.Color(.2, .205, .215), roughness: .5, metalness: .3, clearcoat: .05, clearcoatRoughness: .5 }), .6);
  kawara.onBeforeCompile = sh => {
    withVaryings(sh); seamAO(sh, TOPY[0]);
    sh.fragmentShader = sh.fragmentShader
      .replace('#include <color_fragment>', `#include <color_fragment>
        float slab = floor((vWP.y - ${TRAY_TOP.toFixed(3)}) / ${U_H.toFixed(3)});
        vec3 q = vWP * 2.2 + slab * 3.17;
        float n1 = vn3(q) * .55 + vn3(q * 2.3) * .3 + vn3(q * 6.1) * .15;
        float n2 = vn3(q * 1.5 + 9.) * .6 + vn3(q * 4.4 + 3.) * .4;
        float carbon = smoothstep(.5, .72, n1) * .75;                          // soft carbon clouding from the smoke firing
        float silver = smoothstep(.58, .74, n2) * (1. - carbon) * .7;          // where the silver bloom came through
        vec3 base = vec3(.2, .205, .215) * (.94 + h13(vec3(slab, 2., 5.)) * .12);
        diffuseColor.rgb = mix(base, vec3(.11, .11, .118), carbon);
        diffuseColor.rgb = mix(diffuseColor.rgb, vec3(.29, .295, .305), silver);
        diffuseColor.rgb *= .96 + vn3(q * 18.) * .08;`)
      .replace('#include <roughnessmap_fragment>', `#include <roughnessmap_fragment>
        roughnessFactor = .5 + carbon * .14 - silver * .14;`)
      .replace('#include <metalnessmap_fragment>', `#include <metalnessmap_fragment>
        metalnessFactor = .3 - carbon * .15 + silver * .15;`);
  };
  kawara.customProgramCacheKey = () => 'chart-kawara5';

  /* ---- jūbako: shu urushi, one vermilion on every tier, a thin black-urushi rim line where the tiers meet.
     Low env on the red and a darker clear coat reflection, so the shaded faces stay deep, saturated red. */
  const JU = { uH: { value: U_H - SEAM } }, JUF = { uH: { value: U_H - SEAM } };
  const jubako = (U) => {
    const m = envOn(new THREE.MeshPhysicalMaterial({ color: new THREE.Color('#F07A3A').convertSRGBToLinear(), roughness: .34, clearcoat: .45, clearcoatRoughness: .1, specularIntensity: .3 }), .45);
    m.onBeforeCompile = sh => {
      Object.assign(sh.uniforms, U);
      withVaryings(sh); seamAO(sh, TOPY[2]);
      sh.fragmentShader = sh.fragmentShader.replace('#include <common>', '#include <common>\nuniform float uH;')
        .replace('#include <color_fragment>', `#include <color_fragment>
          float ly = vOP.y + uH * .5, fe = fwidth(ly) + 1e-5;
          float rimL = max(1. - smoothstep(.009 - fe, .009 + fe, uH - ly), 1. - smoothstep(.006 - fe, .006 + fe, ly));
          diffuseColor.rgb = mix(diffuseColor.rgb, vec3(.018, .013, .012), rimL);`);
    };
    m.customProgramCacheKey = () => 'chart-jubako5';
    return m;
  };
  const urushi = jubako(JU), urushiFrac = jubako(JUF);

  /* ---- the lid: a solar panel — blue-black glass, 6 × 6 cells marked only by thin silver busbars, a thin silver frame set flush */
  const lidMat = envOn(new THREE.MeshPhysicalMaterial({ color: 0xffffff, roughness: .12, metalness: 0, clearcoat: 1, clearcoatRoughness: .04 }), .3);
  lidMat.onBeforeCompile = sh => {
    withVaryings(sh);
    sh.fragmentShader = sh.fragmentShader
      .replace('#include <color_fragment>', `#include <color_fragment>
        const float HW = ${(BAR_W / 2).toFixed(4)}, FR = .01;
        float frame = 1., bus = 0., gap = 0.;
        if (vON.y > .7) {
          vec2 q = vOP.xz;
          float e = HW - max(abs(q.x), abs(q.y)), fe = fwidth(e) + 1e-5;
          frame = 1. - smoothstep(FR - fe, FR + fe, e);
          float pitch = 2. * (HW - FR - .004) / 6.;
          vec2 c = (q + HW - FR - .004) / pitch, f = fract(c);
          float fw = max(fwidth(c.x), fwidth(c.y)) + 1e-5;
          // two busbars across each cell (along z) and the fine cell joints, all drawn at their true coverage
          float b1 = min(abs(f.x - .33), abs(f.x - .67)) * pitch, bw = .0008;
          bus = (1. - smoothstep(bw - fw * pitch, bw + fw * pitch, b1)) * clamp(bw * 2. / (fw * pitch), 0., 1.);
          vec2 d = min(f, 1. - f) * pitch;
          gap = (1. - smoothstep(.001 - fw * pitch, .001 + fw * pitch, min(d.x, d.y))) * .5;
        }
        diffuseColor.rgb = mix(vec3(.008, .016, .04), vec3(.62, .64, .68), max(frame, bus * .38));
        diffuseColor.rgb = mix(diffuseColor.rgb, vec3(.05, .07, .1), gap * (1. - frame));`)
      .replace('#include <metalnessmap_fragment>', `#include <metalnessmap_fragment>
        metalnessFactor = max(frame, bus);`)
      .replace('#include <roughnessmap_fragment>', `#include <roughnessmap_fragment>
        roughnessFactor = mix(.08, .3, max(frame, bus));`)
      .replace('#include <lights_physical_fragment>', `#include <lights_physical_fragment>
        material.clearcoat *= 1. - frame;`);
  };
  lidMat.customProgramCacheKey = () => 'chart-lid5';

  /* ---- the tray: a black urushi plinth under a hinoki board */
  const root = new THREE.Group(); scene.add(root);
  // a recessed foot in the same hinoki, set well in from the edges: the board's overhang throws a soft shadow line
  const plinth = new THREE.Mesh(new RoundedBoxGeometry(TRAY.w - .36, TRAY.y0 + .004, TRAY.d - .36, 2, .01), traySide);
  plinth.position.y = (TRAY.y0 + .004) / 2; plinth.castShadow = plinth.receiveShadow = true; root.add(plinth);
  const board = new Block(TRAY.w, TRAY.d, .018, 4, 'x'); board.setH(TRAY.h);
  const boardM = new THREE.Mesh(board.geo, trayMats); boardM.position.y = TRAY.y0 + TRAY.h / 2; boardM.castShadow = boardM.receiveShadow = true; root.add(boardM);

  /* ---- contact shadows */
  const shadowQuad = (w, d, blur, pad, op, y) => {
    const m = new THREE.Mesh(new THREE.PlaneGeometry(w + pad * 2, d + pad * 2), new THREE.MeshBasicMaterial({ color: 0x1c1310, alphaMap: softRect(w, d, blur, pad), transparent: true, opacity: op, depthWrite: false, toneMapped: false }));
    m.rotation.x = -Math.PI / 2; m.position.y = y; m.renderOrder = 1; return m;
  };
  root.add(shadowQuad(TRAY.w - .12, TRAY.d - .12, .08, .3, .5, .0015));
  BAR_X.forEach(x => { const q = shadowQuad(BAR_W, BAR_W, .035, .12, .38, TRAY_TOP + .0012); q.position.x = x; root.add(q); });

  /* ---- paper: the key's long soft shadow, faded well inside the host */
  const FADE = { value: new THREE.Vector4(-1, 1, 0, 0) };
  const paper = new THREE.Mesh(new THREE.PlaneGeometry(40, 40), new THREE.ShadowMaterial({ color: 0x2c1e1a, opacity: .28, transparent: true, depthWrite: false }));
  paper.rotation.x = -Math.PI / 2; paper.receiveShadow = true;
  paper.material.onBeforeCompile = sh => {
    sh.uniforms.uFade = FADE;
    sh.vertexShader = sh.vertexShader.replace('#include <common>', '#include <common>\nvarying vec3 vFP; varying vec2 vNdc;').replace('#include <begin_vertex>', '#include <begin_vertex>\nvFP = (modelMatrix * vec4(transformed, 1.)).xyz;')
      .replace('#include <project_vertex>', '#include <project_vertex>\nvNdc = gl_Position.xy / gl_Position.w;');
    sh.fragmentShader = sh.fragmentShader.replace('#include <common>', '#include <common>\nvarying vec3 vFP; varying vec2 vNdc; uniform vec4 uFade;')
      .replace('#include <tonemapping_fragment>', `vec2 fq = max(abs(vFP.xz) - vec2(${(TRAY.w / 2).toFixed(2)}, ${(TRAY.d / 2).toFixed(2)}), 0.);
        gl_FragColor.a *= 1. - smoothstep(.05, 1.1, length(fq));
        gl_FragColor.a *= smoothstep(uFade.x, uFade.x + .22, vNdc.x) * smoothstep(uFade.y, uFade.y - .22, vNdc.x) * smoothstep(-1., -.8, vNdc.y) * smoothstep(1., .8, vNdc.y);
        #include <tonemapping_fragment>`);
  };
  root.add(paper);

  /* ---- the three stacks: full slabs are instances of one geometry; a short fraction slab and (sunset) the lid on top */
  const bars = KEYS.map((key, bi) => {
    const g = new THREE.Group(); g.position.set(BAR_X[bi], TRAY_TOP, 0); root.add(g);
    const r = key === 'sunset' ? .012 : key === 'grid' ? .02 : .016;
    const mat = key === 'grid' ? kawara : key === 'solar' ? hinokiMats : urushi;
    const dome = key === 'grid' ? .012 : 0;
    const unit = new Block(BAR_W, BAR_W, r, 3, 'h', dome), fracB = new Block(BAR_W, BAR_W, r, 3, 'h', dome);
    const inst = new THREE.InstancedMesh(unit.geo, mat, MAXB); inst.count = 0; inst.castShadow = inst.receiveShadow = true; inst.frustumCulled = false; g.add(inst);
    const tones = [];
    for (let k = 0; k < MAXB; k++) {   // per-slab tone: each a different tile / board / box
      const v = key === 'grid' ? .9 + R() * .2 : .93 + R() * .12;
      tones.push(v); inst.setColorAt(k, new THREE.Color(v, v, v));
    }
    const fracMat = key === 'sunset' ? urushiFrac : key === 'solar' ? mat : Object.assign(mat.clone(), { onBeforeCompile: mat.onBeforeCompile, customProgramCacheKey: mat.customProgramCacheKey });
    const frac = new THREE.Mesh(fracB.geo, fracMat); frac.castShadow = frac.receiveShadow = true; g.add(frac);
    let lid = null;
    if (key === 'sunset') { lid = new THREE.Mesh(new RoundedBoxGeometry(BAR_W, LID, BAR_W, 2, .004), lidMat); lid.castShadow = lid.receiveShadow = true; g.add(lid); }
    const lead = new THREE.Line(new THREE.BufferGeometry().setFromPoints([new THREE.Vector3(), new THREE.Vector3()]), new THREE.LineBasicMaterial({ color: 0x1e1916, transparent: true, opacity: 0, depthTest: false, depthWrite: false, toneMapped: false }));
    lead.frustumCulled = false; lead.renderOrder = 10; scene.add(lead);
    return { key, g, unit, fracB, inst, frac, fracMat, lid, tones, anchor: new THREE.Vector3(), top: new THREE.Vector3(), lead, lx: null, ly: null, size: [90, 44, 12], measured: false, H: 0, x: 0, v: 0, last: '' };
  });

  /* ---- petals resting on the tray (matte, ~1 cm) */
  const petalMat = envOn(new THREE.MeshPhysicalMaterial({ vertexColors: true, roughness: .9, specularIntensity: .25, side: THREE.DoubleSide, emissive: new THREE.Color(.16, .07, .08) }), .3);
  for (const [x, z, ry] of [[1.42, .5, .8], [-1.45, -.42, 2.4], [.5, .54, -1.1], [1.55, .34, 2.0]]) {
    const pm = new THREE.Mesh(petalGeometry(R), petalMat);
    pm.rotation.set(-Math.PI / 2, 0, ry); pm.position.set(x, TRAY_TOP + .002, z); pm.castShadow = pm.receiveShadow = true; root.add(pm);
  }

  /* ---- light: the shared key + warm bounce; PCF shadow fitted to the tray and the tallest stack */
  const sun = new THREE.DirectionalLight(new THREE.Color(0xFFE0BC), 3.3);
  sun.target.position.set(0, .8, 0); sun.position.copy(KEY_DIR).multiplyScalar(8).add(sun.target.position);
  scene.add(sun, sun.target, new THREE.HemisphereLight(new THREE.Color(0xFFF3E4), new THREE.Color(0xE7D6BC), .4));
  sun.castShadow = true; sun.shadow.mapSize.set(2048, 2048);
  {
    sun.updateMatrixWorld(); sun.target.updateMatrixWorld();
    const lc = sun.shadow.camera; lc.position.copy(sun.position); lc.lookAt(sun.target.position); lc.updateMatrixWorld();
    const inv = lc.matrixWorldInverse, b = new THREE.Box3(), v = new THREE.Vector3();
    for (const sx of [-1, 1]) for (const sz of [-1, 1]) for (const y of [0, HMAX + TRAY_TOP + .1]) b.expandByPoint(v.set(sx * TRAY.w / 2, y, sz * TRAY.d / 2).applyMatrix4(inv));
    for (const sx of [-1, 1]) for (const sz of [-1, 1]) b.expandByPoint(v.set(sx * (TRAY.w / 2 + 1.2), 0, sz * (TRAY.d / 2 + 1.2)).applyMatrix4(inv));
    Object.assign(lc, { left: b.min.x - .1, right: b.max.x + .1, bottom: b.min.y - .1, top: b.max.y + .1, near: Math.max(.1, -b.max.z - 1), far: -b.min.z + 1 });
    lc.updateProjectionMatrix();
  }
  sun.shadow.bias = -.0004; sun.shadow.normalBias = .01; sun.shadow.radius = 3;
  sun.shadow.autoUpdate = false; sun.shadow.needsUpdate = true;

  /* ---- stack layout: n full slabs + a fraction slab (≥ ¼ slab tall), graded jūbako colours, lid on the sunset stack */
  const _m4 = new THREE.Matrix4();
  function layout() {
    let moved = false;
    for (const bar of bars) {
      const H = Math.max(0, bar.x);
      let n = Math.min(MAXB, Math.floor((H + 1e-4) / U_H)), rem = H - n * U_H;
      const hasFrac = rem > U_H * .06;
      const th = hasFrac ? Math.max(rem, U_H * FRAC_MIN) - SEAM : 0;
      const key = `${n}|${th.toFixed(4)}`;
      if (key === bar.last) continue;
      bar.last = key; moved = true;
      bar.unit.setH(U_H - SEAM);
      for (let k = 0; k < n; k++) bar.inst.setMatrixAt(k, _m4.makeTranslation(0, k * U_H + (U_H - SEAM) / 2, 0));
      bar.inst.count = n; bar.inst.instanceMatrix.needsUpdate = true;
      bar.frac.visible = hasFrac && th > .01;
      if (bar.frac.visible) { bar.fracB.setH(th); bar.frac.position.y = n * U_H + th / 2; }
      let top = bar.frac.visible ? n * U_H + th : Math.max(0, n * U_H - SEAM);
      if (bar.key === 'sunset') {
        for (let k = 0; k < n; k++) bar.inst.setColorAt(k, new THREE.Color().setScalar(bar.tones[k] * .08 + .95));
        bar.inst.instanceColor.needsUpdate = true;
        JUF.uH.value = Math.max(th, .01);
        bar.lid.visible = top > .01; bar.lid.position.y = top + SEAM + LID / 2;
        if (bar.lid.visible) top += SEAM + LID;
      } else if (bar.key === 'grid') bar.fracMat.color.copy(bar.inst.material.color).multiplyScalar(bar.tones[n] ?? 1);
      bar.H = top;
    }
    bars.forEach((bar, i) => { bar.top.set(bar.g.position.x, TRAY_TOP + bar.H + .01, 0); TOPY[i].uTopY.value = TRAY_TOP + (bar.lid ? bar.H - LID - SEAM : bar.H); });
    return moved;
  }

  /* ---- camera: fit to height, but the tray never narrower than ~70 % of the visible stage; centred on the tray */
  const view = { az: .42, el: .3, d: 10, target: new THREE.Vector3(0, 1, 0), goalD: 10, goalT: new THREE.Vector3(0, 1, 0), key: '', snap: true, botPad: 20 };
  const tmpCam = new THREE.PerspectiveCamera(22, 1, .1, 120), _v = new THREE.Vector3();
  const ROW_GAP = 20, MIN_TRAY = .62;   // the tray never narrower than this share of the visible stage
  function place(cam, az, el, d, tgt) {
    cam.position.set(tgt.x + Math.sin(az) * Math.cos(el) * d, tgt.y + Math.sin(el) * d, tgt.z + Math.cos(az) * Math.cos(el) * d);
    cam.lookAt(tgt); cam.updateMatrixWorld(); cam.updateProjectionMatrix();
  }
  /** Labels sit exactly above their stack's top centre (vertical leaders). All start on one row just above the tallest
      stack; a label that would touch one already placed on its row moves up a row. Returns [{ x, y (label bottom), row }]. */
  const LGAP = 12;
  function solveLabels(pts) {   // pts: [{ x, y }] stack-top screen points
    const base = Math.min(...pts.map(p => p.y)) - ROW_GAP, placed = [], out = [];
    for (const i of [0, 2, 1]) {
      const [w, lh, gap] = bars[i].size; let row = 0;
      const hit = r => placed.some(p => p.row === r && Math.abs(p.x - pts[i].x) < (p.w + w) / 2 + LGAP);
      while (hit(row) && row < 3) row++;
      placed.push({ x: pts[i].x, w, row });
      out[i] = { x: pts[i].x, y: base - row * (lh + gap + 8), row, w, h: lh + gap };
    }
    return out;
  }
  function fit(w, h, vis0, vis1, Hs) {
    tmpCam.fov = camera.fov; tmpCam.aspect = w / h;
    const tray = [], tops = [];
    for (const sx of [-1, 1]) for (const sz of [-1, 1]) for (const y of [0, TRAY_TOP]) tray.push(new THREE.Vector3(sx * TRAY.w / 2, y, sz * TRAY.d / 2));
    Hs.forEach((H, i) => tops.push(new THREE.Vector3(BAR_X[i], TRAY_TOP + H + (i === 2 ? LID + SEAM : 0) + .01, 0)));
    const myTop = 14, myBot = view.botPad, visW = vis1 - vis0, cx = (vis0 + vis1) / 2;
    const bounds = (d, tgt) => {
      place(tmpCam, view.az, view.el, d, tgt);
      let tx0 = 1e9, tx1 = -1e9, y0 = 1e9, y1 = -1e9;
      const pr = p => { _v.copy(p).project(tmpCam); return [(_v.x * .5 + .5) * w, (-_v.y * .5 + .5) * h]; };
      for (const p of tray) { const [x, y] = pr(p); tx0 = Math.min(tx0, x); tx1 = Math.max(tx1, x); y1 = Math.max(y1, y); }
      const L = solveLabels(tops.map(p => { const [x, y] = pr(p); return { x, y }; }));
      let lx0 = tx0, lx1 = tx1;
      for (const l of L) { y0 = Math.min(y0, l.y - l.h); lx0 = Math.min(lx0, l.x - l.w / 2); lx1 = Math.max(lx1, l.x + l.w / 2); }
      return { tx0, tx1, y0, y1, lx0, lx1 };
    };
    const tgt = view.goalT.clone(); let d = 10;
    for (let it = 0; it < 5; it++) {
      // distance: the smallest that fits height and keeps the tray inside the stage; never so far the tray drops under 70 %
      let lo = 2, hi = 60;
      for (let k = 0; k < 22; k++) { const mid = (lo + hi) / 2, b = bounds(mid, tgt); ((b.y1 - b.y0) <= h - myTop - myBot && b.tx1 - b.tx0 <= visW * .9 && b.lx1 - b.lx0 <= visW - 16) ? hi = mid : lo = mid; }
      const dFit = hi;
      lo = 2; hi = 60;
      for (let k = 0; k < 22; k++) { const mid = (lo + hi) / 2, b = bounds(mid, tgt); (b.tx1 - b.tx0 >= visW * MIN_TRAY) ? lo = mid : hi = mid; }
      const d70 = lo;
      d = Math.min(dFit, d70);
      const b = bounds(d, tgt);
      const right = new THREE.Vector3().setFromMatrixColumn(tmpCam.matrixWorld, 0), up = new THREE.Vector3().setFromMatrixColumn(tmpCam.matrixWorld, 1);
      const wpp = 2 * d * Math.tan(THREE.MathUtils.degToRad(tmpCam.fov) / 2) / h;
      // horizontal: centre the tray, then slide just enough to keep every label inside the stage
      let dx = (b.tx0 + b.tx1) / 2 - cx;
      if (b.lx0 - dx < vis0 + 8) dx = b.lx0 - (vis0 + 8); else if (b.lx1 - dx > vis1 - 8) dx = b.lx1 - (vis1 - 8);
      // vertical: centre the whole (labels … tray) if it fits; otherwise keep the tray's foot on the bottom margin and let the stack rise
      const dy = (b.y1 - b.y0) <= h - myTop - myBot ? ((b.y0 + b.y1) / 2 - (myTop + h - myBot) / 2) : (b.y1 - (h - myBot));
      tgt.addScaledVector(right, dx * wpp).addScaledVector(up, -dy * wpp);
    }
    view.goalD = d; view.goalT.copy(tgt);
  }

  /* ---- state */
  const settleNow = REDUCED || Q.has('freeze');
  if (Q.has('bill') && !document.getElementById('bill')) STATE.set('bill', +Q.get('bill'));   // lab only
  let intro = settleNow ? 1e3 : -1, lastBill = -1, tgt = targets(STATE.bill), frame = 0;
  const ptr = { x: 0, y: 0 };
  if (settleNow) bars.forEach((bar, i) => { bar.x = tgt[i]; });
  layout();

  return {
    scene, camera,
    tone: 'aces', exposure: 1.02,   // direct path: MSAA
    anchors: Object.fromEntries(bars.map(b => [b.key, b.anchor])),
    anchorOn(name) { const i = KEYS.indexOf(name); return i < 0 || bars[i].H > .6 * tgt[i]; },
    update(dt, t, s) {
      const vis0 = Math.max(0, -s.rect.left), vis1 = Math.min(s.w, VP.w - s.rect.left);
      if (frame % 20 === 0) {
        const lg = ctx.host.parentElement?.querySelector('.chart-legend');   // keep the tray clear of the DOM legend under the chart
        if (lg) { const lr = lg.getBoundingClientRect(); view.botPad = Math.max(20, Math.round(s.rect.bottom - lr.top + 14)); }
        for (const b of bars) {
          const el = ctx.host.querySelector(`.gl-anchor[data-anchor="${b.key}"]`)?.firstElementChild;
          if (el && el.offsetWidth) { const ns = [el.offsetWidth, el.offsetHeight, 12]; if (!b.measured || ns[0] !== b.size[0] || ns[1] !== b.size[1]) { b.size = ns; b.measured = true; view.key = ''; } }
        }
      }
      frame++;
      const key = `${s.w.toFixed(0)}x${s.h.toFixed(0)}x${vis0.toFixed(0)}x${vis1.toFixed(0)}x${STATE.bill}x${view.botPad}`;
      if (key !== view.key) { view.key = key; view.el = s.w < 600 ? .34 : .28; fit(s.w, s.h, vis0, vis1, targets(STATE.bill)); }
      if (view.snap || REDUCED) { view.d = view.goalD; view.target.copy(view.goalT); view.snap = false; }
      else { const k = 1 - Math.exp(-2.6 * dt); view.d += (view.goalD - view.d) * k; view.target.lerp(view.goalT, k); }

      // stacks follow the bill on a soft damped spring
      if (STATE.bill !== lastBill) { lastBill = STATE.bill; tgt = targets(lastBill); }
      if (intro < 0 && s.progress > .12) intro = 0;
      if (intro >= 0) intro += dt;
      const sub = 4, h = dt / sub, kS = 38, cS = 2 * Math.sqrt(kS) * .8;
      bars.forEach((bar, i) => {
        const goal = intro > i * .16 ? tgt[i] : 0;
        if (REDUCED) { bar.x = goal; bar.v = 0; return; }
        for (let n = 0; n < sub; n++) { bar.v += (kS * (goal - bar.x) - cS * bar.v) * h; bar.x += bar.v * h; }
      });
      if (layout()) sun.shadow.needsUpdate = true;

      // camera: pointer parallax + a slow idle drift
      const px = REDUCED ? 0 : clamp(s.pointer.x, -1, 1), py = REDUCED ? 0 : clamp(s.pointer.y, -1, 1);
      ptr.x = damp(ptr.x, px, 2.6, dt); ptr.y = damp(ptr.y, py, 2.6, dt);
      const idle = REDUCED ? 0 : 1;
      place(camera, view.az + ptr.x * .05 + Math.sin(t * .23) * .01 * idle, view.el - ptr.y * .025 + Math.sin(t * .17 + 1) * .005 * idle, view.d, view.target);
      FADE.value.set(-1 + 2 * vis0 / s.w, -1 + 2 * vis1 / s.w, 0, 0);

      // labels: exactly above each stack's top centre, one row (a label that would touch another rises a row); vertical leaders
      const scr = bars.map(b => { _v.copy(b.top).project(camera); return { x: (_v.x * .5 + .5) * s.w, y: (-_v.y * .5 + .5) * s.h, z: _v.z }; });
      const L = solveLabels(scr);
      bars.forEach((b, i) => {
        const x = scr[i].x, y = L[i].y;
        b.lx = x; b.ly = b.ly === null || REDUCED ? y : damp(b.ly, y, 10, dt);
        b.anchor.set(x / s.w * 2 - 1, -(b.ly / s.h * 2 - 1), scr[i].z).unproject(camera);
        _v.set(x / s.w * 2 - 1, -((b.ly - b.size[2] + 4) / s.h * 2 - 1), scr[i].z).unproject(camera);
        const lp = b.lead.geometry.attributes.position; lp.setXYZ(0, b.top.x, b.top.y, b.top.z); lp.setXYZ(1, _v.x, _v.y, _v.z); lp.needsUpdate = true;
        b.lead.material.opacity = .34 * clamp((scr[i].y - b.ly - b.size[2]) / 10);
      });
    },
  };
}
