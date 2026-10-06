#!/usr/bin/env python3
"""Aura can't output alpha: ornaments are shot on flat chroma green and keyed here by greenness (g - max(r, b)).
The key colour is un-mixed from edge pixels, (C - (1 - a) K) / a, so no green fringe survives (after sunset-assets/tools/make_layers.py).
    python3 tools/key_layers.py"""
import pathlib
import numpy as np
from PIL import Image
HERE = pathlib.Path(__file__).resolve().parent.parent
SRC, OUT = HERE / 'originals' / 'aura', HERE / 'assets' / 'img'
LAYERS = {'branch-1': 2048, 'branch-2': 1536}   # name -> max edge

def key_green(path):
    im = np.asarray(Image.open(path).convert('RGB')).astype(np.float32)
    border = np.concatenate([im[:4].reshape(-1, 3), im[-4:].reshape(-1, 3), im[:, :4].reshape(-1, 3), im[:, -4:].reshape(-1, 3)])
    gm = border[:, 1] - np.maximum(border[:, 0], border[:, 2])
    K = np.median(border[gm > 150], axis=0)
    kg = K[1] - max(K[0], K[2])
    a = 1 - np.clip((im[..., 1] - np.maximum(im[..., 0], im[..., 2]) - .14 * kg) / (.8 * kg), 0, 1)
    a[a < .03] = 0; a[a > .97] = 1
    obj = np.clip((im - (1 - a[..., None]) * K) / np.maximum(a, 1e-3)[..., None], 0, 255)
    # residual spill: green can't exceed the brighter of red/blue on petals and bark
    g_cap = np.maximum(obj[..., 0], obj[..., 2]) * 1.02 + 6
    obj[..., 1] = np.where(a < .999, np.minimum(obj[..., 1], g_cap), obj[..., 1])
    obj[a == 0] = 0
    return Image.fromarray(np.dstack([obj.astype(np.uint8), (a * 255 + .5).astype(np.uint8)]), 'RGBA')

for name, edge in LAYERS.items():
    im = key_green(SRC / f'{name}.png')
    bb = im.getchannel('A').getbbox(); im = im.crop(bb)
    if max(im.size) > edge: im.thumbnail((edge, edge), Image.LANCZOS)
    im.save(OUT / f'{name}.webp', quality=88, alpha_quality=92, method=6)
    print(name, im.size, (OUT / f'{name}.webp').stat().st_size // 1024, 'KB')
