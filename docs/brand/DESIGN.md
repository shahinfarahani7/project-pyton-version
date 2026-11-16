# FibonAI design system

Shared brand and UI rules for every FibonAI surface: marketing site, customer portal, operations portal, worker app and documents. The marketing site (`src/apps/marketing-site`) is the reference implementation; token names below match its CSS.

## 1. Name

- Write **FibonAI** — capital F, capital A, capital I, one word. Never "Fibonai", "Fibon AI" or "FIBONAI" in running text.
- In the wordmark, the **I** is gold and the **A** carries a gold crossbar triangle. Everywhere else the name is plain text.

## 2. Logo

| File | Use |
| --- | --- |
| `fibonai-logo-dark.png` | Stacked lockup (mark + wordmark), slate on transparent — light backgrounds |
| `fibonai-logo-light.png` | Stacked lockup, off-white on transparent — dark backgrounds |
| `fibonai-mark-dark.svg` / `.png` | Mark only, slate + gold — light backgrounds |
| `fibonai-mark-light.svg` / `.png` | Mark only, off-white + gold — dark backgrounds |
| `src/apps/marketing-site/public/favicon.svg` | App icon / favicon: light mark on a `#0B0C0F` rounded tile |

PNG files are cut from the original artwork at 1024 px source resolution (about 670 × 512 px lockup). For anything larger than that, use the SVG mark. A vector wordmark does not exist yet; request the source file before printing the lockup large.

Rules:

- **Clear space:** at least the stroke-to-gold gap of the mark on every side, roughly 25% of mark height.
- **Minimum size:** mark 16 px (favicon), 24 px in UI chrome; lockup 96 px wide.
- **Horizontal lockup** (header, footer): mark on the left, wordmark in Geist 600 at about 60% of mark height, gap 10–12 px.
- The gold areas stay gold on every background. Only the line colour switches: slate `#262F38` on light, off-white `#ECE8DF` on dark.
- Do not recolour the mark in blue or gradients, add shadows to it, outline it, rotate it at rest or put it on busy imagery. A small hover tilt (−4°) is the only allowed motion.

## 3. Colour palette

Visual sheet: `fibonai-palette.svg`.

### Brand

| Token | Hex | Use |
| --- | --- | --- |
| `--brand-gold` | `#CDAE6F` | Gold on dark backgrounds: highlights, mark fill, key emphasis |
| `--brand-gold-deep` | `#C0A064` | Exact logo gold; print and light-background mark fill |
| `--brand-gold-soft` | `#F1E6CF` | Start of gold text gradients, subtle tints |
| `--brand-slate` | `#262F38` | Exact logo slate; mark lines and text on light backgrounds |
| `--brand-line` | `#ECE8DF` | Mark lines and wordmark on dark backgrounds |

Gold highlight gradient (headlines): `linear-gradient(100deg, #F1E6CF, #CDAE6F 55%, #C0A064)`.

### Dark theme (default)

| Token | Hex | Use |
| --- | --- | --- |
| Canvas | `#0B0C0F` | Page background |
| Panel | `#101216` | Cards |
| Panel 2 | `#15171B` | Raised card, inputs |
| Row | `#1A1C20` | List rows, table stripes |
| Line | `rgba(255,255,255,.09)` | Borders |
| Line hover | `rgba(255,255,255,.20)` | Hovered/focused borders |
| Text | `#FFFFFF` | Headlines, primary text |
| Muted | `#B3B5BD` | Body copy |
| Dim | `#7A7C86` | Captions, metadata (not for body text) |
| Steel gradient | `#A6C0CB → #7F9EAD → #4D6472` | Metallic headline/illustration accents |
| Check | `#19C7B4` | Success, verified, edge-ok |
| Hold | `#E2456B` | Held, rejected, policy block |
| Glow blue | `rgba(44,132,255,.55)` | Light effects behind glass only, never text |

### Light theme (portals, documents)

