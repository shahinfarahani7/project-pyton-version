# Sunset — 3-D landing page brief (read fully before writing a scene)

**Sunset** sells rooftop solar + a home battery to homes in Japan: ¥0 upfront, one fixed monthly plan.
The page is `sunset-3d/index.html`. Every section has a real-time three.js (r186) scene. The target is **AAA-game quality,
8/10 or better from a strict art judge**, on a retina screen (DPR 2). Clean, calm, Japanese; powerful, not busy.

## Art direction
- **Mood:** late golden hour into dusk. Low warm sun, long soft shadows, god rays from the background, sakura in bloom,
  petals falling. Colours around a sunset: peach, apricot, vermilion, sakura pink, lavender haze, deep plum-indigo night.
- **Page ground:** warm paper `#F3EADB` on light sections, night `#15111C` on dark sections, with long dusk gradients
  between them (painted by the canvas). A thin **grid of hairlines** runs through every section: it is the solar
  array's cell grid carried across the page. Echo it in 3-D where natural (panel cells, tatami/gravel lines, chart trays).
- **Japanese, specific and correct:** minka / modern machiya architecture (deep eaves, exposed rafters, engawa veranda,
  shoji with warm light behind, kawara or standing-seam roofs, yakisugi or weathered sugi siding, plaster walls,
  granite plinths, stone lanterns (tōrō), raked gravel, moss, pines, somei-yoshino cherry). Nothing that reads Western.
- **No human characters in any 3-D scene.** Buildings, phones, panels, objects, landscapes, skies only.
- **Materials must look real at DPR 2:** use the scanned PBR sets (below) with correct texel density (a wood board ≈
  0.5–1 m per texture repeat, never a stretched or 20× tiled grain), anisotropy, normal maps, roughness variation,
  AO. Wood has to read as wood in a close crop.
- **Lighting like a AAA game:** one strong warm key (the sun) with soft PCF shadows, image-based fill from the real
  sunset HDRI, emissive interiors, contact shadows / AO where objects meet, atmospheric perspective (distance haze
  tinted by the sky), bloom only on genuinely bright things.
- **Taste rules from past reviews (hard rules):**
  - No decorative shines: no sweeping light bands, glints, lens streaks, sheen wipes. Improve lighting/materials instead.
  - UI shown on a screen (the phone) stays **flat and face-on** to the viewer: no perspective tilt on the design itself.
    Depth comes from things floating around it.
  - Emissive reds turn pink through ACES: drive G/B to ~0 for red glows.
  - Avoid facet/Voronoi normals ("hammered tin"), round blob tree crowns ("mushroom caps"), tiled-looking repeats.
  - Text is never inside the 3-D unless it's a physical object (the footer wordmark); labels are DOM anchors.

## Files and ownership
```
sunset-3d/
  index.html  css/site.css  js/core.js  js/post.js  js/main.js  js/petals.js      (owned by the lead — don't edit; ask)
  js/scenes/<name>.js      one module per [data-scene] host (yours)
  js/models/<name>.js      shared builders (house, sakura, garden: agent A)
  assets/tex/  assets/hdr/  assets/models/  assets/data/  assets/img/  assets/icons.json
  lab.html                 isolate one scene:  lab.html?scene=battery&w=640&h=512[&dark=1][&anchors=a,b]
  tools/shot.mjs           headless capture (see Verification)
```
If you need a change in a lead-owned file, write it in your final report (exact diff) instead of editing.
Never use `Math.random()` in a build; use `rng(seed)` from core.js so every load is identical.

## The scene contract
```js
// js/scenes/<name>.js
import { THREE, pbrMaterial, pbrSet, loadTexture, canvasTexture, makeCanvas, rng, clamp, lerp, damp, smooth, E, VP, STATE, costs } from '../core.js';
export async function create(ctx) {
  // ctx: { host (the DOM element), name, renderer, env: { texture /*PMREM*/, equirect /*HDR*/ }, THREE, VP, STATE, PTR, Post }
  const scene = new THREE.Scene(); const camera = new THREE.PerspectiveCamera(30, 1, .1, 500);
  scene.environment = ctx.env.texture; // + scene.environmentIntensity, scene.environmentRotation
  return {
    scene, camera,
    update(dt, t, s) {},       // s: { rect, w, h, dt, t, progress, pin, pointer:{x,y}, hover, scrollV, age }
                               //   progress: 0 when the host's top enters at the viewport bottom → 1 when its bottom leaves the top
                               //   pin: progress through the host's <section> while it is pinned (for sticky sections)
                               //   pointer: -1..1 relative to the host centre (beyond ±1 outside it); age: seconds since build
    post: { ... } | null,      // optional HDR post chain (below). Omit for direct rendering (ACES, MSAA).
    tone: 'aces'|'agx'|'neutral', exposure: 1,   // direct path only
    anchors: { name: Object3D | Vector3 },       // DOM .gl-anchor[data-anchor=name] children of the host follow these
    anchorOn(name) { return true },              // optional: hide a label (e.g. while its object is hidden)
    autoAspect: true,          // the loop sets camera.aspect = host w/h each frame
  };
}
```
- The host rect is the viewport for your camera. The canvas behind it is the **page ground**; a scene with no
  background is transparent over the paper/night colour. Draw your own backdrop only where the design calls for it.
