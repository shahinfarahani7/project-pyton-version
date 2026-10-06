#!/usr/bin/env python3
"""The Sunseto mark: a sun setting into the sea. One definition, written out twice:

    sunseto-mark.svg   for the DOM (the sun and the sea take separate colours via CSS variables)
    mark.json          polygons for the page's canvases and three.js shapes (src/mark.js reads it)

Geometry, in a 44 x 32 box with y down: a sun disc sinking behind the horizon, clipped a little above
the first wave so a sliver of sky separates them, and three waves below it, each shorter than the one
above, drawn as round-capped strokes with two gentle crests. No rays: the mark is the sun meeting the
water.

    python3 tools/make_mark.py
"""
import json, math, pathlib

HERE = pathlib.Path(__file__).resolve().parent.parent
W, H = 44, 32
SUN = dict(cx=22, cy=15.4, r=10.4, clip=18.7)
SW = 2.2                                                             # wave stroke width
WAVES = [dict(y=21.3, x0=3.2, x1=40.8), dict(y=25.6, x0=8.6, x1=35.4), dict(y=29.8, x0=14.2, x1=29.8)]
AMP, LAMBDA = .62, 12.4


def sun_polygon(n=96):
    c, r, clip = SUN['cx'], SUN['r'], SUN['clip']
    a0 = math.asin((clip - SUN['cy']) / r)                          # angle where the circle meets the clip line
    pts = []
    for i in range(n + 1):                                          # the arc above the clip, from right to left
        a = a0 - (math.pi + 2 * a0) * i / n
        pts.append((c + r * math.cos(a), SUN['cy'] + r * math.sin(a)))
    return pts


def wave_polygon(w, n=80):
    """A round-capped stroke along y = y0 + A sin(...), as one closed outline."""
    xs = [w['x0'] + (w['x1'] - w['x0']) * i / n for i in range(n + 1)]
    f = lambda x: w['y'] + AMP * math.sin(2 * math.pi * (x - 22) / LAMBDA + math.pi / 2)
    df = lambda x: AMP * 2 * math.pi / LAMBDA * math.cos(2 * math.pi * (x - 22) / LAMBDA + math.pi / 2)
    top, bot = [], []
    for x in xs:
        y, d = f(x), df(x); L = math.hypot(1, d); nx, ny = -d / L, 1 / L
        top.append((x - nx * SW / 2, y - ny * SW / 2)); bot.append((x + nx * SW / 2, y + ny * SW / 2))
    def cap(x, y, d, start):                                        # a half circle around the end point
        a = math.atan2(d, 1); pts = []
        for i in range(1, 12):
            t = a + (math.pi / 2 + math.pi * i / 12 if start else -math.pi / 2 + math.pi * i / 12)
            pts.append((x + math.cos(t) * SW / 2, y + math.sin(t) * SW / 2))
        return pts
    x1, x0 = xs[-1], xs[0]
    return top + cap(x1, f(x1), df(x1), False) + bot[::-1] + cap(x0, f(x0), df(x0), True)


def path(pts):
    return 'M' + ' L'.join(f'{x:.2f} {y:.2f}' for x, y in pts) + 'Z'


def main():
    sun = sun_polygon(); waves = [wave_polygon(w) for w in WAVES]
    svg = (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}">'
           f'<path class="m-sun" fill="var(--mark-sun, currentColor)" d="{path(sun)}"/>'
           + ''.join(f'<path class="m-sea" fill="var(--mark-sea, currentColor)" d="{path(p)}"/>' for p in waves) + '</svg>')
    (HERE / 'sunseto-mark.svg').write_text(svg)
    (HERE / 'mark.json').write_text(json.dumps({'w': W, 'h': H, 'sun': [[round(x, 3), round(y, 3)] for x, y in sun],
                                                'waves': [[[round(x, 3), round(y, 3)] for x, y in p] for p in waves]}, separators=(',', ':')))
    print('mark written:', len(sun), 'sun points,', [len(p) for p in waves], 'wave points')


if __name__ == '__main__':
    main()
