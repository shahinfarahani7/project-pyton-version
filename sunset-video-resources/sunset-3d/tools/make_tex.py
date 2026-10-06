#!/usr/bin/env python3
"""Poly Haven CC0 scans -> WebP texture sets for the page.
   <name>_c.webp  albedo (sRGB)          <name>_n.webp  OpenGL normal
   <name>_r.webp  packed R=AO G=roughness B=0 (three: aoMap reads R, roughnessMap reads G)"""
import pathlib
from PIL import Image
Image.MAX_IMAGE_PIXELS = None
HERE = pathlib.Path(__file__).resolve().parent.parent
SRC, OUT = HERE / 'originals' / 'polyhaven', HERE / 'assets' / 'tex'
SETS = {  # name -> (source prefix, source res, colour/normal edge, orm edge)
    'sugi':    ('kitchen_wood', '4k', 4096, 2048),       # silver-grey weathered cedar -> exterior siding, fence
    'mahogany':('dark_wood', '4k', 4096, 2048),           # red mahogany -> lacquer, dark interior, darkened beams
    'darkwood':('fine_grained_wood', '2k', 2048, 1024),  # dark aged raw timber -> posts, beams, rafters
    'hinoki':  ('oak_veneer_01', '2k', 2048, 1024),      # pale cathedral grain -> hinoki panels, cabinet, chart plinth
    'deck':    ('wood_floor_deck', '2k', 2048, 1024),    # warm deck boards -> engawa floor
    'plaster': ('plastered_wall', '2k', 2048, 1024),     # light plaster -> shikkui walls
}
for name, (pre, res, edge, oedge) in SETS.items():
    c = Image.open(SRC / f'{pre}_diff_{res}.jpg').convert('RGB')
    n = Image.open(SRC / f'{pre}_nor_{res}.jpg').convert('RGB')
    r = Image.open(SRC / f'{pre}_rough_{res}.jpg').convert('L')
    try: a = Image.open(SRC / f'{pre}_ao_{res}.jpg').convert('L')
    except FileNotFoundError: a = Image.new('L', r.size, 255)
    fit = lambda im, e: im if im.width <= e else im.resize((e, e), Image.LANCZOS)
    fit(c, edge).save(OUT / f'{name}_c.webp', quality=88, method=6)
    fit(n, edge).save(OUT / f'{name}_n.webp', quality=92, method=6)
    a, r = fit(a, oedge), fit(r, oedge)
    Image.merge('RGB', (a, r, Image.new('L', r.size, 0))).save(OUT / f'{name}_r.webp', quality=90, method=6)
    print(name, *(f"{(OUT/f'{name}_{k}.webp').stat().st_size/1e6:.2f}MB" for k in 'cnr'))