- `scene.background` is not allowed (it clears the whole canvas). Use a backdrop mesh/sphere with `depthWrite:false`.
- Direct path: rendered with MSAA, `renderer.toneMapping` from `tone`, exposure from `exposure`.
- Post path (`post: {...}`), options with defaults:
  `{ exposure:1, tone:'aces'|'agx', hue:.35 (0..1 blend toward a hue-preserving tonemap: stops sunsets clipping to flat yellow),
     sat:1.04, contrast:1.04, vignette:.22, grain:.018, lift:[0,0,0], shadowTint:[1,1,1], highTint:[1,1,1], ss:1 (supersample),
     bloom:{ strength:.55, radius:1, threshold:1.2, knee:.6 } | null,
     rays:{ sun: Vector3 (world position of the light source), strength:1, tint:[1,.78,.56], density:.92, decay:.958,
            weight:.032, threshold:1.2, falloff:3.2 } | null }`
  The ray pass marches from each pixel toward the projected sun and accumulates **sky pixels** (depth == 1) brighter than
  `threshold`, weighted by distance to the sun (`falloff`). So: the sky dome must use `depthWrite:false`, and anything
  that should cast shafts (branches, roof, ridge) must write depth. Keep the sun's own disc/glow in the sky shader.
  HalfFloat targets can't take MSAA here, so the post path ends in FXAA; use `ss:1.5` on small hosts if edges crawl.
  You can mutate `obj.post.o` (the live options) in `update` (e.g. `this.post.o.exposure = …`) once built.
- Budget: the hero may take ~6 ms at DPR 2 on an M-series GPU; every other scene ≤ 3 ms. One shadow-casting light per
  scene, shadow map ≤ 4096 (hero) / 2048 (others), fitted tightly to the subject. Freeze static shadows
  (`light.shadow.autoUpdate=false; light.shadow.needsUpdate=true` when something moves).
- Reduced motion (`REDUCED` from core.js): hold a composed still, don't hide things.
- Mobile (host narrower than ~600 px): reframe the camera so the subject still fits; cut counts, not the look.

## Assets (all local; CC0 unless noted)
Scanned PBR sets in `assets/tex/<name>_{c,n,r}.webp` — `_c` albedo (sRGB), `_n` OpenGL normal, `_r` packed **R=AO, G=roughness**.
`pbrMaterial(name, { repeat:[u,v], rotation, tint, roughness, normal, ao, metalness, envMapIntensity, physical })` builds a material;
`pbrSet(name, {repeat})` returns the textures. `repeat` is per UV unit — set UVs in metres (e.g. BoxGeometry UVs are 0..1
per face, so scale repeat by the face size) so grain has real-world scale.
| set | look | size | use for |
|---|---|---|---|
| `sugi` | silver-grey weathered cedar, strong vertical grain | 4K | exterior siding, fences, gate |
| `mahogany` | red-brown fine grain | 4K | lacquer, dark interior, (tinted dark) beams |
| `darkwood` | dark aged raw timber | 2K | posts, beams, rafters, frames |
| `hinoki` | pale oak/hinoki cathedral grain | 2K | engawa, battery cabinet front, chart tray, soroban frame |
| `deck` | warm varnished deck boards with gaps | 2K | engawa floor (desaturate/lighten for hinoki decking) |
| `plaster` | light grey plaster | 2K | shikkui walls (tint warm white) |
Also `_c/_n` only (no `_r`): `sakura_bark`, `japanese_stone_wall`, `ganges_river_pebbles` (gravel), `rock_moss_set_02`,
`forest_ground_04`, `rock_face_01`, `reed_roof_04` (thatch). Poly Haven albedos are often very dark (1–4 % mean);
measure and multiply `tint` to a plausible albedo rather than raising exposure.
- `assets/hdr/belfast_sunset_puresky_2k.hdr` — real sunset sky (warm horizon, lavender clouds); `ctx.env.texture` has it prefiltered.
  **Outdoor scenes only.** On the paper it fills shadow sides lavender (judged "CG violet").
