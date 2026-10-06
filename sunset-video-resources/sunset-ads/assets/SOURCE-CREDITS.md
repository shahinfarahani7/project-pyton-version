# Sunseto — credits and provenance

## Fonts (SIL Open Font License 1.1, licences in `fonts/licenses/`)
- Instrument Sans, Instrument Serif: Instrument (Rodrigo Fuenzalida / Jordan Egstad), via github.com/google/fonts
- JetBrains Mono: JetBrains, via github.com/google/fonts
- Shippori Mincho: FONTDASU, via github.com/google/fonts (subset to the kanji the page uses)

Built by `tools/make_fonts.py` from the sources in `fonts/src/`.

## Brand
- The Sunseto mark (a sun setting into three waves) and wordmark were drawn for this project:
  `tools/make_mark.py` (geometry, `sunseto-mark.svg`, `mark.json`), `tools/mark.html` (3D render),
  `tools/make_logo.py` (lockups). The 陽 seal was generated with Aura and keyed by `tools/make_layers.py`.

## Images
- Drawings, ornaments, photographic textures, the hand photo and the bokeh backdrop were generated with Aura;
  sources are in `originals/`.
- iPhone 18 Pro geometry comes from the AR-005 project (`../ar-iphone-18-pro-005`), itself a reconstruction of
  the LS Graphics AR mockup; see that project's README.
- Japan map: GSI Global Map Japan via the jpn-atlas package.

## Removed in the originality pass (2026-09-24)
Daylight's four web-font files, logo SVGs and thermostat icon, and all of its copy, were removed. Nothing in
`sunset.html` now comes from godaylight.com. Page structure and some photo compositions still follow the
original and are flagged for a later pass.
