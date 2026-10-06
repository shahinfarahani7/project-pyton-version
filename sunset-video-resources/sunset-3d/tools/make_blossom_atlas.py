#!/usr/bin/env python3
"""Photographic sakura blossom clusters (Aura, on chroma green) -> a keyed 3x3 atlas for canopy cards.
   assets/img/blossom-atlas.webp  RGBA, 3x3 cells, each cluster re-centred in its cell
   assets/img/blossom-atlas.json  { cols, rows, cells: [{ u0, v0, u1, v1, cx, cy, r, stem:[u,v] }] } (uv, v up)"""
import json, pathlib, sys
import numpy as np
from PIL import Image
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from key_layers import key_green
HERE = pathlib.Path(__file__).resolve().parent.parent
im = key_green(HERE / 'originals/aura/blossom-atlas.png')
a = np.asarray(im)[..., 3]
W, H = im.size; N = 3; cell = W // N; OUT = 512            # 3x512 = 1536 atlas
atlas = Image.new('RGBA', (OUT * N, OUT * N), (0, 0, 0, 0)); cells = []
for j in range(N):
    for i in range(N):
        box = (i * cell, j * cell, (i + 1) * cell, (j + 1) * cell)
        sub = im.crop(box); sa = np.asarray(sub)[..., 3]
        ys, xs = np.nonzero(sa > 8)
        x0, x1, y0, y1 = xs.min(), xs.max(), ys.min(), ys.max()
        c = sub.crop((x0, y0, x1 + 1, y1 + 1))
        s = (OUT - 24) / max(c.size); c = c.resize((max(1, round(c.width * s)), max(1, round(c.height * s))), Image.LANCZOS)
        ox, oy = i * OUT + (OUT - c.width) // 2, j * OUT + (OUT - c.height) // 2
        atlas.alpha_composite(c, (ox, oy))
        # stem: the darkest opaque pixels (bark) — their centroid, for orienting the card toward its branch
        rgb = np.asarray(c).astype(np.float32); m = (rgb[..., 3] > 200) & (rgb[..., :3].sum(-1) < 240)
        sy, sx = (np.nonzero(m) if m.any() else (np.array([c.height - 1]), np.array([c.width // 2])))
        stem = [(ox + sx.mean()) / (OUT * N), 1 - (oy + sy.mean()) / (OUT * N)]
        cells.append({'u0': i / N, 'v0': 1 - (j + 1) / N, 'u1': (i + 1) / N, 'v1': 1 - j / N, 'stem': [round(v, 4) for v in stem]})
atlas.save(HERE / 'assets/img/blossom-atlas.webp', quality=90, alpha_quality=95, method=6)
json.dump({'cols': N, 'rows': N, 'size': OUT * N, 'cells': cells, 'note': 'photographic clusters keyed from chroma green; straight (non-premultiplied) alpha; lit flat — apply scene lighting/translucency in the shader'}, open(HERE / 'assets/img/blossom-atlas.json', 'w'), indent=1)
print('atlas', atlas.size, (HERE / 'assets/img/blossom-atlas.webp').stat().st_size // 1024, 'KB')