- `ctx.env.studio` — a warm paper-studio PMREM (page-coloured room, big warm softbox upper-left, dim warm fill right,
  top strip, peach rim behind). **All product scenes on the paper use this** (chart, panel, battery, phone), env intensity
  ≈ 0.35–0.5, plus ONE shared key: DirectionalLight from the upper left (direction ≈ (-1, 1.3, .8)), colour #FFE0BC,
  shadows falling toward the lower right, and a warm bounce (HemisphereLight sky #FFF3E4 / ground #E7D6BC ≈ .4).
  Shadow sides must read warm grey, never violet.
- `assets/models/iphone18.glb` — iPhone 18 Pro body (reconstructed; see ../ar-iphone-18-pro-005). For the app phone.
- `assets/data/jpmap.json` — Japan outline `{ W, H, inner, outer: "x,y x,y …|…" polygons in a W×H px frame, cities: {name:[x,y]} }`.
- `assets/img/blossom-atlas.webp` + `.json` — 3×3 atlas of **photographic** sakura blossom clusters (keyed, straight alpha,
  lit flat) for canopy cards; the json gives each cell's uv rect and its stem point. Use it instead of drawn flowers.
- `assets/img/*.webp` — transparent PNG ornaments (sakura sprig, crane, fan, lantern, 陽 hanko seal, postal stamps). DOM only.
- Fonts on the page: Instrument Serif (display), Instrument Sans (body), JetBrains Mono (labels), Shippori Mincho (kanji).
  Palette: paper #F3EADB, ink #1E1916, night #15111C, sun #EC6A3C, vermilion #D5452B, sakura #F3B9C4, gold #E7B266, lavender #BBA6D8.

## Shared models (agent A builds these first; others import them)
```js
// js/models/house.js
export async function buildHouse({ env, detail = 'high', panels = true, glow = 0 /*0..1 interior light*/, seed = 1 } = {})
  // -> { group, panels: Object3D[] (each with userData.home = { position, quaternion } in group space, for install animations),
  //      setGlow(v), anchors: { roof, battery, meter }, bounds: Box3, sunCatchers: Object3D[] /*meshes that should write depth for rays*/ }
// js/models/sakura.js
export async function buildSakura({ seed = 1, height = 7, bloom = 1 } = {}) // -> { group, update(t, wind) }
// js/models/garden.js
export async function buildGarden({ seed = 1, size = [20, 14] } = {})       // -> { group }  (gravel, stones, moss, tōrō, path)
```
Units are metres. House ≈ 11 m wide, 8 m deep, ridge ≈ 6 m. Front of the house faces +z; ground at y = 0.

## Verification (you must do this yourself, repeatedly)
- A static server for the whole `HTML Pages` folder runs on the port written in **`sunset-3d/tools/PORT`** (currently 52170;
  re-read it if a request fails — it changes when the server restarts), so the page is `http://localhost:<PORT>/sunset-3d/lab.html?scene=<name>`. If it is down, start your own in the background:
  `PORT=<free port> node "/Users/mengto/Downloads/Projects/HTML Pages/.claude/serve-port.mjs" "/Users/mengto/Downloads/Projects/HTML Pages" &`
- Capture headless (GPU on; never opens a visible window — **do not open Chrome windows or use the Browser pane**):
  `node tools/shot.mjs --url "http://localhost:<PORT>/sunset-3d/lab.html?scene=hero" --out <your scratch dir>/hero.png --w 1440 --h 900 --dpr 2 --freeze 3.5`
  `--freeze t` pins the clock for deterministic frames; `--seq "0,.5,1" --pin "#how"` samples a pinned section on index.html;
  `--jump "#savings"` scrolls index.html to a section. It prints console errors — the console must be clean.
  Look at every capture (Read the PNG). Crop and zoom on materials; check at DPR 2 and at 390×844 (mobile).
- Iterate until it looks like a still from a AAA game, not a WebGL demo. Before finishing, judge your own frames
  honestly out of 10 against that bar and list what still holds it back.
- Keep your scratch captures in your own folder (e.g. `/private/tmp/claude-501/<…>/scratchpad/<agent>/`), never the repo.
