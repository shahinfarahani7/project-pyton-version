#!/usr/bin/env python3
"""Build the Sunseto brand guide: src/page.html + guide.css + guide.js -> ../sunset-brand.html.

The page links its images and fonts from sunset-brand/assets/ (run tools/make_assets.py first, and
tools/capture-site.mjs for the 3D tiles). This script also writes the Downloads chapter from what is
actually in assets/ (sizes and dimensions read from the files), small thumbnails for that list, and
assets/sunseto-brand-kit.zip with every downloadable file.

    python3 build.py
"""
import pathlib, re, zipfile, urllib.parse, html, datetime
from PIL import Image

HERE = pathlib.Path(__file__).resolve().parent
SRC, A = HERE / 'src', HERE / 'assets'
OUT = HERE.parent / 'sunset-brand.html'
PREFIX = 'sunset-brand/assets'
EDITION = 'September 2026'

# the Downloads chapter: group, folder, [(file, note)], thumbnail background
GROUPS = [
    ('Logo', 'logo', [
        ('logo_sunseto.png', 'Full lockup, cream · master'), ('logo_ink.png', 'Full lockup, ink · master'),
        ('logo_sunseto.webp', 'Full lockup, cream'), ('logo_sunseto_nav.webp', 'Nav lockup, cream'), ('logo_ink_nav.webp', 'Nav lockup, ink'),
        ('logo_sunseto_nav.png', 'Nav lockup, cream · master'), ('logo_ink_nav.png', 'Nav lockup, ink · master'),
        ('logo_word.webp', 'Mark and wordmark, no seal (the loader’s layer)'), ('logo_word.png', 'Mark and wordmark · master'),
        ('logo_stamp.webp', 'The seal alone, aligned to the lockup'), ('logo_stamp.png', 'The seal alone · master')]),
    ('Mark', 'mark', [
        ('sunseto-mark-colour.svg', 'Flat mark · sun #E5482F, sea #2A1D52'), ('sunseto-mark-paper.svg', 'Flat mark · sun and brown'),
        ('sunseto-mark-ink.svg', 'Flat mark · ink'), ('sunseto-mark-cream.svg', 'Flat mark · cream'),
        ('sunseto-mark.svg', 'Flat mark · takes --mark-sun and --mark-sea'), ('mark_cream.png', 'Enamel mark, cream · 3D render'),
        ('mark_ink.png', 'Enamel mark, ink · 3D render'), ('mark.json', 'Mark geometry as polygons, 44 × 32')]),
    ('Seal and icon', 'seal', [('hanko.webp', '陽 seal, keyed'), ('orn_appicon.png', 'App icon · master'), ('orn_appicon.webp', 'App icon')]),
    ('Fonts', 'fonts', [
        ('instrument-serif-400.woff2', 'Instrument Serif Regular'), ('instrument-serif-400i.woff2', 'Instrument Serif Italic'),
        ('instrument-sans-400.woff2', 'Instrument Sans Regular'), ('instrument-sans-500.woff2', 'Instrument Sans Medium'),
        ('instrument-sans-600.woff2', 'Instrument Sans SemiBold'), ('jetbrains-mono-400.woff2', 'JetBrains Mono Regular'),
        ('jetbrains-mono-500.woff2', 'JetBrains Mono Medium'), ('shippori-mincho-500.woff2', 'Shippori Mincho Medium · the site’s kanji'),
        ('licenses/instrumentserif-OFL.txt', 'SIL Open Font License 1.1'), ('licenses/instrumentsans-OFL.txt', 'SIL Open Font License 1.1'),
        ('licenses/jetbrainsmono-OFL.txt', 'SIL Open Font License 1.1'), ('licenses/shipporimincho-OFL.txt', 'SIL Open Font License 1.1')]),
    ('Ornaments', 'ornaments', [('orn_crane.webp', 'Orizuru, the paper crane'), ('orn_lantern.webp', 'Chōchin, the lantern'), ('orn_fan.webp', 'Sensu, the fan'), ('orn_sakura.webp', 'Sakura, a sprig')]),
    ('Stamps', 'stamps', [('stamp_kyoto.webp', 'Kyoto · machiya window'), ('stamp_chiba.webp', 'Chiba · rain on the street'), ('stamp_onomichi.webp', 'Onomichi · the harbour at sunset')]),
    ('Engravings', 'engravings', [
        ('w_jaerial.webp', 'Roof by roof · harbour town'), ('w_jliving.webp', 'Keep the evening · tea at home'), ('w_jrain.webp', 'What we face · rain'),
        ('w_jstorm.webp', 'Why now · the storm'), ('w_sunhand.webp', 'From roof to room · the held sun'),
        ('w_aerial.webp', 'Archive · earlier US set, not for Japan'), ('w_living.webp', 'Archive · earlier US set'), ('w_stormhouse.webp', 'Archive · earlier US set'),
        ('w_stormsky.webp', 'Archive · earlier US set'), ('w_wildfire.webp', 'Archive · earlier US set')]),
    ('3D tiles', 'tiles', [
        ('tile-house.webp', 'Spend less · the house'), ('tile-battery.webp', 'Stay on · the battery'), ('tile-hand.webp', 'See it · the hand'),
        ('tile-machiya.webp', 'Step 1 · the machiya'), ('tile-cedar-yard.webp', 'Step 1 · the cedar yard'), ('tile-phone.webp', 'Step 1 · the phone'),
        ('tile-step2.webp', 'Step 2 · the fitting drawing'), ('tile-dusk.webp', 'Step 3 · dusk, Shiga'), ('tile-storm.webp', 'Step 3 · the storm'),
        ('tile-network.webp', 'Network · the map'), ('tile-hero.webp', 'The hero, first screen')]),
    ('Textures', 'textures', [('chart_wood.webp', 'Hinoki, baked for the chart tray'), ('chart_sky.webp', 'The engraving on the chart paper'), ('grain.png', 'Paper grain, 180 px tile')]),
    ('Source', 'source', [('make_mark.py', 'The mark’s geometry'), ('make_logo.py', 'The lockups'), ('mark.html', 'The enamel render (three.js)'), ('make_fonts.py', 'The font subsets')]),
]
DARK_THUMB = {'logo_sunseto.png', 'logo_sunseto.webp', 'logo_sunseto_nav.webp', 'logo_sunseto_nav.png', 'logo_word.webp', 'logo_word.png', 'mark_cream.png', 'sunseto-mark-cream.svg'}
DL_ICON = '<svg viewBox="0 0 11 11" aria-hidden="true"><path d="M5.5 1v7M2.2 4.9 5.5 8.2l3.3-3.3M1 10h9" fill="none" stroke="currentColor" stroke-width="1.1"/></svg>'


