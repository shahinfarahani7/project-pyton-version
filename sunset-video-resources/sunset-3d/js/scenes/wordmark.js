/* Footer wordmark: "Sunset" in Instrument Serif as near-black urushi-lacquer letters standing in a calm evening sea,
   the sun setting behind the "n". Everything the sun does is traced from one occlusion mask of the word seen from the
   sun: the lanes of light through the gaps that cross the sea haze toward the camera, the glitter they leave on the
   water, and nothing else. The sea is a planar mirror broken by ripples; the letters are dark lacquer that mirrors
   the sky behind the viewer (violet above, warm rose toward the waterline) with only a soft Fresnel rim.
   Glyph outlines: Instrument Serif Regular (OFL), converted with fontTools (quadratic 'q' commands, 1000 upm). */
import { THREE, clamp, lerp, damp, smooth, REDUCED } from '../core.js';
import { Font } from 'three/addons/loaders/FontLoader.js';
import { Reflector } from 'three/addons/objects/Reflector.js';
import { toCreasedNormals } from 'three/addons/utils/BufferGeometryUtils.js';

const GLYPHS = {
  S: { ha: 407, o: 'm 184 -9 q 140 -5 164 -9 q 94 5 115 -1 q 60 18 72 11 q 50 26 53 22 q 46 42 46 31 l 41 199 q 54 219 41 219 q 69 201 65 219 l 78 163 q 205 20 112 20 q 284 54 255 20 q 314 148 314 87 q 284 258 314 207 q 186 359 253 309 q 78 462 112 412 q 44 567 44 511 q 96 686 44 641 q 227 730 147 730 q 285 723 257 730 q 331 703 313 716 q 340 694 337 699 q 344 681 344 689 l 347 530 q 334 513 347 513 q 321 527 325 513 l 314 552 q 268 664 292 629 q 201 700 245 700 q 132 672 158 700 q 107 593 107 644 q 135 511 107 550 q 233 416 163 472 q 342 298 308 355 q 377 178 377 242 q 352 80 377 122 q 284 14 327 38 q 184 -9 240 -9 z' },
  u: { ha: 454, o: 'm 171 -9 q 123 2 146 -9 q 85 37 100 13 q 70 101 70 61 l 70 449 q 64 474 70 467 q 45 482 59 481 l 28 484 q 11 497 11 486 q 30 510 11 510 l 123 510 q 138 495 138 510 l 138 122 q 156 56 138 76 q 204 37 173 37 q 259 54 235 37 q 298 102 283 72 q 312 166 312 131 l 312 449 q 306 474 312 467 q 287 482 301 481 l 270 484 q 253 497 253 486 q 272 510 253 510 l 365 510 q 380 495 380 510 l 380 107 q 386 82 380 89 q 405 74 391 76 l 426 71 q 439 61 439 70 q 423 49 439 52 q 374 33 392 45 q 341 4 355 21 q 326 -5 332 -5 q 317 7 317 -5 l 317 53 q 312 62 317 61 q 300 58 306 64 q 234 6 263 21 q 171 -9 206 -9 z' },
  n: { ha: 470, o: 'm 30 0 q 15 11 15 0 q 28 23 15 20 l 40 25 q 68 38 61 29 q 74 67 74 46 l 74 403 q 68 428 74 421 q 49 436 63 434 l 28 439 q 15 450 15 440 q 31 461 15 458 q 78 477 62 466 q 113 504 95 488 q 128 513 122 513 q 137 501 137 513 l 137 456 q 144 444 137 447 q 158 450 150 442 q 228 502 198 488 q 293 516 259 516 q 365 484 338 516 q 392 392 392 453 l 392 67 q 398 38 392 46 q 426 26 405 29 l 448 23 q 459 11 459 21 q 447 0 459 0 l 279 0 q 265 11 265 0 q 276 23 265 21 l 290 25 q 318 37 311 28 q 324 67 324 46 l 324 381 q 306 450 324 430 q 255 470 288 470 q 198 452 223 470 q 157 402 172 433 q 142 335 142 372 l 142 67 q 148 37 142 46 q 176 26 155 28 l 203 23 q 214 12 214 21 q 199 0 214 0 z' },
  s: { ha: 308, o: 'm 131 -9 q 82 -4 108 -9 q 40 10 56 2 q 31 27 31 15 l 28 139 q 41 156 28 156 q 56 140 52 156 q 98 43 73 69 q 157 17 122 17 q 205 40 186 17 q 224 102 224 62 q 202 173 224 142 q 128 241 180 204 q 52 312 76 276 q 28 389 28 347 q 68 481 28 446 q 174 516 108 516 q 213 512 194 516 q 247 497 232 507 q 256 481 256 491 l 258 371 q 246 356 258 356 q 236 360 239 356 q 231 372 233 365 q 191 462 211 437 q 142 488 171 488 q 99 470 116 488 q 82 425 82 452 q 103 364 82 390 q 179 300 124 338 q 254 222 229 264 q 280 132 280 181 q 239 30 280 68 q 131 -9 198 -9 z' },
  e: { ha: 355, o: 'm 192 -9 q 106 23 144 -9 q 46 114 68 55 q 23 249 23 172 q 46 388 23 328 q 109 482 69 448 q 198 516 149 516 q 294 468 257 516 q 330 310 330 419 q 305 277 330 277 l 115 277 q 95 254 95 277 q 126 95 95 148 q 205 42 157 42 q 267 69 243 42 q 306 160 291 96 q 319 171 309 171 q 328 151 331 171 q 277 26 312 62 q 192 -9 242 -9 z m 112 302 l 213 302 q 261 352 261 302 q 245 454 261 417 q 197 491 229 491 q 132 446 158 491 q 97 318 105 401 q 112 302 95 302 z' },
  t: { ha: 259, o: 'm 147 -9 q 90 16 112 -9 q 67 96 67 40 l 67 470 q 55 482 67 482 l 26 482 q 10 494 10 482 q 19 508 10 502 q 72 558 52 531 q 107 630 92 584 q 124 651 114 651 q 135 635 135 651 l 135 524 q 149 510 135 510 l 214 510 q 230 496 230 510 q 214 482 230 482 l 149 482 q 135 468 135 482 l 135 95 q 142 60 135 73 q 168 48 149 48 q 202 69 189 48 q 220 137 216 90 q 233 151 222 151 q 245 136 245 151 q 214 25 242 59 q 147 -9 185 -9 z' },
};
const KERN = { Su: -8 };

