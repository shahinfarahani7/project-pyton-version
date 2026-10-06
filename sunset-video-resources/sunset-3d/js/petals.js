/* Sakura petals over the whole page.
   GL layer (behind the DOM, over the 3-D scenes): instanced quads animated entirely in the vertex shader.
   Each petal tumbles about its own long axis (goes edge-on), rolls in-plane, and slips sideways in phase
   with the tumble. Page scroll lifts them with depth parallax. Front and back faces differ.
   Near layer (a 2-D canvas above the DOM): three to five large soft petals that cross in front of the type. */
import { THREE, VP, REDUCED, rng, makeCanvas, canvasTexture } from './core.js';

function petalCanvas(size = 256) {
  const c = makeCanvas(size, size), g = c.getContext('2d');
  const s = size / 2;
  g.translate(s, s);
  // a single somei-yoshino petal: broad rounded blade, notched tip (top), narrowing to the claw (bottom)
  const path = new Path2D();
  path.moveTo(0, s * .92);
  path.bezierCurveTo(s * .28, s * .7, s * .66, s * .2, s * .6, -s * .38);
  path.bezierCurveTo(s * .56, -s * .72, s * .3, -s * .9, s * .1, -s * .8);
  path.quadraticCurveTo(0, -s * .66, -s * .1, -s * .8);
  path.bezierCurveTo(-s * .3, -s * .9, -s * .56, -s * .72, -s * .6, -s * .38);
  path.bezierCurveTo(-s * .66, s * .2, -s * .28, s * .7, 0, s * .92);
  const grad = g.createLinearGradient(0, s * .9, 0, -s * .9);
  grad.addColorStop(0, '#E98FA3'); grad.addColorStop(.25, '#F6BBC8'); grad.addColorStop(.7, '#FCE3E8'); grad.addColorStop(1, '#FFF4F4');
  g.fillStyle = grad; g.fill(path);
  g.save(); g.clip(path);
  g.globalAlpha = .16; g.strokeStyle = '#D9738B'; g.lineWidth = size / 220;
  for (let i = -3; i <= 3; i++) { g.beginPath(); g.moveTo(0, s * .88); g.quadraticCurveTo(i * s * .1, 0, i * s * .15, -s * .82); g.stroke(); }
  g.restore();
  return c;
}

