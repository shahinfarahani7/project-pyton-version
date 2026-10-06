/* HDR post chain for one scene host.
   scene -> HalfFloat RT (+ depth texture) -> [god rays from sky pixels near the sun] + [dual-filter bloom]
   -> composite (exposure, ACES/AgX with hue-preserving blend, grade, vignette, grain) -> FXAA -> canvas.
   Output is premultiplied and blended over the page ground, so transparent scene backgrounds show the paper.
   Sky meshes must use depthWrite:false: the ray pass treats depth==1 as sky. */
import * as THREE from 'three';

const VS = /* glsl */`varying vec2 vUv; void main(){ vUv = uv; gl_Position = vec4(position.xy, 0., 1.); }`;
const quadGeo = new THREE.BufferGeometry();
quadGeo.setAttribute('position', new THREE.Float32BufferAttribute([-1, -1, 0, 3, -1, 0, -1, 3, 0], 3));
quadGeo.setAttribute('uv', new THREE.Float32BufferAttribute([0, 0, 2, 0, 0, 2], 2));
const quadCam = new THREE.OrthographicCamera(-1, 1, 1, -1, 0, 1);
function pass(fs, uniforms, opts = {}) {
  const m = new THREE.ShaderMaterial({ vertexShader: VS, fragmentShader: fs, uniforms, depthTest: false, depthWrite: false, ...opts });
  const mesh = new THREE.Mesh(quadGeo, m); mesh.frustumCulled = false;
  const sc = new THREE.Scene(); sc.add(mesh);
  return { m, u: uniforms, draw(r, target) { r.setRenderTarget(target); r.render(sc, quadCam); } };
}
const rt = (w, h, type = THREE.HalfFloatType, extra = {}) => new THREE.WebGLRenderTarget(Math.max(1, w), Math.max(1, h), { type, minFilter: THREE.LinearFilter, magFilter: THREE.LinearFilter, depthBuffer: false, ...extra });

const COMMON = /* glsl */`
float luma(vec3 c){ return dot(c, vec3(.2126,.7152,.0722)); }
float hash12(vec2 p){ vec3 p3 = fract(vec3(p.xyx) * .1031); p3 += dot(p3, p3.yzx + 33.33); return fract((p3.x + p3.y) * p3.z); }`;

const RAYS_FS = /* glsl */`
uniform sampler2D tColor; uniform sampler2D tDepth; uniform sampler2D tPrev; uniform int uFirst;
uniform vec2 uSun; uniform float uAspect, uDensity, uDecay, uWeight, uThresh, uFalloff, uSunOn;
varying vec2 vUv;
${COMMON}
vec3 mask(vec2 p){
  if (p.x < 0. || p.y < 0. || p.x > 1. || p.y > 1.) return vec3(0.);
  float sky = step(.99995, texture2D(tDepth, p).r);
  vec3 c = texture2D(tColor, p).rgb;
  vec2 d = (p - uSun) * vec2(uAspect, 1.);
  float fall = exp(-dot(d, d) * uFalloff);
  return sky * max(c - uThresh, 0.) * fall;
}
void main(){
  const int N = 36;
  vec2 delta = (vUv - uSun) * uDensity / float(N);
  vec2 p = vUv; float il = 1.; vec3 acc = vec3(0.);
  float j = hash12(gl_FragCoord.xy);
  p -= delta * j;
  for (int i = 0; i < N; i++) {
    p -= delta;
    vec3 s = uFirst == 1 ? mask(p) : texture2D(tPrev, p).rgb;
    acc += s * il * uWeight; il *= uDecay;
  }
  gl_FragColor = vec4(acc * uSunOn, 1.);
}`;

