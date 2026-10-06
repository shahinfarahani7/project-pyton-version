#!/usr/bin/env python3
"""Sunseto logo as transparent PNGs: the 3D mark (tools/mark.html) + lowercase wordmark (Instrument Sans
SemiBold, OFL) + the keyed 陽 hanko.
Writes img/logo_<variant>.png (full lockup) plus the loader's aligned word/stamp layers."""
import pathlib
from PIL import Image, ImageDraw, ImageFont
HERE = pathlib.Path(__file__).resolve().parent.parent
TTF = str(HERE / 'tools' / 'InstrumentSans-SemiBold.ttf')
S, W, H = 4, 1500, 420


def semibold():
    """A static Instrument Sans SemiBold for the wordmark, from the variable source."""
    import os
    if not os.path.exists(TTF):
        from fontTools.ttLib import TTFont
        from fontTools.varLib import instancer
        instancer.instantiateVariableFont(TTFont(HERE / 'fonts' / 'src' / 'InstrumentSans[wdth,wght].ttf'), {'wght': 600, 'wdth': 100}).save(TTF)


def layers(color):
    """Mark + lowercase wordmark on one layer, the 陽 seal on another (the loader stamps it in)."""
    semibold()
    word = Image.new('RGBA', (W * S, H * S), (0, 0, 0, 0)); d = ImageDraw.Draw(word)
    variant = 'ink' if sum(color[:3]) < 200 else 'cream'
    mk = Image.open(HERE / 'tools' / f'mark_{variant}.png').convert('RGBA'); mk = mk.crop(mk.getbbox())
    mh = int(150 * S); mw = int(mk.width * mh / mk.height)
    ox, base = 40 * S, 300 * S                                      # the wordmark baseline sits level with the first wave
    word.alpha_composite(mk.resize((mw, mh), Image.LANCZOS), (ox, base - int(mh * .72)))
    fnt = ImageFont.truetype(TTF, 172 * S); x = ox + mw + 34 * S
    for ch in 'sunseto': d.text((x, base), ch, font=fnt, fill=color, anchor='ls'); x += fnt.getlength(ch) - 6 * S
    stamp = Image.new('RGBA', word.size, (0, 0, 0, 0))
    st = Image.open(HERE / 'originals' / 'hanko_keyed.png').convert('RGBA'); sz = int(128 * S)
    st = st.resize((sz, sz), Image.LANCZOS).rotate(-7, resample=Image.BICUBIC, expand=True)
    stamp.alpha_composite(st, (int(x + 26 * S), int(base - sz * .95)))
    return word.resize((W, H), Image.LANCZOS), stamp.resize((W, H), Image.LANCZOS)


def export(color, name, loader=False):
    word, stamp = layers(color)
    full = word.copy(); full.alpha_composite(stamp)
    bb = full.getbbox(); box = (bb[0] - 8, bb[1] - 8, bb[2] + 8, bb[3] + 8)
    full.crop(box).save(HERE / 'img' / f'logo_{name}.png', optimize=True)
    if loader:
        word.crop(box).save(HERE / 'img' / 'logo_word.png', optimize=True)
        stamp.crop(box).save(HERE / 'img' / 'logo_stamp.png', optimize=True)
    print(name, full.crop(box).size)

export((255, 243, 228, 255), 'sunseto', loader=True)   # cream: loader, footer, dark sections
export((22, 17, 14, 255), 'ink')                        # ink: the glass nav over light sections