def size(n):
    return f'{n / 1024:.0f} KB' if n < 1024 * 1024 else f'{n / 1024 / 1024:.1f} MB'


def dims(p):
    if p.suffix in ('.png', '.webp', '.jpg'):
        with Image.open(p) as im: return f'{im.width} × {im.height}'
    if p.suffix == '.svg':
        m = re.search(r'viewBox="0 0 ([\d.]+) ([\d.]+)"', p.read_text()); return f'{m.group(1)} × {m.group(2)} vector' if m else 'vector'
    return ''


def thumb(p, folder):
    """A 112 px thumbnail for raster files (the list would otherwise pull megabytes of engravings)."""
    t = A / 'guide' / 'thumbs'; t.mkdir(parents=True, exist_ok=True)
    out = t / f'{folder}__{p.stem}.webp'
    if not out.exists() or out.stat().st_mtime < p.stat().st_mtime:
        with Image.open(p) as im:
            im = im.convert('RGBA'); im.thumbnail((168, 126), Image.LANCZOS); im.save(out, 'WEBP', quality=80)
    return f'{PREFIX}/guide/thumbs/{out.name}'


def downloads():
    parts, files = [], []
    for title, folder, items in GROUPS:
        rows, total = [], 0
        for name, note in items:
            p = A / folder / name
            if not p.exists():
                print('  missing', folder, name); continue
            files.append((folder, name, p)); total += p.stat().st_size
            ext = p.suffix.lstrip('.').upper()
            href = f'{PREFIX}/{folder}/{name}'
            if p.suffix in ('.png', '.webp'):
                cls = ' dark' if name in DARK_THUMB else ''
                th = f'<img class="th{cls}" src="{thumb(p, folder)}" alt="" loading="lazy" style="object-fit:{"cover" if folder in ("engravings", "tiles", "textures", "stamps") else "contain"}">'
            elif p.suffix == '.svg':
                cls = ' dark' if name in DARK_THUMB else ''
                th = f'<img class="th{cls}" src="{href}" alt="" loading="lazy" style="object-fit:contain;padding:6px">'
            elif p.suffix == '.woff2':
                fam = 'j' if 'shippori' in name else 'm' if 'mono' in name else 's' if 'sans' in name else ''
                glyph = '陽' if fam == 'j' else 'Aa'
                style = ' style="font-style:italic"' if name.endswith('400i.woff2') else ''
                th = f'<span class="th type {fam}"{style}>{glyph}</span>'
            else:
                th = f'<span class="th type m">{{ }}</span>' if p.suffix in ('.py', '.json', '.html') else '<span class="th type m">txt</span>'
            rows.append(f'<li>{th}<div class="fn">{html.escape(name.split("/")[-1])}<small>{html.escape(note)}</small></div>'
                        f'<span class="px">{dims(p)}</span><span class="ty">{ext}</span><span class="sz">{size(p.stat().st_size)}</span>'
                        f'<a class="get" href="{href}" download>{DL_ICON}Get</a></li>')
        parts.append(f'<div class="dl-group"><h4>{title}<span class="mono">{len(rows)} files · {size(total)}</span></h4><ul class="dl">{"".join(rows)}</ul></div>')
    return '\n'.join(parts), files