const VS = /* glsl */`
attribute vec4 aSeed;      // x0, y0 (0..1), depth (0 near..1 far), phase
attribute vec4 aRate;      // fall, spin rate, roll rate, slip
attribute vec3 aLook;      // scale, tint shift, hide threshold
uniform float uTime, uScroll, uW, uH, uDensity, uWind;
varying vec2 vUv; varying float vShade; varying float vFar; varying float vTint;
void main(){
  vUv = uv;
  float depth = aSeed.z;
  float zc = mix(260., -900., depth);                 // camera sits at z = D, z=0 is the page plane
  float k = (1. - zc / (uH * 1.9));                   // widen far layers so they still fill the frame
  float spanY = uH * 1.25 * k, spanX = uW * 1.2 * k;
  float par = mix(1.15, .35, depth);
  float t = uTime;
  float spin = aSeed.w * 6.2832 + t * aRate.y;
  float roll = aSeed.w * 12.566 + t * aRate.z;
  float y = mod(aSeed.y * spanY + uScroll * par - t * aRate.x, spanY) - spanY * .5;
  float x = mod(aSeed.x * spanX + t * uWind * mix(1., .5, depth) - cos(spin) * aRate.w / aRate.y + spanX * .5, spanX) - spanX * .5;
  float show = step(aLook.z, uDensity);
  float sc = aLook.x * show;
  // petal quad: tumble about its long axis (y), then roll in-plane (z), then a little pitch
  vec3 p = position * sc;
  float cs = cos(spin), sn = sin(spin);
  p = vec3(p.x * cs, p.y, p.x * sn);
  float cr = cos(roll), sr = sin(roll);
  p = vec3(p.x * cr - p.y * sr, p.x * sr + p.y * cr, p.z);
  float pt = .55 + .3 * sin(roll * .7);
  p = vec3(p.x, p.y * cos(pt) - p.z * sin(pt), p.y * sin(pt) + p.z * cos(pt));
  vShade = abs(cs) * .55 + .45;                       // edge-on reads darker
  vFar = depth; vTint = aLook.y;
  gl_Position = projectionMatrix * viewMatrix * vec4(p + vec3(x, y, zc), 1.);
}`;
const FS = /* glsl */`
uniform sampler2D tPetal; uniform float uDark, uAlpha; uniform vec4 uKeep[8]; uniform float uDpr, uH;
varying vec2 vUv; varying float vShade; varying float vFar; varying float vTint;
void main(){
  vec4 c = texture2D(tPetal, vUv);
  if (c.a < .5) discard;
  // keep petals out of text blocks (css px rects, y down): a petal crossing type reads as a smudge on it
  vec2 fp = vec2(gl_FragCoord.x, uH * uDpr - gl_FragCoord.y) / uDpr;
  for (int k = 0; k < 8; k++) { vec4 r = uKeep[k]; if (r.z > r.x && fp.x > r.x - 12. && fp.x < r.z + 12. && fp.y > r.y - 12. && fp.y < r.w + 12.) discard; }
  vec3 col = c.rgb;
  col = mix(col, col * vec3(1.02, .93, .96), vTint);
  if (!gl_FrontFacing) col = mix(col, vec3(.97, .9, .9), .45) * .9;   // the back is paler and duller
  col *= vShade;
  col = mix(col, col * vec3(.62, .52, .66) + vec3(.06, .02, .05), uDark);   // dusk on dark sections
  float fade = mix(1., .55, vFar);
  gl_FragColor = vec4(col * fade + vec3(.95, .9, .88) * (1. - fade) * (1. - uDark) * .35, uAlpha);
  #include <colorspace_fragment>
}`;

export class Petals {
  constructor(count = 150) {
    const r = rng(41);
    const g = new THREE.InstancedBufferGeometry();
    const base = new THREE.PlaneGeometry(1, 1);
    g.index = base.index; g.attributes.position = base.attributes.position; g.attributes.uv = base.attributes.uv;
    const seed = new Float32Array(count * 4), rate = new Float32Array(count * 4), look = new Float32Array(count * 3);
    for (let i = 0; i < count; i++) {
      const depth = Math.pow(r(), .7);
      seed.set([r(), r(), depth, r()], i * 4);
      const fall = (38 + r() * 46) * (1.15 - depth * .5);
      rate.set([fall, (1.1 + r() * 2.1) * (r() < .5 ? -1 : 1), (r() - .5) * 1.1, 26 + r() * 40], i * 4);
      look.set([(15 + r() * 9) * (1 - depth * .25), r(), r()], i * 3);
    }
    g.setAttribute('aSeed', new THREE.InstancedBufferAttribute(seed, 4));
    g.setAttribute('aRate', new THREE.InstancedBufferAttribute(rate, 4));
    g.setAttribute('aLook', new THREE.InstancedBufferAttribute(look, 3));
    g.instanceCount = count;
    this.u = { tPetal: { value: canvasTexture(petalCanvas()) }, uTime: { value: 0 }, uScroll: { value: 0 }, uW: { value: VP.w }, uH: { value: VP.h }, uDensity: { value: .5 }, uWind: { value: 16 }, uDark: { value: 0 }, uAlpha: { value: 1 }, uKeep: { value: Array.from({ length: 8 }, () => new THREE.Vector4()) }, uDpr: { value: 1 } };
    const m = new THREE.ShaderMaterial({ vertexShader: VS, fragmentShader: FS, uniforms: this.u, side: THREE.DoubleSide });
    this.mesh = new THREE.Mesh(g, m); this.mesh.frustumCulled = false;
    this.scene = new THREE.Scene(); this.scene.add(this.mesh);
    this.camera = new THREE.PerspectiveCamera(30, 1, 10, 6000);
    this.density = .5; this.dark = 0;
  }
  resize(w, h) {
    this.u.uW.value = w; this.u.uH.value = h;
    this.camera.aspect = w / h; this.camera.position.set(0, 0, (h / 2) / Math.tan(THREE.MathUtils.degToRad(15)));
    this.camera.lookAt(0, 0, 0); this.camera.updateProjectionMatrix();
  }
  keepOut(rects) { for (let k = 0; k < 8; k++) { const r = rects[k]; r ? this.u.uKeep.value[k].set(r.left, r.top, r.right, r.bottom) : this.u.uKeep.value[k].set(0, 0, 0, 0); } this.u.uDpr.value = VP.dpr; }
  update(dt, t, scroll, density, dark) {
    this.density += (density - this.density) * Math.min(1, dt * 1.5);
    this.dark += (dark - this.dark) * Math.min(1, dt * 3);
    this.u.uTime.value = REDUCED ? 30 : t; this.u.uScroll.value = scroll;
    this.u.uDensity.value = this.density; this.u.uDark.value = this.dark;
  }
  render(r) {
    if (this.density < .01) return;
    r.setRenderTarget(null); r.setScissorTest(false);
    r.setViewport(0, 0, VP.w, VP.h); r.clear(false, true, false);
    r.render(this.scene, this.camera);
  }
}