const NOISE = /* glsl */`
float wH(vec2 p){ vec3 p3 = fract(vec3(p.xyx) * .1031); p3 += dot(p3, p3.yzx + 33.33); return fract((p3.x + p3.y) * p3.z); }
float wN(vec2 p){ vec2 i = floor(p), f = fract(p); f = f * f * (3. - 2. * f); return mix(mix(wH(i), wH(i + vec2(1,0)), f.x), mix(wH(i + vec2(0,1)), wH(i + vec2(1,1)), f.x), f.y); }
float wF(vec2 p){ float a = .5, s = 0.; for (int i = 0; i < 4; i++) { s += a * wN(p); p = mat2(1.6, 1.2, -1.2, 1.6) * p + 7.3; a *= .5; } return s; }`;

/* sky: late afterglow. The sun is ~3° below the sea; a rose-apricot rim hugs the horizon under it, magenta-rose above,
   mauve, then indigo overhead. Two cloud decks in perspective catch the afterglow on their undersides. Fuji and a low
   island stand in the haze on the horizon. Below the horizon the calm sea mirrors it all (environment only). */
const SKY = /* glsl */`
uniform vec3 uSunDir; uniform float uGlow, uCloudT, uFujiAz;
${NOISE}
float deck(vec3 d, float h, float sc, float cov, vec2 drift, float fw){
  vec2 q = d.xz / max(d.y, .004) * h * sc + drift;
  float lod = clamp(log2(max(fw * h * sc / max(d.y * d.y, 1e-5), 1e-4)) + 1.5, 0., 3.);   // fewer octaves where cells get small
  float n = wN(q) * .55 + wN(q * 2.1 + 3.1) * .28 * (1. - smoothstep(0., 1., lod)) + wN(q * 4.3 + 7.7) * .17 * (1. - smoothstep(1., 2., lod));
  return smoothstep(cov, cov + .16, n) * smoothstep(.006, .04, d.y);
}
vec3 skyCol(vec3 d, float disc, float clouds){
  float el = asin(clamp(d.y, -1., 1.)), e = abs(el);
  float az = atan(d.x, -d.z) - atan(uSunDir.x, -uSunDir.z);
  az = mod(az + 3.14159265, 6.2831853) - 3.14159265;
  float away = smoothstep(.7, 2.6, abs(az));
  vec3 hor = mix(vec3(.78, .34, .24), vec3(.2, .12, .2), away);
  vec3 rose = mix(vec3(.4, .16, .21), vec3(.12, .07, .15), away);
  vec3 mauve = mix(vec3(.15, .075, .16), vec3(.07, .045, .12), away);
  vec3 indigo = vec3(.04, .034, .1), night = vec3(.013, .013, .038);
  vec3 c = mix(hor, rose, smoothstep(.0, .035, e));
  c = mix(c, mauve, smoothstep(.03, .12, e));
  c = mix(c, indigo, smoothstep(.1, .28, e));
  c = mix(c, night, smoothstep(.28, .9, e));
  c += vec3(1.0, .42, .2) * exp(-e / .01) * exp(-az * az / (.3 * .3)) * uGlow;       // the afterglow rim on the sea line
  c += vec3(.3, .1, .13) * exp(-e / .05) * exp(-az * az / (.7 * .7)) * uGlow;
  c += vec3(.5, .22, .3) * away * exp(-pow((e - .05) / .05, 2.));                        // the belt of Venus behind the viewer (seen only in the lacquer)
  if (clouds > 0. && el > .004) {
    float fw = 1. / 900.;
    vec2 dr = vec2(uCloudT, uCloudT * .3);
    float lo = deck(d, 1., .9, .52, dr, fw), hi = deck(d, 2.6, .55, .6, dr * .6 + 11., fw) * (1. - lo);
    float lit = exp(-az * az / (.45 * .45)) * uGlow, low = exp(-e / .09);
    vec3 under = mix(vec3(.09, .05, .1), vec3(.75, .22, .2), lit * low) + vec3(.9, .35, .15) * lit * exp(-e / .03) * .8;
    vec3 thin = mix(vec3(.16, .08, .16), vec3(.9, .4, .3), lit * low);
    c = mix(c, mix(under, thin, .35), lo * .9);
    c = mix(c, mix(vec3(.1, .06, .13), vec3(.6, .2, .24), lit * low) * (1. + .3 * lit), hi * .55);
  }
  // Fuji (in the clear sky right of the word) and a long low island (left), hazed into the afterglow; edges antialiased
  float aa = max(fwidth(el), 2e-5) * 1.2;
  float fx = (az - uFujiAz) / .1, afx = abs(fx);
  float ridge = .0016 * (wN(vec2(az * 140., 0.)) - .5) + .0008 * (wN(vec2(az * 420., 3.)) - .5);
  float fuji = .036 * pow(clamp(1. - afx, 0., 1.), 1.55) + ridge * smoothstep(1., .2, afx);
  fuji = min(fuji, .0305 + .0008 * wN(vec2(az * 600., 1.)));                              // the flat summit crater rim
  float ix = (az + .31) / .13; float isl = .0075 * max(0., 1. - ix * ix) * (.55 + .45 * wN(vec2(az * 55., 5.))) + .003 * max(0., 1. - pow((az + .4) / .05, 2.));
  float land = max(fuji * step(afx, 1.), isl);
  float cover = smoothstep(land + aa, land - aa, el) * step(-.002, el) * step(.0001, land);
  vec3 landC = mix(vec3(.15, .07, .12), vec3(.1, .06, .12), away) * (.9 + .25 * smoothstep(0., .03, el));
  // snow on the upper third, in streaks down the gullies, catching the rose afterglow
  float snowLine = .021 + .005 * wN(vec2(az * 260., 7.)) - .004 * (1. - smoothstep(.0, .5, afx));
  float snow = smoothstep(snowLine - aa, snowLine + aa * 2., el) * step(afx, 1.) * smoothstep(.0, .012, fuji - isl);
  landC = mix(landC, vec3(.42, .26, .32), snow * .75);
  c = mix(c, mix(c, landC, .72), cover);
  c += vec3(38., 19., 7.) * 0. * disc;
  if (el < 0.) c = mix(c * .85, vec3(.02, .012, .018), smoothstep(-.01, -.3, el));
  return c;
}`;