def kit(files):
    z = A / 'sunseto-brand-kit.zip'
    readme = ('Sunseto brand kit, edition 01 (' + EDITION + ')\n\n'
              'Logo, mark, seal and icon, ornaments, stamps, engravings, 3D tiles and textures: Sunseto. Use them for Sunseto only.\n'
              'Fonts: SIL Open Font License 1.1, licences in fonts/licenses. Instrument Sans and Serif by Instrument; JetBrains Mono by JetBrains;\n'
              'Shippori Mincho by FONTDASU (cut to the kanji the site uses).\n'
              'Source: the scripts that draw the mark, render the enamel version, lay out the lockups and cut the fonts.\n')
    with zipfile.ZipFile(z, 'w', zipfile.ZIP_DEFLATED) as zf:
        zf.writestr('sunseto-brand-kit/README.txt', readme)
        for folder, name, p in files: zf.write(p, f'sunseto-brand-kit/{folder}/{name}')
    return z


def main():
    page = (SRC / 'page.html').read_text()
    css, js = (SRC / 'guide.css').read_text(), (SRC / 'guide.js').read_text()
    page = page.replace('{{CSS}}', css).replace('{{JS}}', js)
    mark = (A / 'mark' / 'sunseto-mark.svg').read_text()
    inner = mark[mark.index('>') + 1:mark.rindex('</svg>')]
    fav = inner.replace('var(--mark-sun, currentColor)', '#e5482f').replace('var(--mark-sea, currentColor)', '#2a1d52')
    sun = re.search(r'class="m-sun"[^>]*d="([^"]+)"', mark).group(1)
    dl, files = downloads()
    z = kit(files)
    total = sum(p.stat().st_size for _, _, p in files)
    page = (page.replace('{{DOWNLOADS}}', dl).replace('{{MARK_URI}}', urllib.parse.quote(fav, safe=' =:/.-')).replace('{{MARK}}', '<use href="#mk"/>').replace('{{MARK_SYMBOL}}', f'<symbol id="mk" viewBox="0 0 44 32">{inner}</symbol>')
            .replace('{{SUN_PATH}}', sun).replace('{{DATE}}', EDITION).replace('{{KIT_COUNT}}', str(len(files)))
            .replace('{{KIT_SIZE}}', size(total)).replace('{{ZIP_SIZE}}', size(z.stat().st_size)).replace('{{A}}', PREFIX))
    left = re.findall(r'\{\{[A-Z_]+\}\}', page)
    if left: print('  unfilled:', sorted(set(left)))
    OUT.write_text(page)
    print(f'wrote {OUT.name} ({OUT.stat().st_size / 1024:.0f} KB), {len(files)} downloads ({size(total)}), kit {size(z.stat().st_size)}')


if __name__ == '__main__':
    main()
