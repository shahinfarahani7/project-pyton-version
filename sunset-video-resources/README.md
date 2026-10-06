# Sunset project files

This bundle accompanies Meng To's tutorial about building a 3D solar website, brand guide and advertising concepts with Claude Code, Opus 5.5 and Mobbin.

## Included

- `sunset.html`: the selected landing-page HTML.
- `sunset-brand.html`: the selected brand-guide HTML.
- `sunset-ads.html`: the selected advertising-showcase HTML.
- `sunset-brand/`: brand assets, fonts and source files.
- `sunset-ads/`: advertising assets, mockups, print files and tools.
- `sunset-3d/`: the separate 3D build, scenes, models, textures and logo explorations.
- `guide.pdf`: the written workflow guide.
- `prompts.md`: reusable prompts adapted from the narrated tutorial.
- `checksums.json`: SHA-256 values for every original selected file.

All six selected items are preserved together. This includes the supporting source artwork and files, not only the three HTML pages. Versions were copied from the files selected on 25 September 2026, after the recording; they are not claimed to be byte-identical to every intermediate state in the video.

## Open the demos

Extract the entire ZIP first. Keep the three HTML files and three folders in the same directory.

For consistent loading, start a local HTTP server in the extracted folder. If Python 3 is installed:

```sh
python3 -m http.server 8000
```

Then open:

- `http://localhost:8000/sunset.html`
- `http://localhost:8000/sunset-brand.html`
- `http://localhost:8000/sunset-ads.html`
- `http://localhost:8000/sunset-3d/index.html`

Use a modern browser with WebGL enabled. The 3D project uses JavaScript modules and should be opened through HTTP rather than `file://`. Some resources use external CDNs and Google Fonts, so an internet connection may be required. Build and capture tools are optional; they are not needed just to view the pages.

The selected source folders include their original development tools. Their scripts may contain machine-specific paths. The viewing instructions above do not require those scripts.

The brand is called Sunset in the narration; several finished assets use Sunseto. Prices, savings, testimonials and contact forms are design-demo content. Preserve the supplied asset credits and license files when reusing assets.