const PREFILTER_FS = /* glsl */`
uniform sampler2D tIn; uniform vec2 uTexel; uniform float uThresh, uKnee; varying vec2 vUv;
${COMMON}
void main(){
  vec3 c = texture2D(tIn, vUv + uTexel * vec2(-1,-1)).rgb + texture2D(tIn, vUv + uTexel * vec2(1,-1)).rgb
         + texture2D(tIn, vUv + uTexel * vec2(-1,1)).rgb + texture2D(tIn, vUv + uTexel * vec2(1,1)).rgb;
  c *= .25;
  float br = max(c.r, max(c.g, c.b));
  float rq = clamp(br - uThresh + uKnee, 0., 2. * uKnee); rq = rq * rq / (4. * uKnee + 1e-4);
  float w = max(rq, br - uThresh) / max(br, 1e-4);
  gl_FragColor = vec4(min(c * w, vec3(64.)), 1.);
}`;
const DOWN_FS = /* glsl */`
uniform sampler2D tIn; uniform vec2 uTexel; varying vec2 vUv;
void main(){
  vec3 s = texture2D(tIn, vUv).rgb * 4.;
  s += texture2D(tIn, vUv + uTexel * vec2(-1,-1)).rgb + texture2D(tIn, vUv + uTexel * vec2(1,-1)).rgb
     + texture2D(tIn, vUv + uTexel * vec2(-1,1)).rgb + texture2D(tIn, vUv + uTexel * vec2(1,1)).rgb;
  gl_FragColor = vec4(s / 8., 1.);
}`;
const UP_FS = /* glsl */`
uniform sampler2D tIn; uniform sampler2D tAdd; uniform vec2 uTexel; uniform float uRadius; varying vec2 vUv;
void main(){
  vec2 o = uTexel * uRadius;
  vec3 s = texture2D(tIn, vUv + vec2(-o.x, 0.)).rgb + texture2D(tIn, vUv + vec2(o.x, 0.)).rgb
         + texture2D(tIn, vUv + vec2(0., -o.y)).rgb + texture2D(tIn, vUv + vec2(0., o.y)).rgb;
  s = s * 2. + texture2D(tIn, vUv + vec2(-o.x,-o.y)).rgb + texture2D(tIn, vUv + vec2(o.x,-o.y)).rgb
             + texture2D(tIn, vUv + vec2(-o.x, o.y)).rgb + texture2D(tIn, vUv + vec2(o.x, o.y)).rgb;
  gl_FragColor = vec4(s / 12. + texture2D(tAdd, vUv).rgb, 1.);
}`;

const COMPOSITE_FS = /* glsl */`
uniform sampler2D tScene, tBloom, tRays;
uniform float uExposure, uBloom, uRays, uTone, uHue, uSat, uContrast, uVignette, uGrain, uTime, uAspect, uHasBloom, uHasRays;
uniform vec3 uRayTint, uShadowTint, uHighTint, uLift;
varying vec2 vUv;
${COMMON}
vec3 RRTAndODTFit(vec3 v){ vec3 a = v * (v + .0245786) - .000090537; vec3 b = v * (.983729 * v + .4329510) + .238081; return a / b; }
vec3 aces(vec3 c){
  const mat3 I = mat3(vec3(.59719,.07600,.02840), vec3(.35458,.90834,.13383), vec3(.04823,.01566,.83777));
  const mat3 O = mat3(vec3(1.60475,-.10208,-.00327), vec3(-.53108,1.10813,-.07276), vec3(-.07367,-.00605,1.07602));
  c /= .6; c = I * c; c = RRTAndODTFit(c); c = O * c; return clamp(c, 0., 1.);
}
vec3 agxC(vec3 x){ vec3 x2 = x * x; vec3 x4 = x2 * x2; return 15.5 * x4 * x2 - 40.14 * x4 * x + 31.96 * x4 - 6.868 * x2 * x + .4298 * x2 + .1191 * x - .00232; }
vec3 agx(vec3 c){
  const mat3 S2R = mat3(vec3(.6274,.0691,.0164), vec3(.3293,.9195,.0880), vec3(.0433,.0113,.8956));
  const mat3 R2S = mat3(vec3(1.6605,-.1246,-.0182), vec3(-.5876,1.1329,-.1006), vec3(-.0728,-.0083,1.1187));
  const mat3 IN = mat3(vec3(.856627153315983,.137318972929847,.11189821299995), vec3(.0951212405381588,.761241990602591,.0767994186031903), vec3(.0482516061458583,.101439036467562,.811302368396859));
  const mat3 OUT = mat3(vec3(1.1271005818144368,-.1413297634984383,-.14132976349843826), vec3(-.11060664309660323,1.157823702216272,-.11060664309660294), vec3(-.016493938717834573,-.016493938717834257,1.2519364065950405));
  c = S2R * c; c = IN * c; c = max(c, 1e-10); c = log2(c); c = (c + 12.47393) / 16.500999; c = clamp(c, 0., 1.);
  c = agxC(c); c = OUT * c; c = pow(max(vec3(0.), c), vec3(2.2)); c = R2S * c; return clamp(c, 0., 1.);
}
vec3 tm(vec3 c){ return uTone < .5 ? aces(c) : agx(c); }
vec3 toSRGB(vec3 c){ return mix(c * 12.92, 1.055 * pow(c, vec3(1. / 2.4)) - .055, step(.0031308, c)); }
void main(){
  vec4 s = texture2D(tScene, vUv);
  vec3 add = vec3(0.);
  if (uHasBloom > .5) add += texture2D(tBloom, vUv).rgb * uBloom;
  if (uHasRays > .5) add += texture2D(tRays, vUv).rgb * uRays * uRayTint;
  vec3 hdr = (s.rgb + add) * uExposure;
  vec3 ldr = tm(hdr);
  float L = luma(hdr), tl = luma(tm(vec3(L)));
  vec3 hp = clamp(hdr * (tl / max(L, 1e-4)), 0., 1.);
  ldr = mix(ldr, hp, uHue);
  // grade in display-linear
  float y = luma(ldr);
  ldr = mix(vec3(y), ldr, uSat);
  ldr = ldr + uLift * (1. - ldr);
  ldr *= mix(uShadowTint, uHighTint, smoothstep(.05, .75, y));
  ldr = clamp((ldr - .18) * uContrast + .18, 0., 1.);
  vec2 d = (vUv - .5) * vec2(uAspect, 1.);
  ldr *= mix(1., smoothstep(1.35, .25, length(d)), uVignette);
  vec3 o = toSRGB(ldr);
  o += (hash12(gl_FragCoord.xy + fract(uTime) * 91.7) - .5) * uGrain;
  float a = clamp(s.a + luma(add) * 1.5, 0., 1.);
  gl_FragColor = vec4(o, a);            // premultiplied: transparent pixels carry only bloom/ray light
}`;