/* ------------------------------------------------------------------ near layer (2-D, over the DOM) */
export class NearPetals {
  constructor(cv, n = 4) {
    this.cv = cv; this.g = cv.getContext('2d'); this.n = n; this.list = []; this.r = rng(77);
    const src = petalCanvas(192);
    const bake = (back) => { const c = makeCanvas(224, 224), g = c.getContext('2d'); g.filter = 'blur(3.5px)'; if (back) { g.globalAlpha = .9; } g.drawImage(src, 16, 16); if (back) { g.globalCompositeOperation = 'source-atop'; g.fillStyle = 'rgba(250,236,236,.5)'; g.fillRect(0, 0, 224, 224); } return c; };
    this.face = bake(false); this.back = bake(true);
    this.resize();
    for (let i = 0; i < n; i++) this.list.push(this.spawn(true));
    this.active = true;
  }
  resize() { const d = Math.min(VP.dpr, 1.5); this.d = d; this.cv.width = Math.round(VP.w * d); this.cv.height = Math.round(VP.h * d); }
  spawn(anyY) {
    const r = this.r;
    return { x: VP.w * (.5 + r() * .5), y: anyY ? r() * VP.h : -120 - r() * 400, s: 54 + r() * 44, fall: 60 + r() * 50, spin: r() * 6.28, sr: (1.2 + r() * 1.4) * (r() < .5 ? -1 : 1), roll: r() * 6.28, rr: (r() - .5) * .8, slip: 70 + r() * 60, a: .55 + r() * .3 };
  }
  update(dt, scrollV, on) {
    const g = this.g, d = this.d;
    g.setTransform(1, 0, 0, 1, 0, 0); g.clearRect(0, 0, this.cv.width, this.cv.height);
    if (!on || REDUCED) { this.cv.style.visibility = 'hidden'; return; }
    this.cv.style.visibility = 'visible';
    for (const l of this.list) {
      l.spin += l.sr * dt; l.roll += l.rr * dt;
      l.x += Math.sin(l.spin) * l.slip * dt + 14 * dt;
      l.y += l.fall * dt - scrollV * .35 * dt;
      if (l.y > VP.h + 140 || l.y < -600) Object.assign(l, this.spawn(false));
      if (l.x > VP.w + 120) l.x = VP.w * .5 - 60; if (l.x < VP.w * .4) l.x = VP.w + 100;
      const cs = Math.cos(l.spin);
      g.setTransform(d, 0, 0, d, l.x * d, l.y * d);
      g.rotate(l.roll); g.scale(Math.max(.04, Math.abs(cs)), 1);
      g.globalAlpha = l.a * Math.min(1, Math.max(0, (l.x / VP.w - .42) / .14));   // never over the copy column
      g.drawImage(cs < 0 ? this.back : this.face, -l.s / 2, -l.s / 2, l.s, l.s);
    }
  }
}
