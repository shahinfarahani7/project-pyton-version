#!/usr/bin/env python3
"""Sunseto brand guide: gather the kit.

Copies the brand files from ../sunset-assets (read only: nothing there is moved or changed) into
assets/, grouped the way the guide's Downloads chapter lists them, and derives the few files the site
never needed as separate files:

    assets/mark/sunseto-mark-{colour,ink,cream,paper}.svg   the flat mark in each approved colourway
    assets/textures/grain.png                               the site's paper grain (same seed as build.py)
    assets/guide/...                                        display-size copies for the guide page itself
    assets/guide/shippori-guide.woff2                       Shippori Mincho cut to the kanji this guide sets

    python3 tools/make_assets.py
"""
import pathlib, shutil, re, io, random
from PIL import Image

HERE = pathlib.Path(__file__).resolve().parent.parent
SITE = HERE.parent / 'sunset-assets'
A = HERE / 'assets'

COPY = {
    'logo': ['img/ui/logo_sunseto.webp', 'img/ui/logo_sunseto_nav.webp', 'img/ui/logo_ink_nav.webp', 'img/ui/logo_word.webp', 'img/ui/logo_stamp.webp',
             'img/logo_sunseto.png', 'img/logo_ink.png', 'img/logo_word.png', 'img/logo_stamp.png', 'img/logo_sunseto_nav.png', 'img/logo_ink_nav.png'],
    'mark': ['sunseto-mark.svg', 'mark.json', 'tools/mark_cream.png', 'tools/mark_ink.png'],
    'seal': ['img/layers/hanko.webp', 'img/ui/orn_appicon.webp', 'img/orn_appicon.png'],
    'fonts': ['fonts/instrument-serif-400.woff2', 'fonts/instrument-serif-400i.woff2', 'fonts/instrument-sans-400.woff2', 'fonts/instrument-sans-500.woff2',
              'fonts/instrument-sans-600.woff2', 'fonts/jetbrains-mono-400.woff2', 'fonts/jetbrains-mono-500.woff2', 'fonts/shippori-mincho-500.woff2'],
    'fonts/licenses': ['fonts/licenses/instrumentserif-OFL.txt', 'fonts/licenses/instrumentsans-OFL.txt', 'fonts/licenses/jetbrainsmono-OFL.txt', 'fonts/licenses/shipporimincho-OFL.txt'],
    'ornaments': ['img/layers/orn_crane.webp', 'img/layers/orn_lantern.webp', 'img/layers/orn_fan.webp', 'img/layers/orn_sakura.webp'],
    'stamps': ['img/ui/stamp_kyoto.webp', 'img/ui/stamp_chiba.webp', 'img/ui/stamp_onomichi.webp'],
    'engravings': ['img/w_jaerial.webp', 'img/w_jliving.webp', 'img/w_jrain.webp', 'img/w_jstorm.webp', 'img/w_sunhand.webp',
                   'img/w_aerial.webp', 'img/w_living.webp', 'img/w_stormhouse.webp', 'img/w_stormsky.webp', 'img/w_wildfire.webp'],
    'textures': ['img/ui/chart_wood.webp', 'img/ui/chart_sky.webp'],
    'source': ['tools/make_mark.py', 'tools/make_logo.py', 'tools/mark.html', 'tools/make_fonts.py'],
}

# the flat mark's approved colourways: sun, sea
MARKS = {'colour': ('#e5482f', '#2a1d52'), 'ink': ('#111111', '#111111'), 'cream': ('#fff7e9', '#fff7e9'), 'paper': ('#e5482f', '#4c2806')}

# the kanji and kana this guide sets (the site's own subset only carries 陽 小 中 大 夕 日)
GUIDE_CJK = '陽小中大夕日印色字間器絵流声守箱目次朱藍紺和紙墨生成罫焦茶鼠藤瑠璃群青鉄洗茄子杏夜明'


def copy():
    n = 0
    for folder, files in COPY.items():
        (A / folder).mkdir(parents=True, exist_ok=True)
        for f in files:
            src = SITE / f
            dst = A / folder / src.name
            if not dst.exists() or dst.stat().st_mtime < src.stat().st_mtime or dst.stat().st_size != src.stat().st_size:
                shutil.copy2(src, dst); n += 1
    print('copied', n, 'files')


def marks():
    svg = (SITE / 'sunseto-mark.svg').read_text()
    for name, (sun, sea) in MARKS.items():
        out = svg.replace('var(--mark-sun, currentColor)', sun).replace('var(--mark-sea, currentColor)', sea)
        (A / 'mark' / f'sunseto-mark-{name}.svg').write_text(out)
    print('marks', list(MARKS))


def grain():
    """The paper grain exactly as build.py makes it: 180 px, seed 7, gaussian round mid grey."""
    random.seed(7)
    n = 180
    im = Image.new('L', (n, n))
    im.putdata([max(0, min(255, int(random.gauss(128, 46)))) for _ in range(n * n)])
    (A / 'textures').mkdir(parents=True, exist_ok=True)
    im.save(A / 'textures' / 'grain.png', optimize=True)


def display():
    """Display-size copies for the guide page (the downloads link to the full-size files)."""
    g = A / 'guide'; g.mkdir(parents=True, exist_ok=True)
    for f in sorted((A / 'engravings').glob('*.webp')):
        im = Image.open(f); im.thumbnail((1400, 1400), Image.LANCZOS)
        im.save(g / f.name, 'WEBP', quality=82, method=6)
    for f in sorted((A / 'tiles').glob('*.webp')) if (A / 'tiles').exists() else []:
        im = Image.open(f); im.thumbnail((900, 1200), Image.LANCZOS)
        im.save(g / ('t_' + f.name), 'WEBP', quality=84, method=6)
    print('display copies written')


def font():
    from fontTools.ttLib import TTFont
    from fontTools import subset
    opts = subset.Options(); opts.flavor = 'woff2'; opts.layout_features = ['*']; opts.name_IDs = ['*']; opts.notdef_outline = True
    f = TTFont(SITE / 'fonts' / 'src' / 'ShipporiMincho-Medium.ttf')
    sub = subset.Subsetter(opts); sub.populate(text=GUIDE_CJK + '・「」、。'); sub.subset(f)
    f.flavor = 'woff2'; f.save(A / 'guide' / 'shippori-guide.woff2')
    print('guide kanji font', round((A / 'guide' / 'shippori-guide.woff2').stat().st_size / 1024, 1), 'KB')


if __name__ == '__main__':
    copy(); marks(); grain(); display(); font()