| Role | Hex | Notes |
| --- | --- | --- |
| Paper | `#F7F5F0` | Page background (warm, pairs with gold) |
| Surface | `#FFFFFF` | Cards |
| Ink | `#262F38` | Primary text (brand slate) |
| Ink 2 | `#5B6470` | Secondary text |
| Gold ink | `#806533` | Gold **text** and links on light backgrounds |
| Gold fill | `#C0A064` | Gold shapes, badges, mark — never small text |
| Line | `rgba(38,47,56,.12)` | Borders |

### Measured contrast (WCAG 2.x)

| Pair | Ratio | Verdict |
| --- | ---: | --- |
| White on Canvas | 19.56 | AAA |
| Muted `#B3B5BD` on Canvas | 9.56 | AAA |
| Dim `#7A7C86` on Canvas | 4.71 | AA — small captions only |
| Gold `#CDAE6F` on Canvas | 9.20 | AAA |
| Hold `#E2456B` on Canvas | 4.93 | AA |
| Slate `#262F38` on Paper | 12.47 | AAA |
| Gold ink `#806533` on Paper | 5.04 | AA |
| Gold deep `#C0A064` on Paper | 2.28 | **Fails** — shapes only |
| Canvas text on Gold button | 9.20 | AAA |

## 4. Typography

| Role | Family | Weight | Notes |
| --- | --- | --- | --- |
| Display / H1–H2 | Cal Sans | 600 | Tracking −0.005em, line-height 1.02–1.08; hero `clamp(2.5rem, 4.8vw, 3.9rem)`, section `clamp(2rem, 3.6vw, 3rem)` |
| UI and body | Geist Sans | 400 / 500 / 600 | Body 16 px, line-height 1.55 |
| Data, IDs, prices | Geist Mono | 400 / 500 | Task types (`document.ocr`), hashes, EUR amounts |
| Wordmark | Geist Sans | 600 | See section 2 |

All three are self-hosted through `@fontsource`; do not load fonts from third-party CDNs.

## 5. Shape, spacing and components

- **Radii:** pills 800 px; cards 14–16 px; large showcase panels 24 px; inputs and small tiles 8–10 px; tags 5–6 px.
- **Container:** max 1320 px, 1 rem side gutters on mobile. Section rhythm about 72 px top padding.
- **Cards:** Panel background, 1 px Line border, no drop shadow. Hover: border to Line hover plus a soft radial highlight that follows the pointer.
- **Buttons:** primary is a white pill with Canvas text; secondary is a transparent pill with a Line border. Gold is for brand emphasis, not for every CTA.
- **Brand pill:** small mark + wordmark + muted note, gold-tinted border `rgba(205,174,111,.28)`, backdrop blur.
- **Status chips:** Check for verified/edge, Hold for held/blocked, Muted for neutral. Always pair colour with text or an icon (✓ / ✕).

## 6. Glass and 3D

- Objects are **real things related to the product** (phone worker, AI chip, padlock), rendered as frosted glass with titanium/chrome details — not abstract cartoon shapes.
- Lighting: neutral environment, cool blue and soft pink rim lights, one internal glow per object.
- 3D is decorative: lazy-load it, pause offscreen, render a static frame under `prefers-reduced-motion`, and keep a non-WebGL fallback.

## 7. Motion

- Easing `cubic-bezier(0.22, 1, 0.36, 1)` (`--em-ease`) for all UI transitions.
- Motion is subtle (card hover lift 4 px, gentle 3D sway). No autoplaying loops in data views.
- Honour `prefers-reduced-motion` everywhere.

## 8. Copy rules

- Lead with **quote first, run second**: price is shown and fixed before any task runs.
- Money is always EUR shown as text exactly as published (for example `€0.0025 per page`). Never compute or round prices in UI code.
- Worker messaging: rewards are **variable and not guaranteed**; FibonAI is **not cryptocurrency mining**.
- Cloud fallback is described as allowed by policy, with the reason recorded.
- Sentence case for buttons and labels; display headlines may use title case.

## 9. Open items

- Email addresses on the marketing site still use the `edgemint.io` domain. Replace them once the FibonAI domain is confirmed.
- Vector source for the wordmark is still needed for large-format use.