export async function create(ctx) {
  const { renderer } = ctx;
  const VP = ctx.VP;
  const scene = new THREE.Scene();
  const camera = new THREE.PerspectiveCamera(20, 2, .5, 6000);

  /* ------------------------------------------------------------ sky dome (premultiplied fade into the page at the top) */
  const sunDir = new THREE.Vector3();
  const skyU = { uSunDir: { value: sunDir }, uGlow: { value: 1 }, uCloudT: { value: 0 }, uFujiAz: { value: .34 }, uResY: { value: 800 }, uFade: { value: new THREE.Vector2(.8, 1) }, uMain: { value: 1 }, uDisc: { value: 1 } };
  const skyMat = new THREE.ShaderMaterial({
    uniforms: skyU, side: THREE.BackSide, depthWrite: false,
    vertexShader: 'varying vec3 vDir; void main(){ vec4 w = modelMatrix * vec4(position, 1.); vDir = w.xyz - cameraPosition; gl_Position = projectionMatrix * viewMatrix * w; }',
    fragmentShader: SKY + `
      uniform float uResY, uMain, uDisc; uniform vec2 uFade; varying vec3 vDir;
      void main(){
        vec3 d = normalize(vDir);
        vec3 c = skyCol(d, uDisc, uMain);
        float a = 1.;
        if (uMain > .5 && cameraPosition.y > 0.) a = 1. - smoothstep(uFade.x, uFade.y, gl_FragCoord.y / uResY);
        gl_FragColor = vec4(c * a, a);
      }`,
  });
  const sky = new THREE.Mesh(new THREE.SphereGeometry(4000, 48, 24), skyMat);
  sky.frustumCulled = false; sky.renderOrder = -10; scene.add(sky);

  /* ------------------------------------------------------------ environment: the same sky, no disc, warm low band behind the viewer */
  const envScene = new THREE.Scene();
  const envMat = skyMat.clone(); envMat.uniforms.uSunDir.value = sunDir; envMat.uniforms.uMain.value = 0; envMat.uniforms.uDisc.value = 0; envMat.uniforms.uCloudT = skyU.uCloudT; envMat.uniforms.uFujiAz = skyU.uFujiAz;
  envScene.add(new THREE.Mesh(new THREE.SphereGeometry(50, 64, 32), envMat));
  const pm = new THREE.PMREMGenerator(renderer);
  const setSun = (elevDeg) => { const e = THREE.MathUtils.degToRad(elevDeg); sunDir.set(0, Math.sin(e), -Math.cos(e)); };
  setSun(-2.8);
  let envRT = pm.fromScene(envScene, 0, .1, 200);
  scene.environment = envRT.texture; scene.environmentIntensity = 1;

  /* ------------------------------------------------------------ letters */
  const font = new Font({ glyphs: GLYPHS, familyName: 'Instrument Serif', ascender: 990, descender: -310, underlinePosition: -100, underlineThickness: 50, resolution: 1000, boundingBox: { xMin: -200, yMin: -310, xMax: 1200, yMax: 990 } });
  const EM = 13.4, k = EM / 1000, SINK = .38, Z0 = -.8, DEPTH = 1.5, BEV = 0;
  const hazeU = { value: .0035 };
  const lacquer = new THREE.MeshPhysicalMaterial({ color: new THREE.Color().setHex(0x0b0708), roughness: .85, metalness: 0, clearcoat: 1, clearcoatRoughness: .025, envMapIntensity: 5, specularIntensity: .06 });
  const walls = new THREE.MeshPhysicalMaterial({ color: new THREE.Color().setHex(0x0b0708), roughness: .85, metalness: 0, clearcoat: 1, clearcoatRoughness: .06, envMapIntensity: 2.6, specularIntensity: .06 });
  for (const m of [lacquer, walls]) m.onBeforeCompile = sh => {
    sh.uniforms.uSunDir = skyU.uSunDir; sh.uniforms.uGlow = skyU.uGlow; sh.uniforms.uCloudT = skyU.uCloudT; sh.uniforms.uFujiAz = skyU.uFujiAz; sh.uniforms.uHaze = hazeU;
    sh.vertexShader = sh.vertexShader.replace('#include <common>', '#include <common>\nvarying vec3 vWP;').replace('#include <worldpos_vertex>', '#include <worldpos_vertex>\nvWP = (modelMatrix * vec4(transformed, 1.)).xyz;');
    sh.fragmentShader = sh.fragmentShader.replace('#include <common>', '#include <common>\nvarying vec3 vWP; uniform float uHaze;\n' + SKY)
      .replace('void main() {', 'void main() {\nif (vWP.y < -.02 && cameraPosition.y > 0.) discard;')
      // wet band: the lacquer is darker and glossier where the swell washes it
      .replace('#include <roughnessmap_fragment>', '#include <roughnessmap_fragment>\n float wet = 1. - smoothstep(.5, .6, vWP.y); roughnessFactor = mix(roughnessFactor, .08, wet); diffuseColor.rgb *= 1. - .6 * wet;')
      // aerial perspective, capped so the faces never turn brown
      // the polished faces mirror the sky behind the viewer: violet overhead, a rose band toward the waterline

      .replace('#include <fog_fragment>', `vec3 hv = vWP - cameraPosition; float hd = length(hv); hv /= hd;
        vec3 hc = skyCol(normalize(vec3(hv.x, abs(hv.y) * .5 + .01, hv.z)), 0., 0.);
        gl_FragColor.rgb = mix(gl_FragColor.rgb, min(hc, vec3(.12, .07, .1)), min(1. - exp(-hd * uHaze), .05));
`);
  };
  lacquer.customProgramCacheKey = () => 'wm-lacquer'; walls.customProgramCacheKey = () => 'wm-walls';
  const word = new THREE.Group(); scene.add(word);
  const maskScene = new THREE.Scene(), maskMat = new THREE.MeshBasicMaterial({ color: 0x000000, side: THREE.DoubleSide });
  const text = 'Sunset';
  let x = 0; const geos = [], shapesBy = [];
  for (let i = 0; i < text.length; i++) {
    const ch = text[i];
    // resample each contour and drop near-duplicate points: tiny segments make the bevel miters spike out of the outline
    const clean = pts => { const out = []; for (const q of pts) if (!out.length || q.distanceTo(out[out.length - 1]) > .03) out.push(q); if (out.length > 2 && out[0].distanceTo(out[out.length - 1]) < .03) out.pop(); return out; };
    const shapes = font.generateShapes(ch, EM).map(sh => { const n = new THREE.Shape(clean(sh.getPoints(14))); n.holes = sh.holes.map(h => new THREE.Path(clean(h.getPoints(14)))); return n; });
    const g = toCreasedNormals(new THREE.ExtrudeGeometry(shapes, { depth: DEPTH, curveSegments: 16, bevelEnabled: false }), THREE.MathUtils.degToRad(40));
    const nrm = g.attributes.normal;   // rounded chamfer and smooth walls, dead-flat faces
    for (const gr of g.groups) if (gr.materialIndex === 0) for (let v = gr.start; v < gr.start + gr.count; v++) nrm.setXYZ(v, 0, 0, Math.sign(nrm.getZ(v)) || 1);
    for (let v = 0; v < nrm.count; v++) {   // degenerate slivers leave zero/NaN normals, which shade as black specks
      const nx = nrm.getX(v), ny = nrm.getY(v), nz = nrm.getZ(v), l = Math.hypot(nx, ny, nz);
      if (!(l > .5)) nrm.setXYZ(v, 0, 0, 1);
    }
    g.translate(x, 0, 0);
    geos.push(g); shapesBy.push({ shapes, x });
    x += GLYPHS[ch].ha * k + (KERN[ch + (text[i + 1] || '')] || 0) * k;
  }
  const box = new THREE.Box3();
  for (const g of geos) { g.computeBoundingBox(); box.union(g.boundingBox); }
  const wordW = box.max.x - box.min.x, cx = (box.max.x + box.min.x) / 2;
  for (const g of geos) {
    g.translate(-cx, -SINK, Z0);
    word.add(new THREE.Mesh(g, [lacquer, walls]));
    maskScene.add(new THREE.Mesh(g, maskMat));
  }
  const wordTop = box.max.y - SINK, zFront = Z0 + DEPTH + BEV, zBack = Z0 - BEV;

  // the word's footprint on the sea surface: x-intervals where each glyph crosses the waterline (even-odd rule)
  const foot = [];
  for (const { shapes, x: ox } of shapesBy) {
    const xs = [];
    for (const sh of shapes) for (const pts of [sh.getPoints(24), ...sh.holes.map(h => h.getPoints(24))]) {
      for (let i = 0; i < pts.length; i++) {
        const a = pts[i], b = pts[(i + 1) % pts.length];
        if ((a.y > SINK) !== (b.y > SINK)) xs.push(a.x + (SINK - a.y) / (b.y - a.y) * (b.x - a.x));
      }
    }
    xs.sort((p, q) => p - q);
    for (let i = 0; i + 1 < xs.length; i += 2) foot.push(new THREE.Vector2(xs[i] + ox - cx, xs[i + 1] + ox - cx));
  }
  while (foot.length < 16) foot.push(new THREE.Vector2(1e4, 1e4));
  foot.length = 16;

  /* ------------------------------------------------------------ sea: planar mirror, ripple-broken, glitter where the sun gets through */
  const seaU = {
    color: { value: null }, tDiffuse: { value: null }, textureMatrix: { value: null }, uTime: { value: 0 }, uResY: { value: 800 }, uFadeY: { value: .2 },
    uSunDir: { value: sunDir }, uGlow: { value: 1 }, uCloudT: skyU.uCloudT, uSpan: { value: .2 }, uAspect: { value: 3 }, uRough: { value: 1 },
    uFoot: { value: foot }, uZ: { value: new THREE.Vector2(zBack, zFront) },
  };
  const seaShader = {
    name: 'SunsetSea', uniforms: seaU,
    vertexShader: 'uniform mat4 textureMatrix; varying vec4 vUv; varying vec3 vW; void main(){ vUv = textureMatrix * vec4(position, 1.); vec4 w = modelMatrix * vec4(position, 1.); vW = w.xyz; gl_Position = projectionMatrix * viewMatrix * w; }',
    fragmentShader: SKY + `
      uniform sampler2D tDiffuse; uniform float uTime, uResY, uFadeY, uSpan, uAspect, uRough; uniform vec2 uFoot[16]; uniform vec2 uZ;
      varying vec4 vUv; varying vec3 vW;
      vec2 gradN(vec2 q){ float a = wN(q), b = wN(q + vec2(.3, 0.)), c = wN(q + vec2(0., .3)); return vec2(b - a, c - a) / .3; }
      void main(){
        vec3 toC = cameraPosition - vW; float dist = length(toC); vec3 V = toC / dist;
        vec2 p = vW.xz;
        float fz = length(vec2(dFdx(vW.z), dFdy(vW.z)));
        // distance to the word's footprint on the water (for the contact line and the rings)
        float dmin = 1e3; vec2 dir = vec2(0.);
        for (int i = 0; i < 16; i++) {
          vec2 iv = uFoot[i]; if (iv.x > 1e3) break;
          vec2 dd = vec2(max(max(iv.x - p.x, p.x - iv.y), 0.), max(max(uZ.x - p.y, p.y - uZ.y), 0.));
          float l = length(dd); if (l < dmin) { dmin = l; dir = dd / max(l, 1e-4); }
        }
        // small random ripples (two octaves, each dropped once its cells fall under ~6 px) + faint rings at the letters
        vec2 q1 = p * vec2(.45, 1.1) + vec2(uTime * .04, uTime * .09), q2 = p * vec2(1.2, 2.9) - vec2(uTime * .07, uTime * .16);
        float v1 = 1. - smoothstep(.5, 1.2, fz * 1.1 * 6.), v2 = 1. - smoothstep(.5, 1.2, fz * 2.9 * 6.);
        vec2 g = (gradN(q1) * v1 + .6 * gradN(q2) * v2);
        g += dir * cos(dmin * 6. - uTime * 2.) * exp(-dmin / .8) * .8;
        g *= uRough * smoothstep(.0, 1.2, dmin + .15);                                 // calm right at the contact line
        // ripples grow toward the viewer: the mirror breaks up and smears downward the further it is from the word
        float fromWord = smoothstep(1., 28., vW.z - uZ.y);
        g *= .45 + 1.4 * fromWord;
        vec3 n = normalize(vec3(-g.x * .03, 1., -g.y * .03));
        float fres = .02 + .98 * pow(1. - max(dot(n, V), 0.), 5.);
        vec2 off = g * vec2(.0014, .006) * (.5 + fromWord);
        float smear = (.002 + .014 * fromWord) / uSpan * .12;
        vec3 refl = vec3(0.); float ws = 0.;
        for (int i = 0; i < 5; i++) {
          float fi = float(i), w = exp(-fi * .45);
          vec4 uv = vUv; uv.xy += (off + vec2(0., -fi * smear)) * uv.w;       // the smear runs away from the horizon
          refl += texture2DProj(tDiffuse, uv).rgb * w; ws += w;
        }
        refl /= ws;
        vec3 deep = vec3(.012, .009, .02);
        float far = smoothstep(250., 2500., dist);                                     // far water matches the mirrored sky: no seam at the horizon
        vec3 col = mix(deep, refl * mix(.6, .85, far), fres);
        col *= 1. - .6 * exp(-dmin / .1);                                              // the wet dark line at each letter
        float sy = gl_FragCoord.y / uResY;
        float a = smoothstep(0., uFadeY, sy); a = a * a * (3. - 2. * a);
        gl_FragColor = vec4(col * a, a);
      }`,
  };
  const sea = new Reflector(new THREE.PlaneGeometry(8000, 8000), { shader: seaShader, textureWidth: 512, textureHeight: 256, multisample: 0, clipBias: .002 });
  sea.rotation.x = -Math.PI / 2;
  Object.assign(sea.material.uniforms, { uFoot: { value: foot }, uSunDir: { value: sunDir }, uCloudT: skyU.uCloudT, uFujiAz: skyU.uFujiAz });
  sea.material.extensions = { derivatives: true };
  scene.add(sea);

  /* ------------------------------------------------------------ light shafts: the open sky around the sun, streamed outward through the
     gaps in screen space (from a 1/4-res view mask of the word), kept off the lacquer faces */
  const viewRT = new THREE.WebGLRenderTarget(4, 4, { depthBuffer: true, minFilter: THREE.LinearFilter, magFilter: THREE.LinearFilter });
  const shaftRT = new THREE.WebGLRenderTarget(4, 4, { type: THREE.HalfFloatType, depthBuffer: false, minFilter: THREE.LinearFilter, magFilter: THREE.LinearFilter });
  const shaftU = { tView: { value: viewRT.texture }, uSun: { value: new THREE.Vector2() }, uHor: { value: .3 }, uAsp: { value: 3 }, uGlow: skyU.uGlow };
  const shaftScene = new THREE.Scene(), quadCam = new THREE.OrthographicCamera(-1, 1, 1, -1, 0, 1);
  const tri = new THREE.BufferGeometry(); tri.setAttribute('position', new THREE.Float32BufferAttribute([-1, -1, 0, 3, -1, 0, -1, 3, 0], 3));
  const shaftMesh = new THREE.Mesh(tri, new THREE.ShaderMaterial({
    uniforms: shaftU, depthTest: false, depthWrite: false,
    vertexShader: 'varying vec2 vUv; void main(){ vUv = position.xy * .5 + .5; gl_Position = vec4(position.xy, 0., 1.); }',
    fragmentShader: `
      uniform sampler2D tView; uniform vec2 uSun; uniform float uHor, uAsp, uGlow; varying vec2 vUv;
      float ign(vec2 p){ return fract(52.9829189 * fract(dot(p, vec2(.06711056, .00583715)))); }
      float src(vec2 p){
        if (p.x < 0. || p.x > 1. || p.y > 1.) return 0.;
        float open = texture2D(tView, p).r;
        vec2 d = (p - uSun) * vec2(uAsp, 1.);
        float sky = smoothstep(uHor - .004, uHor + .012, p.y);
        float band = exp(-max(p.y - uHor, 0.) / .03) * exp(-abs(d.x) / .35);
        return open * sky * (.25 * exp(-length(d) / .09) + band);
      }
      void main(){
        const int N = 48;
        vec2 dl = (vUv - uSun) / float(N) * .98;
        vec2 p = vUv - dl * ign(gl_FragCoord.xy);
        float acc = 0., w = 1.;
        for (int i = 0; i < N; i++) { acc += src(p) * w; w *= .985; p -= dl; }
        acc /= float(N);
        float onWord = 1. - texture2D(tView, vUv).r;
        gl_FragColor = vec4(vec3(1., .66, .34) * acc * uGlow * (1. - .96 * onWord), 1.);
      }`,
  }));
  shaftMesh.frustumCulled = false; shaftScene.add(shaftMesh);
  const shaftAdd = new THREE.Mesh(tri, new THREE.ShaderMaterial({
    uniforms: { tShaft: { value: shaftRT.texture }, uK: { value: 0 }, uResY: skyU.uResY, uFadeY: { value: .2 } },
    transparent: true, depthTest: false, depthWrite: false,
    blending: THREE.CustomBlending, blendEquation: THREE.AddEquation, blendSrc: THREE.OneFactor, blendDst: THREE.OneFactor, blendSrcAlpha: THREE.ZeroFactor, blendDstAlpha: THREE.OneFactor,
    vertexShader: 'varying vec2 vUv; void main(){ vUv = position.xy * .5 + .5; gl_Position = vec4(position.xy, 0., 1.); }',
    fragmentShader: `uniform sampler2D tShaft; uniform float uK, uResY, uFadeY; varying vec2 vUv;
      void main(){ if (cameraPosition.y < 0.) discard;
        float a = smoothstep(0., uFadeY, gl_FragCoord.y / uResY);
        gl_FragColor = vec4(texture2D(tShaft, vUv).rgb * uK * a, 0.); }`,
  }));
  shaftAdd.frustumCulled = false; shaftAdd.renderOrder = 1000; scene.add(shaftAdd);

  const post = {
    exposure: 1.0, tone: 'aces', hue: .5, sat: 1.04, contrast: 1.04, vignette: .0, grain: .012, ss: 1,
    bloom: { strength: .32, radius: .9, threshold: 2.6, knee: 1 }, rays: null,
  };

  /* ------------------------------------------------------------ camera: level (verticals stay vertical), lens-shifted to the layout */
  const D = 62, CAM_Y = 2.4;
  const par = { x: 0, y: 0 };
  let sunE = -2.6, lastEnvE = -2.8;
  const cc = new THREE.Color(), _v = new THREE.Vector3();
  const obj = {
    scene, camera, post, autoAspect: false,
    update(dt, t, s) {
      const a = s.w / Math.max(1, s.h), mobile = s.w < 600;
      const tx = REDUCED ? 0 : clamp(s.pointer.x, -1, 1), ty = REDUCED ? 0 : clamp(s.pointer.y, -1, 1);
      par.x = damp(par.x, tx, 2.2, dt); par.y = damp(par.y, ty, 2.2, dt);
      camera.position.set(par.x * 2.2, CAM_Y + (-par.y * .5 + .5) * .3, D);
      camera.rotation.set(0, 0, 0); camera.updateMatrixWorld();
      // layout (fractions of the host height): the bottom fade band, the letters' waterline just above it, >= 6 % headroom
      const fadeF = Math.min(76, s.h * .2) / s.h;
      const tWL = -camera.position.y / (D - zFront), tTop = (wordTop - camera.position.y) / (D - zFront);
      const wlMin = fadeF + (mobile ? .07 : .045);
      let span = Math.max(wordW / (D - zFront) / (.88 * a), (tTop - tWL) / (.79 - wlMin));
      const wordF = (tTop - tWL) / span;
      const wl = Math.max(wlMin, (1 - wordF) * (mobile ? .52 : .6) - .02);    // extra room goes mostly to the sky
      const tb = tWL - wl * span, tt = tb + span, hw = a * span / 2, n = camera.near, cx0 = -camera.position.x / (D - zFront);
      camera.projectionMatrix.makePerspective((cx0 - hw) * n, (cx0 + hw) * n, tt * n, tb * n, n, camera.far);
      camera.projectionMatrixInverse.copy(camera.projectionMatrix).invert();
      // the sun settles as the footer arrives, then breathes very slowly
      const arrive = smooth(.05, .36, s.progress);
      const target = lerp(-2.4, -3.1, arrive) + (REDUCED ? 0 : Math.sin(t * .11) * .05);
      sunE = damp(sunE, target, 1.5, dt);
      setSun(sunE);
      if (Math.abs(sunE - lastEnvE) > .25) { envRT.dispose(); envRT = pm.fromScene(envScene, 0, .1, 200); scene.environment = envRT.texture; lastEnvE = sunE; }
      const resY = s.h * VP.dpr * (obj.post?.o?.ss || 1);
      skyU.uResY.value = resY; skyU.uFade.value.set(mobile ? .66 : .78, 1.); skyU.uFujiAz.value = mobile ? .6 : .34;
      skyU.uCloudT.value = REDUCED ? 0 : t * .004;
      const su = sea.material.uniforms;
      su.uResY.value = resY; su.uFadeY.value = fadeF; su.uTime.value = REDUCED ? 3 : t; su.uSpan.value = span; su.uAspect.value = a; su.uRough.value = mobile ? .7 : 1;
      shaftAdd.material.uniforms.uFadeY.value = fadeF;
      const rt = sea.getRenderTarget(), rw = Math.round(s.w * VP.dpr * .75), rh = Math.round(s.h * VP.dpr * .75);
      if (rt.width !== rw || rt.height !== rh) rt.setSize(rw, rh);

      shaftAdd.visible = false;   // shafts off: from under the horizon they read as searchlights
    },
  };
  return obj;
}
