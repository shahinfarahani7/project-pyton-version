#!/usr/bin/env python3
"""Build ../sunset-ads.html from page.src.html with every image, font and the mark inlined, so the page works
opened as a file, in the desktop Browser pane (which serves local files as data: URLs), or sent elsewhere."""
import base64, pathlib, re, json

HERE = pathlib.Path(__file__).resolve().parent.parent          # sunset-ads/
ROOT = HERE.parent                                             # HTML Pages/
MIME = {'.jpg': 'image/jpeg', '.png': 'image/png', '.ttf': 'font/ttf', '.woff2': 'font/woff2'}

def uri(rel):
    p = ROOT / rel
    return f"data:{MIME[p.suffix]};base64," + base64.b64encode(p.read_bytes()).decode()

html = (HERE / 'page.src.html').read_text(encoding='utf-8')
# the zoom viewer shows the inlined image itself at its natural size; no links out to the multi-MB print files
html = re.sub(r'\sdata-full="[^"]*"', ' data-full', html)
html = html.replace("VI.src = i.dataset.full;", "VI.src = i.currentSrc || i.src;")
html = re.sub(r'src="(sunset-ads/[^"]+)"', lambda m: f'src="{uri(m.group(1))}"', html)
html = re.sub(r'url\((sunset-ads/[^)]+)\)', lambda m: f'url({uri(m.group(1))})', html)
mark = json.loads((HERE / 'assets/img/mark.json').read_text())
html = html.replace("fetch('sunset-ads/assets/img/mark.json').then(r => r.json()).then(M => {",
                    "Promise.resolve(" + json.dumps(mark, separators=(',', ':')) + ").then(M => {")
assert 'sunset-ads/' not in re.sub(r'<(footer|span class="file")[\s\S]*?</\1>', '', html.split('<footer')[0]), 'a relative asset path is left'
out = ROOT / 'sunset-ads.html'
out.write_text(html, encoding='utf-8')
print(f'wrote {out} ({out.stat().st_size / 1e6:.1f} MB)')
