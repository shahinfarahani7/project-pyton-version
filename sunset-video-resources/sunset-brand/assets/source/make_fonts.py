#!/usr/bin/env python3
"""Sunseto's web fonts: openly licensed families (SIL OFL 1.1), cut to the weights and characters the
page uses, written as WOFF2 into fonts/ where build.py embeds them. The licence files sit beside them.

    sans   Instrument Sans      400, 500, 600   (variable font instanced at each weight)
    serif  Instrument Serif     400, 400 italic
    mono   JetBrains Mono       400, 500
    jp     Shippori Mincho      500, only the kanji and kana the page actually contains

Sources live in fonts/src (downloaded from github.com/google/fonts). Also writes a static Instrument Sans
Medium TTF to tools/ for the logo lockups and the three.js typeface.

    python3 tools/make_fonts.py
"""
import pathlib, re, io
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer
from fontTools import subset

HERE = pathlib.Path(__file__).resolve().parent.parent
SRC, OUT = HERE / 'fonts' / 'src', HERE / 'fonts'

LATIN = ''.join(chr(c) for c in range(0x20, 0x7F)) + ''.join(chr(c) for c in range(0xA0, 0x180)) + '‘’“”–—…•·→←↗↑↓°¥€×÷'


def page_cjk():
    txt = ''.join(p.read_text(errors='ignore') for p in list((HERE / 'src').glob('*.js')) + [HERE / 'src' / 'page.html'])
    return ''.join(sorted(set(re.findall(r'[　-ヿ㐀-鿿＀-￯]', txt))))


def write(font, name, text):
    opts = subset.Options(); opts.flavor = 'woff2'; opts.layout_features = ['*']; opts.name_IDs = ['*']; opts.notdef_outline = True
    sub = subset.Subsetter(opts); sub.populate(text=text); sub.subset(font)
    font.flavor = 'woff2'; font.save(OUT / name)
    print(f'{name:28s} {(OUT / name).stat().st_size / 1024:6.1f} KB')


def main():
    for w in (400, 500, 600):
        f = instancer.instantiateVariableFont(TTFont(SRC / 'InstrumentSans[wdth,wght].ttf'), {'wght': w, 'wdth': 100})
        if w == 500:
            f.save(HERE / 'tools' / 'InstrumentSans-Medium.ttf')
            f = TTFont(HERE / 'tools' / 'InstrumentSans-Medium.ttf')
        write(f, f'instrument-sans-{w}.woff2', LATIN)
    write(TTFont(SRC / 'InstrumentSerif-Regular.ttf'), 'instrument-serif-400.woff2', LATIN)
    write(TTFont(SRC / 'InstrumentSerif-Italic.ttf'), 'instrument-serif-400i.woff2', LATIN)
    for w in (400, 500):
        write(instancer.instantiateVariableFont(TTFont(SRC / 'JetBrainsMono[wght].ttf'), {'wght': w}), f'jetbrains-mono-{w}.woff2', LATIN)
    cjk = page_cjk()
    write(TTFont(SRC / 'ShipporiMincho-Medium.ttf'), 'shippori-mincho-500.woff2', cjk + '・「」、。')
    print('kanji/kana kept:', cjk)


if __name__ == '__main__':
    main()