const FXAA_FS = /* glsl */`
uniform sampler2D tIn; uniform vec2 uTexel; varying vec2 vUv;
${COMMON}
void main(){
  vec4 cM = texture2D(tIn, vUv);
  float lM = luma(cM.rgb), lN = luma(texture2D(tIn, vUv + vec2(0., uTexel.y)).rgb), lS = luma(texture2D(tIn, vUv - vec2(0., uTexel.y)).rgb);
  float lE = luma(texture2D(tIn, vUv + vec2(uTexel.x, 0.)).rgb), lW = luma(texture2D(tIn, vUv - vec2(uTexel.x, 0.)).rgb);
  float mn = min(lM, min(min(lN, lS), min(lE, lW))), mx = max(lM, max(max(lN, lS), max(lE, lW)));
  float range = mx - mn;
  if (range < max(.0312, mx * .125)) { gl_FragColor = cM; return; }
  float lNW = luma(texture2D(tIn, vUv + uTexel * vec2(-1., 1.)).rgb), lNE = luma(texture2D(tIn, vUv + uTexel).rgb);
  float lSW = luma(texture2D(tIn, vUv - uTexel).rgb), lSE = luma(texture2D(tIn, vUv + uTexel * vec2(1., -1.)).rgb);
  vec2 dir = vec2(-((lNW + lNE) - (lSW + lSE)), ((lNW + lSW) - (lNE + lSE)));
  float red = max((lNW + lNE + lSW + lSE) * .03125, .0078125);
  float rcp = 1. / (min(abs(dir.x), abs(dir.y)) + red);
  dir = clamp(dir * rcp, -8., 8.) * uTexel;
  vec4 A = .5 * (texture2D(tIn, vUv + dir * (1. / 3. - .5)) + texture2D(tIn, vUv + dir * (2. / 3. - .5)));
  vec4 B = A * .5 + .25 * (texture2D(tIn, vUv - dir * .5) + texture2D(tIn, vUv + dir * .5));
  float lB = luma(B.rgb);
  gl_FragColor = (lB < mn || lB > mx) ? A : B;
}`;

const _v = new THREE.Vector3();
export const DEFAULT_POST = {
  exposure: 1, tone: 'aces', hue: .35, sat: 1.04, contrast: 1.04, vignette: .22, grain: .018, lift: [0, 0, 0],
  shadowTint: [1, 1, 1], highTint: [1, 1, 1], ss: 1,
  bloom: { strength: .55, radius: 1, threshold: 1.2, knee: .6 },
  rays: null,  // { sun: Vector3 (world), strength: 1, tint: [1,.8,.6], density: .9, decay: .955, weight: .045, threshold: .6, falloff: 1.5 }
};

export class Post {
  constructor(opts = {}) {
    this.o = { ...DEFAULT_POST, ...opts, bloom: opts.bloom === null ? null : { ...DEFAULT_POST.bloom, ...(opts.bloom || {}) }, rays: opts.rays ? { strength: 1, tint: [1, .78, .56], density: .92, decay: .958, weight: .032, threshold: 1.2, falloff: 3.2, ...opts.rays } : null };
    this.w = 0; this.h = 0; this.mips = [];
    this.prefilter = pass(PREFILTER_FS, { tIn: { value: null }, uTexel: { value: new THREE.Vector2() }, uThresh: { value: 1 }, uKnee: { value: .5 } });
    this.down = pass(DOWN_FS, { tIn: { value: null }, uTexel: { value: new THREE.Vector2() } });
    this.up = pass(UP_FS, { tIn: { value: null }, tAdd: { value: null }, uTexel: { value: new THREE.Vector2() }, uRadius: { value: 1 } });
    this.rays = pass(RAYS_FS, { tColor: { value: null }, tDepth: { value: null }, tPrev: { value: null }, uFirst: { value: 1 }, uSun: { value: new THREE.Vector2(.5, .5) }, uAspect: { value: 1 }, uDensity: { value: .9 }, uDecay: { value: .95 }, uWeight: { value: .05 }, uThresh: { value: .5 }, uFalloff: { value: 1.5 }, uSunOn: { value: 1 } });
    this.comp = pass(COMPOSITE_FS, {
      tScene: { value: null }, tBloom: { value: null }, tRays: { value: null }, uExposure: { value: 1 }, uBloom: { value: .5 }, uRays: { value: 1 }, uTone: { value: 0 }, uHue: { value: .3 },
      uSat: { value: 1 }, uContrast: { value: 1 }, uVignette: { value: .2 }, uGrain: { value: .03 }, uTime: { value: 0 }, uAspect: { value: 1 }, uHasBloom: { value: 1 }, uHasRays: { value: 0 },
      uRayTint: { value: new THREE.Vector3(1, .8, .6) }, uShadowTint: { value: new THREE.Vector3(1, 1, 1) }, uHighTint: { value: new THREE.Vector3(1, 1, 1) }, uLift: { value: new THREE.Vector3() },
    });
    this.fxaa = pass(FXAA_FS, { tIn: { value: null }, uTexel: { value: new THREE.Vector2() } }, { transparent: true, blending: THREE.CustomBlending, blendSrc: THREE.OneFactor, blendDst: THREE.OneMinusSrcAlphaFactor, blendSrcAlpha: THREE.OneFactor, blendDstAlpha: THREE.OneMinusSrcAlphaFactor });
  }
  setSize(w, h) {
    w = Math.max(2, Math.round(w)); h = Math.max(2, Math.round(h));
    if (w === this.w && h === this.h) return;
    this.w = w; this.h = h;
    this.dispose(true);
    const depthTexture = new THREE.DepthTexture(w, h); depthTexture.type = THREE.UnsignedIntType;
    this.rtScene = rt(w, h, THREE.HalfFloatType, { depthBuffer: true, depthTexture });
    this.rtLDR = rt(w, h, THREE.UnsignedByteType);
    const hw = Math.ceil(w / 2), hh = Math.ceil(h / 2);
    this.rtRayA = rt(hw, hh); this.rtRayB = rt(hw, hh);
    this.mips = []; let mw = hw, mh = hh;
    for (let i = 0; i < 6 && mw > 4 && mh > 4; i++) { this.mips.push({ d: rt(mw, mh), u: rt(mw, mh), w: mw, h: mh }); mw = Math.ceil(mw / 2); mh = Math.ceil(mh / 2); }
  }
  dispose(keepPasses) {
    for (const k of ['rtScene', 'rtLDR', 'rtRayA', 'rtRayB']) { this[k]?.depthTexture?.dispose(); this[k]?.dispose(); this[k] = null; }
    for (const m of this.mips) { m.d.dispose(); m.u.dispose(); } this.mips = [];
    if (!keepPasses) for (const p of [this.prefilter, this.down, this.up, this.rays, this.comp, this.fxaa]) p.m.dispose();
  }
  /** rect / clip in CSS px, viewport coords (y down). dpr = device pixel ratio. */
  render(r, scene, camera, rect, clip, dpr, t) {
    const o = this.o, ss = o.ss || 1;
    this.setSize(rect.width * dpr * ss, rect.height * dpr * ss);
    const oldTM = r.toneMapping; r.toneMapping = THREE.NoToneMapping;
    // 1. scene -> HDR
    r.getClearColor(this._cc = this._cc || new THREE.Color()); const ca = r.getClearAlpha();
    r.setRenderTarget(this.rtScene); r.setClearColor(0x000000, 0); r.clear(true, true, false); r.setClearColor(this._cc, ca);
    r.render(scene, camera);
    // 2. god rays
    const cu = this.comp.u;
    cu.uHasRays.value = 0;
    if (o.rays && o.rays.sun) {
      _v.copy(o.rays.sun).project(camera);
      const behind = _v.z > 1;
      const ru = this.rays.u;
      ru.uSun.value.set(_v.x * .5 + .5, _v.y * .5 + .5); ru.uAspect.value = this.w / this.h;
      ru.uDensity.value = o.rays.density; ru.uDecay.value = o.rays.decay; ru.uWeight.value = o.rays.weight;
      ru.uThresh.value = o.rays.threshold; ru.uFalloff.value = o.rays.falloff; ru.uSunOn.value = behind ? 0 : 1;
      ru.tColor.value = this.rtScene.texture; ru.tDepth.value = this.rtScene.depthTexture;
      ru.uFirst.value = 1; ru.tPrev.value = this.rtRayB.texture; this.rays.draw(r, this.rtRayA);   // never leave the target bound as an input
      ru.uFirst.value = 0; ru.tPrev.value = this.rtRayA.texture; ru.uDensity.value = o.rays.density * .35; ru.uWeight.value = 1 / 36 * 1.6; ru.uDecay.value = .99;
      this.rays.draw(r, this.rtRayB);
      cu.tRays.value = this.rtRayB.texture; cu.uHasRays.value = 1; cu.uRays.value = o.rays.strength; cu.uRayTint.value.set(...o.rays.tint);
    }
    // 3. bloom (dual filter)
    cu.uHasBloom.value = 0;
    if (o.bloom && this.mips.length > 2 && o.bloom.strength > 0) {
      const pf = this.prefilter.u; pf.tIn.value = this.rtScene.texture; pf.uTexel.value.set(1 / this.w, 1 / this.h); pf.uThresh.value = o.bloom.threshold; pf.uKnee.value = o.bloom.knee;
      this.prefilter.draw(r, this.mips[0].d);
      for (let i = 1; i < this.mips.length; i++) { const du = this.down.u; du.tIn.value = this.mips[i - 1].d.texture; du.uTexel.value.set(1 / this.mips[i - 1].w, 1 / this.mips[i - 1].h); this.down.draw(r, this.mips[i].d); }
      let src = this.mips[this.mips.length - 1].d;
      for (let i = this.mips.length - 2; i >= 0; i--) { const uu = this.up.u; uu.tIn.value = src.texture; uu.tAdd.value = this.mips[i].d.texture; uu.uTexel.value.set(1 / this.mips[i + 1].w, 1 / this.mips[i + 1].h); uu.uRadius.value = o.bloom.radius; this.up.draw(r, this.mips[i].u); src = this.mips[i].u; }
      cu.tBloom.value = src.texture; cu.uHasBloom.value = 1; cu.uBloom.value = o.bloom.strength;
    }
    // 4. composite -> LDR
    cu.tScene.value = this.rtScene.texture; cu.uExposure.value = o.exposure; cu.uTone.value = o.tone === 'agx' ? 1 : 0; cu.uHue.value = o.hue;
    cu.uSat.value = o.sat; cu.uContrast.value = o.contrast; cu.uVignette.value = o.vignette; cu.uGrain.value = o.grain; cu.uTime.value = t;
    cu.uAspect.value = this.w / this.h; cu.uShadowTint.value.set(...o.shadowTint); cu.uHighTint.value.set(...o.highTint); cu.uLift.value.set(...o.lift);
    this.comp.draw(r, this.rtLDR);
    // 5. FXAA -> canvas, inside this host's viewport, clipped to what is on screen
    r.setRenderTarget(null);
    const H = r.domElement.clientHeight || innerHeight;
    r.setViewport(rect.left, H - rect.bottom, rect.width, rect.height);
    r.setScissor(clip.left, H - clip.bottom, clip.width, clip.height); r.setScissorTest(true);
    this.fxaa.u.tIn.value = this.rtLDR.texture; this.fxaa.u.uTexel.value.set(1 / this.w, 1 / this.h);
    this.fxaa.draw(r, null);
    r.setScissorTest(false);
    r.toneMapping = oldTM;
  }
}
