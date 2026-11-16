"""Render the five FibonAI client-acquisition social videos (16:9 and 9:16, 30 fps, with music).

Videos (see docs/brand/social-strategy/FibonAI-Discord-Telegram-Strategy.md):
    1  Free month offer       1 month free + free API
    2  How it works           the five-step flow
    3  Verified by 3 phones   answers compared, the match is returned
    4  Invoices               documents in, structured data out
    5  Catalog clean-up       blurry/duplicate photos, tags, background removal

Usage (from repository root):
    python docs/brand/social-videos/render_social.py --video 1 --ratio 16x9
    python docs/brand/social-videos/render_social.py --video all --ratio both --jobs 4
    python docs/brand/social-videos/render_social.py --video 3 --ratio 9x16 --preview 2 6 9

Requires: pip install pillow numpy opencv-python-headless fonttools imageio-ffmpeg
The soundtrack is synthesised in this script (no third-party audio).
"""

import argparse
import math
import os
import random
import subprocess
import sys
import tempfile
import wave
from concurrent.futures import ThreadPoolExecutor
from functools import lru_cache
from pathlib import Path

import cv2
import imageio_ffmpeg
import numpy as np
from fontTools.ttLib import TTFont
from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
FONTSOURCE = ROOT / "src" / "apps" / "marketing-site" / "node_modules" / "@fontsource"
MARK = ROOT / "docs" / "brand" / "fibonai-mark-light.png"
LOGO = ROOT / "docs" / "brand" / "fibonai-logo-light.png"

FPS = 30
W, H, PORTRAIT = 1920, 1080, False

CANVAS = (11, 12, 15)
PANEL = (16, 18, 22)
PANEL_2 = (21, 23, 27)
SLATE = (38, 47, 56)
GOLD = (205, 174, 111)
GOLD_DEEP = (192, 160, 100)
GOLD_SOFT = (241, 230, 207)
LINE = (236, 232, 223)
STEEL_1 = (166, 192, 203)
STEEL_2 = (127, 158, 173)
STEEL_3 = (77, 100, 114)
PAPER = (247, 245, 240)
MUTED = (179, 181, 189)
INK_2 = (91, 100, 112)
TEAL = (25, 199, 180)
HOLD = (226, 69, 107)

VIDEOS = {
    1: ("FibonAI-01-Free-Month", 13.0, 10.2),
    2: ("FibonAI-02-How-It-Works", 14.6, 12.0),
    3: ("FibonAI-03-Verified-By-3-Phones", 14.6, 12.0),
    4: ("FibonAI-04-Invoices", 14.2, 11.6),
    5: ("FibonAI-05-Catalog-Cleanup", 14.2, 11.6),
}


def setup(ratio):
    global W, H, PORTRAIT
    W, H = (1920, 1080) if ratio == "16x9" else (1080, 1920)
    PORTRAIT = H > W
    setup_background()


def pick(land, port):
    return port if PORTRAIT else land


# ---------- timing ----------

def prog(t, a, b):
    return min(1.0, max(0.0, (t - a) / (b - a)))


def ease_out(x):
    return 1 - (1 - x) ** 3


def ease_in_out(x):
    return 4 * x**3 if x < 0.5 else 1 - (-2 * x + 2) ** 3 / 2


def ease_back(x, s=1.6):
    x -= 1
    return 1 + (s + 1) * x**3 + s * x**2


def lerp(a, b, x):
    return a + (b - a) * x


def mix(c1, c2, x):
    return tuple(int(round(lerp(a, b, x))) for a, b in zip(c1, c2))


# ---------- fonts and sprites ----------

def _convert_font(family, weight):
    cache = Path(tempfile.gettempdir()) / "fibonai-fonts"
    cache.mkdir(exist_ok=True)
    target = cache / f"{family}-{weight}.ttf"
    if not target.exists():
        fnt = TTFont(FONTSOURCE / family / "files" / f"{family}-latin-{weight}-normal.woff")
        fnt.flavor = None
        partial = cache / f"{family}-{weight}.{os.getpid()}.tmp"
        fnt.save(partial)
        try:
            os.replace(partial, target)
        except OSError:
            partial.unlink(missing_ok=True)
    return str(target)


@lru_cache(maxsize=None)
def font(kind, size):
    family, weight = {
        "display": ("cal-sans", 400),
        "sans": ("geist-sans", 400),
        "medium": ("geist-sans", 500),
        "semibold": ("geist-sans", 600),
        "mono": ("geist-mono", 500),
    }[kind]
    return ImageFont.truetype(_convert_font(family, weight), size)


def rounded(size, radius, fill, outline=None, width=0, scale=2):
    w, h = size
    img = Image.new("RGBA", (w * scale, h * scale), (0, 0, 0, 0))
    ImageDraw.Draw(img).rounded_rectangle(
        (0, 0, w * scale - 1, h * scale - 1), radius * scale, fill=fill, outline=outline, width=width * scale
    )
    return img.resize((w, h), Image.LANCZOS)


def glow(sprite, radius, color, strength=1.0):
    pad = radius * 3
    alpha = sprite.getchannel("A")
    small = Image.new("L", ((sprite.width + pad * 2) // 4, (sprite.height + pad * 2) // 4), 0)
    small.paste(alpha.resize((max(1, sprite.width // 4), max(1, sprite.height // 4))), (pad // 4, pad // 4))
    small = small.filter(ImageFilter.GaussianBlur(radius / 4))
    big = small.resize((sprite.width + pad * 2, sprite.height + pad * 2), Image.BICUBIC)
    big = big.point(lambda v: min(255, int(v * strength)))
    out = Image.new("RGBA", big.size, color + (0,))
    out.putalpha(big)
    return out, pad


def text_sprite(text, fnt, fill, tracking=0, pad=10):
    box = fnt.getbbox(text)
    w = box[2] - box[0] + tracking * max(0, len(text) - 1)
    img = Image.new("RGBA", (int(w) + pad * 2, int(box[3]) + pad * 2), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    if tracking:
        x = pad - box[0]
        for ch in text:
            d.text((x, pad), ch, font=fnt, fill=fill)
            x += fnt.getlength(ch) + tracking
    else:
        d.text((pad - box[0], pad), text, font=fnt, fill=fill)
    return img


def para_sprite(text, fnt, fill, align="center", spacing=8, pad=8):
    probe = ImageDraw.Draw(Image.new("RGBA", (1, 1)))
    box = [int(math.ceil(v)) for v in probe.multiline_textbbox((0, 0), text, font=fnt, spacing=spacing, align=align)]
    img = Image.new("RGBA", (box[2] - box[0] + pad * 2, box[3] - box[1] + pad * 2), (0, 0, 0, 0))
    ImageDraw.Draw(img).multiline_text((pad - box[0], pad - box[1]), text, font=fnt, fill=fill, spacing=spacing, align=align)
    return img


def gradient_text(text, fnt, top, bottom, pad=10):
    mask = text_sprite(text, fnt, (255, 255, 255, 255), pad=pad).getchannel("A")
    arr = np.zeros((mask.height, mask.width, 4), np.uint8)
    for i, c in enumerate(top):
        arr[..., i] = np.linspace(c, bottom[i], mask.height)[:, None]
    arr[..., 3] = 255
    grad = Image.fromarray(arr, "RGBA")
    grad.putalpha(mask)
    return grad


def with_shadow(sprite, radius=18, strength=0.6):
    shadow, pad = glow(sprite, radius, (6, 8, 10), strength=strength)
    shadow.alpha_composite(sprite, (pad, pad - 3))
    return shadow


def star_sprite(size, color):
    s = size * 4
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    c = s / 2
    pts = []
    for i in range(8):
        ang = math.pi / 4 * i - math.pi / 2
        r = c * (1.0 if i % 2 == 0 else 0.22)
        pts.append((c + r * math.cos(ang), c + r * math.sin(ang)))
    ImageDraw.Draw(img).polygon(pts, fill=color + (255,))
    return img.resize((size, size), Image.LANCZOS)


def paste_center(frame, sprite, cx, cy, opacity=1.0, scale=1.0, rotate=0.0, blur=0.0):
    if opacity <= 0.004 or sprite is None:
        return
    spr = sprite
    if abs(scale - 1.0) > 0.002:
        spr = spr.resize((max(1, int(spr.width * scale)), max(1, int(spr.height * scale))), Image.BICUBIC)
    if abs(rotate) > 0.01:
        spr = spr.rotate(rotate, resample=Image.BICUBIC, expand=True)
    if blur > 0.3:
        padded = Image.new("RGBA", (spr.width + int(blur * 6), spr.height + int(blur * 6)), (0, 0, 0, 0))
        padded.alpha_composite(spr, (int(blur * 3), int(blur * 3)))
        spr = padded.filter(ImageFilter.GaussianBlur(blur))
    if opacity < 0.999:
        a = spr.getchannel("A").point(lambda v: int(v * opacity))
        spr = spr.copy()
        spr.putalpha(a)
    x, y = int(round(cx - spr.width / 2)), int(round(cy - spr.height / 2))
    left, top = max(0, -x), max(0, -y)
    right, bottom = min(spr.width, W - x), min(spr.height, H - y)
    if right <= left or bottom <= top:
        return
    if left or top or right < spr.width or bottom < spr.height:
        spr = spr.crop((left, top, right, bottom))
    frame.alpha_composite(spr, (x + left, y + top))


def supersample(size, draw_fn, scale=4):
    w, h = size
    img = Image.new("RGBA", (w * scale, h * scale), (0, 0, 0, 0))
    draw_fn(ImageDraw.Draw(img), scale)
    return img.resize((w, h), Image.LANCZOS)


# ---------- background ----------

BLOBS = [
    (0.12, 0.10, 0.36, STEEL_3, 0.45, 0.5, 0.4, 0.0),
    (0.90, 0.30, 0.26, (34, 52, 60), 0.55, 0.4, 0.6, 1.3),
    (0.55, 1.05, 0.48, GOLD_DEEP, 0.26, 0.3, 0.5, 2.1),
]
ACCENT = (0.5, 0.42, 0.30, (70, 60, 40), 0.75, 0.3, 0.3, 0.0)


def setup_background():
    global LOW_W, LOW_H, GX, GY, VIGNETTE, DOTS, GRAIN
    LOW_W, LOW_H = (135, 240) if PORTRAIT else (240, 135)
    yy, xx = np.mgrid[0:LOW_H, 0:LOW_W].astype(np.float32)
    s = max(LOW_W, LOW_H)
    GX, GY = xx / s, yy / s
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    nx, ny = (xx / W - 0.5) * 2, (yy / H - 0.5) * 2
    VIGNETTE = (1 - 0.38 * np.clip((nx**2 + ny**2) / 2, 0, 1) ** 1.3)[..., None]
    DOTS = np.zeros((H, W, 1), np.float32)
    for dy in (0, 1):
        for dx in (0, 1):
            DOTS[22 + dy :: 44, 22 + dx :: 44] = 9.0
    DOTS *= VIGNETTE**4
    GRAIN = [np.random.default_rng(i).integers(-4, 5, (H, W, 1), dtype=np.int16) for i in range(4)]


def background(t, accent=0.0):
    s = max(LOW_W, LOW_H)
    img = np.empty((LOW_H, LOW_W, 3), np.float32)
    img[:] = np.array(CANVAS, np.float32)
    blobs = BLOBS + ([ACCENT[:4] + (ACCENT[4] * accent,) + ACCENT[5:]] if accent > 0 else [])
    for cx, cy, r, color, amp, sx, sy, ph in blobs:
        x = (cx + 0.04 * math.sin(t * sx + ph)) * LOW_W / s
        y = (cy + 0.04 * math.cos(t * sy + ph)) * LOW_H / s
        w = amp * np.exp(-((GX - x) ** 2 + (GY - y) ** 2) / (r * r))[..., None]
        img = img * (1 - w) + np.array(color, np.float32) * w
    big = cv2.resize(np.clip(img, 0, 255).astype(np.uint8), (W, H), interpolation=cv2.INTER_CUBIC)
    return np.clip(big.astype(np.float32) * VIGNETTE + DOTS, 0, 255).astype(np.uint8)


# ---------- shared pieces ----------

def wordmark(size):
    f = font("semibold", size)
    parts = [("Fibon", LINE), ("A", LINE), ("I", GOLD)]
    width = int(sum(f.getlength(p) for p, _ in parts)) + 20
    box = f.getbbox("FibonAI")
    img = Image.new("RGBA", (width, box[3] + 20), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    x = 10
    for text, color in parts:
        d.text((x, 10), text, font=f, fill=color + (255,))
        if text == "A":
            aw = f.getlength("A")
            top, bottom = box[1] + 10, box[3] + 10
            band = Image.new("RGBA", img.size, (0, 0, 0, 0))
            ImageDraw.Draw(band).text((x, 10), "A", font=f, fill=GOLD + (255,))
            clip = Image.new("L", img.size, 0)
            ImageDraw.Draw(clip).rectangle((x, top + (bottom - top) * 0.58, x + aw, top + (bottom - top) * 0.74), fill=255)
            band.putalpha(ImageChops.multiply(band.getchannel("A"), clip))
            img.alpha_composite(band)
        x += f.getlength(text)
    return img


@lru_cache(maxsize=None)
def mark_sprite(height):
    img = Image.open(MARK).convert("RGBA")
    return img.resize((int(img.width * height / img.height), height), Image.LANCZOS)


@lru_cache(maxsize=None)
def bug_sprite():
    mark = mark_sprite(44)
    wm = wordmark(32)
    img = Image.new("RGBA", (mark.width + 12 + wm.width, max(mark.height, wm.height)), (0, 0, 0, 0))
    img.alpha_composite(mark, (0, (img.height - mark.height) // 2))
    img.alpha_composite(wm, (mark.width + 12, (img.height - wm.height) // 2 - 2))
    return img


def brand_bug(frame, opacity):
    spr = bug_sprite()
    paste_center(frame, spr, 60 + spr.width / 2, pick(66, 110) + spr.height / 2, opacity)


def _raw_line(text, style, size):
    if style == "gold":
        return gradient_text(text, font("display", size), (255, 248, 232), GOLD_DEEP)
    if style == "white":
        return text_sprite(text, font("display", size), (255, 255, 255, 255))
    if style == "caption":
        return text_sprite(text, font("semibold", size), (255, 255, 255, 255))
    if style == "muted":
        return text_sprite(text, font("sans", size), MUTED + (255,))
    if style == "eyebrow":
        return text_sprite(text, font("mono", size), GOLD + (255,), tracking=int(size * 0.28))
    raise ValueError(style)


@lru_cache(maxsize=None)
def line_sprite(text, style, size):
    while True:
        spr = _raw_line(text, style, size)
        if spr.width <= W * 0.88 or size < 18:
            break
        size = int(size * 0.94)
    return with_shadow(spr, 18, 0.6)


def headline(frame, t, lines, a, b, cy):
    """lines: (text, style, size). Lines rise in with a stagger at `a` and fade out at `b`."""
    heights = [size * 1.12 for _, _, size in lines]
    y = cy - sum(heights) / 2
    for i, ((text, style, size), lh) in enumerate(zip(lines, heights)):
        p = ease_out(prog(t, a + i * 0.14, a + i * 0.14 + 0.65))
        o = 1 - ease_in_out(prog(t, b, b + 0.4))
        if p * o > 0:
            paste_center(frame, line_sprite(text, style, size), W / 2, y + lh / 2 + (1 - p) * 46, p * o, blur=(1 - p) * 8 + (1 - o) * 5)
        y += lh


def captions(frame, t, items, cy, size=44):
    for a, b, text in items:
        p = ease_out(prog(t, a, a + 0.45))
        o = 1 - ease_in_out(prog(t, b - 0.35, b))
        if p * o > 0.01:
            paste_center(frame, line_sprite(text, "caption", size), W / 2, cy + (1 - p) * 22, p * o)


def eyebrow(frame, t, text, a, b, cy, size=26):
    p = ease_out(prog(t, a, a + 0.5))
    o = 1 - ease_in_out(prog(t, b, b + 0.4))
    if p * o > 0.01:
        paste_center(frame, line_sprite(text, "eyebrow", size), W / 2, cy + (1 - p) * 14, p * o)


rng = random.Random(7)
SPARKLES = [
    (rng.uniform(0.05, 0.95), rng.uniform(0.08, 0.92), rng.choice([16, 22, 30, 40]), rng.uniform(0, 6.28), rng.choice([GOLD_SOFT, (255, 255, 255), GOLD]))
    for _ in range(12)
]


@lru_cache(maxsize=None)
def star_glow(size, color):
    star = star_sprite(size, color)
    g, _ = glow(star, max(6, size // 3), color, strength=0.9)
    g.alpha_composite(star, ((g.width - size) // 2, (g.height - size) // 2))
    return g


def sparkles(frame, t, strength):
    if strength <= 0.01:
        return
    for x, y, size, ph, color in SPARKLES:
        tw = 0.5 + 0.5 * math.sin(t * 2.6 + ph)
        paste_center(frame, star_glow(size, color), x * W, y * H + math.sin(t + ph) * 8, strength * (0.3 + 0.6 * tw), scale=0.7 + 0.4 * tw, rotate=t * 20 + ph * 10)


@lru_cache(maxsize=None)
def check_sprite(d, color=TEAL):
    def draw(dr, s):
        dr.ellipse((0, 0, d * s - 1, d * s - 1), fill=color + (255,))
        dr.line([(d * s * 0.27, d * s * 0.52), (d * s * 0.44, d * s * 0.68), (d * s * 0.74, d * s * 0.34)], fill=(255, 255, 255, 255), width=int(d * s * 0.11), joint="curve")
    return supersample((d, d), draw)


@lru_cache(maxsize=None)
def cross_sprite(d):
    def draw(dr, s):
        dr.ellipse((0, 0, d * s - 1, d * s - 1), fill=HOLD + (255,))
        a, b = d * s * 0.32, d * s * 0.68
        dr.line([(a, a), (b, b)], fill=(255, 255, 255, 255), width=int(d * s * 0.1))
        dr.line([(a, b), (b, a)], fill=(255, 255, 255, 255), width=int(d * s * 0.1))
    return supersample((d, d), draw)


def pill(text, kind="sans", size=28, fill=PANEL_2, text_fill=GOLD_SOFT, outline=None, padx=34, height=None, icon=None):
    f = font(kind, size)
    h = height or int(size * 2.1)
    iw = icon.width + 14 if icon else 0
    w = int(f.getlength(text)) + padx * 2 + iw
    img = rounded((w, h), h // 2, fill + (255,), outline=(outline + (255,)) if outline else None, width=2 if outline else 0)
    if icon:
        img.alpha_composite(icon, (padx, (h - icon.height) // 2))
    ImageDraw.Draw(img).text((padx + iw, h // 2), text, font=f, fill=text_fill + (255,), anchor="lm")
    return img


# ---------- end card ----------

@lru_cache(maxsize=None)
def logo_sprite():
    img = Image.open(LOGO).convert("RGBA")
    h = pick(300, 340)
    return img.resize((int(img.width * h / img.height), h), Image.LANCZOS)


@lru_cache(maxsize=None)
def logo_glow():
    return glow(logo_sprite(), 36, GOLD, 0.42)[0]


@lru_cache(maxsize=None)
def offer_pill():
    return pill("1 MONTH FREE  +  FREE API", kind="semibold", size=pick(32, 34), fill=GOLD, text_fill=CANVAS, padx=44)


@lru_cache(maxsize=None)
def offer_pill_glow():
    return glow(offer_pill(), 18, GOLD, 0.6)[0]


def end_card(frame, t, t0):
    if t < t0:
        return
    p = prog(t, t0, t0 + 0.8)
    s = lerp(0.55, 1.0, ease_back(p)) if p < 1 else 1.0
    cy = H * pick(0.38, 0.41)
    paste_center(frame, logo_glow(), W / 2, cy, min(1, p * 2) * 0.7, scale=s)
    paste_center(frame, logo_sprite(), W / 2, cy, min(1, p * 2), scale=s)
    py = cy + logo_sprite().height / 2 + pick(95, 120)
    pp = ease_out(prog(t, t0 + 0.55, t0 + 1.0))
    paste_center(frame, offer_pill_glow(), W / 2, py + (1 - pp) * 20, pp * (0.55 + 0.25 * math.sin(t * 3)))
    paste_center(frame, offer_pill(), W / 2, py + (1 - pp) * 20, pp)
    cp = ease_out(prog(t, t0 + 0.85, t0 + 1.3))
    paste_center(frame, line_sprite("Claim your free month — link in the post", "muted", 30), W / 2, py + pick(88, 100) + (1 - cp) * 16, cp)
    sparkles(frame, t, 0.75 * p)


# ---------- video 1: free month ----------

@lru_cache(maxsize=None)
def offer_ring(r):
    def draw(dr, s):
        R = r * s
        dr.ellipse((4 * s, 4 * s, 2 * R - 4 * s, 2 * R - 4 * s), outline=STEEL_3 + (110,), width=2 * s)
        dr.arc((10 * s, 10 * s, 2 * R - 10 * s, 2 * R - 10 * s), -90, 40, fill=GOLD + (255,), width=6 * s)
        dr.arc((10 * s, 10 * s, 2 * R - 10 * s, 2 * R - 10 * s), 150, 190, fill=GOLD_SOFT + (220,), width=3 * s)
        dr.arc((40 * s, 40 * s, 2 * R - 40 * s, 2 * R - 40 * s), 60, 140, fill=STEEL_1 + (160,), width=2 * s)
    return supersample((2 * r, 2 * r), draw, scale=2)


@lru_cache(maxsize=None)
def key_icon(size):
    def draw(dr, s):
        k = size * s
        dr.ellipse((0.04 * k, 0.28 * k, 0.48 * k, 0.72 * k), outline=GOLD + (255,), width=int(0.1 * k))
        dr.line([(0.46 * k, 0.5 * k), (0.96 * k, 0.5 * k)], fill=GOLD + (255,), width=int(0.1 * k))
        dr.line([(0.8 * k, 0.5 * k), (0.8 * k, 0.72 * k)], fill=GOLD + (255,), width=int(0.1 * k))
        dr.line([(0.66 * k, 0.5 * k), (0.66 * k, 0.66 * k)], fill=GOLD + (255,), width=int(0.1 * k))
    return supersample((size, size), draw)


@lru_cache(maxsize=None)
def api_pill():
    return pill("+ free API access", kind="semibold", size=pick(40, 40), fill=PANEL_2, text_fill=GOLD_SOFT, outline=GOLD, padx=40, icon=key_icon(40))


INCLUDED = ["Free API key", "Webhooks to your system", "Cost estimate before every task", "Setup help on Discord"]


@lru_cache(maxsize=None)
def included_card():
    w, h = pick(980, 940), 600
    card = rounded((w, h), 36, PANEL + (238,), outline=STEEL_3 + (150,), width=2)
    title = text_sprite("INCLUDED IN YOUR FREE MONTH", font("mono", 24), GOLD + (255,), tracking=6)
    card.alpha_composite(title, (56, 52))
    return card


@lru_cache(maxsize=None)
def included_row(text):
    f = font("semibold", pick(42, 40))
    chk = check_sprite(46)
    img = Image.new("RGBA", (int(f.getlength(text)) + 90, 64), (0, 0, 0, 0))
    img.alpha_composite(chk, (0, 9))
    ImageDraw.Draw(img).text((70, 32), text, font=f, fill=(255, 255, 255, 255), anchor="lm")
    return img


def video1(frame, t):
    headline(frame, t, [("AI results.", "white", pick(150, 124)), ("No servers.", "gold", pick(150, 124))], 0.3, 2.6, H * 0.5)

    if 2.9 < t < 7.9:
        p = prog(t, 3.0, 3.7)
        out = ease_in_out(prog(t, 7.2, 7.7))
        s = lerp(0.5, 1.0, ease_back(p)) * (1 + 0.35 * out)
        o = min(1.0, p * 1.6) * (1 - out)
        cy = H * pick(0.47, 0.46)
        paste_center(frame, offer_ring(pick(400, 460)), W / 2, cy, o * 0.9, scale=s, rotate=-t * 24)
        paste_center(frame, line_sprite("1 MONTH", "white", pick(120, 120)), W / 2, cy - pick(170, 190) * s, o, scale=s)
        paste_center(frame, line_sprite("FREE", "gold", pick(300, 300)), W / 2, cy + 10 * s, o, scale=s, blur=(1 - p) * 6)
        ap = ease_out(prog(t, 4.2, 4.75))
        paste_center(frame, api_pill(), W / 2, cy + pick(225, 250) + (1 - ap) * 30, ap * (1 - out))
        sparkles(frame, t, o)

    if 7.6 < t < 10.4:
        out = ease_in_out(prog(t, 9.8, 10.2))
        cp = ease_out(prog(t, 7.7, 8.25))
        card = included_card()
        cy = H * 0.5 + (1 - cp) * 40
        paste_center(frame, card, W / 2, cy, cp * (1 - out), scale=lerp(0.94, 1.0, cp))
        top = cy - card.height / 2
        for i, text in enumerate(INCLUDED):
            rp = ease_out(prog(t, 8.0 + i * 0.25, 8.45 + i * 0.25))
            row = included_row(text)
            paste_center(frame, row, W / 2 - card.width / 2 + 56 + row.width / 2 + (1 - rp) * 30, top + 170 + i * 105, rp * (1 - out))


# ---------- video 2: how it works ----------

STEPS = [
    ("Free tasks", "Start with free\nmonthly tasks", "calendar"),
    ("Quick estimate", "Difficulty and time,\nchecked first", "gauge"),
    ("Sent to phones", "Queued to\navailable devices", "queue"),
    ("Processed", "Real phones\nrun the task", "phone"),
    ("Verified", "The checked answer\ncomes back to you", "shield"),
]


@lru_cache(maxsize=None)
def step_icon(kind, size, color):
    c = color + (255,)

    def draw(d, s):
        k = size * s
        lw = int(0.075 * k)
        if kind == "calendar":
            d.rounded_rectangle((0.12 * k, 0.2 * k, 0.88 * k, 0.88 * k), 0.1 * k, outline=c, width=lw)
            d.line([(0.12 * k, 0.4 * k), (0.88 * k, 0.4 * k)], fill=c, width=lw)
            d.line([(0.34 * k, 0.1 * k), (0.34 * k, 0.28 * k)], fill=c, width=lw)
            d.line([(0.66 * k, 0.1 * k), (0.66 * k, 0.28 * k)], fill=c, width=lw)
            d.line([(0.33 * k, 0.63 * k), (0.46 * k, 0.75 * k), (0.68 * k, 0.53 * k)], fill=c, width=lw, joint="curve")
        elif kind == "gauge":
            d.arc((0.08 * k, 0.18 * k, 0.92 * k, 1.02 * k), 180, 360, fill=c, width=lw)
            d.line([(0.5 * k, 0.6 * k), (0.72 * k, 0.34 * k)], fill=c, width=lw)
            d.ellipse((0.43 * k, 0.53 * k, 0.57 * k, 0.67 * k), fill=c)
            d.line([(0.2 * k, 0.82 * k), (0.8 * k, 0.82 * k)], fill=c, width=lw)
        elif kind == "queue":
            for i in range(3):
                x = 0.08 * k + i * 0.22 * k
                d.rounded_rectangle((x, 0.36 * k, x + 0.16 * k, 0.64 * k), 0.04 * k, outline=c, width=lw)
            d.line([(0.74 * k, 0.5 * k), (0.94 * k, 0.5 * k)], fill=c, width=lw)
            d.line([(0.84 * k, 0.38 * k), (0.95 * k, 0.5 * k), (0.84 * k, 0.62 * k)], fill=c, width=lw, joint="curve")
        elif kind == "phone":
            d.rounded_rectangle((0.28 * k, 0.06 * k, 0.72 * k, 0.94 * k), 0.1 * k, outline=c, width=lw)
            d.arc((0.38 * k, 0.32 * k, 0.62 * k, 0.56 * k), -90, 200, fill=c, width=lw)
            d.line([(0.42 * k, 0.78 * k), (0.58 * k, 0.78 * k)], fill=c, width=lw)
        elif kind == "shield":
            d.polygon([(0.5 * k, 0.06 * k), (0.86 * k, 0.2 * k), (0.82 * k, 0.6 * k), (0.5 * k, 0.94 * k), (0.18 * k, 0.6 * k), (0.14 * k, 0.2 * k)], outline=c, width=lw)
            d.line([(0.32 * k, 0.5 * k), (0.46 * k, 0.64 * k), (0.7 * k, 0.38 * k)], fill=c, width=lw, joint="curve")
    return supersample((size, size), draw)


@lru_cache(maxsize=None)
def step_node(i, active):
    r = pick(78, 68)
    pad = 20
    d = 2 * r + pad * 2
    img = Image.new("RGBA", (d, d), (0, 0, 0, 0))

    def ring(dr, s):
        dr.ellipse((pad * s, pad * s, (d - pad) * s, (d - pad) * s), fill=(PANEL_2 if active else PANEL) + (255,), outline=(GOLD if active else STEEL_3) + (255,), width=4 * s)
    img.alpha_composite(supersample((d, d), ring))
    if active:
        g, gp = glow(img, 16, GOLD, 0.55)
        g.alpha_composite(img, (gp, gp))
        img = g
    icon = step_icon(STEPS[i][2], int(r * 0.95), GOLD if active else STEEL_2)
    img.alpha_composite(icon, ((img.width - icon.width) // 2, (img.height - icon.height) // 2))
    br = 22
    badge = supersample((br * 2, br * 2), lambda dr, s: dr.ellipse((0, 0, br * 2 * s - 1, br * 2 * s - 1), fill=(GOLD if active else SLATE) + (255,)))
    ImageDraw.Draw(badge).text((br, br), str(i + 1), font=font("semibold", 24), fill=(CANVAS if active else MUTED) + (255,), anchor="mm")
    off = int(r * 0.72)
    img.alpha_composite(badge, (img.width // 2 + off - br, img.height // 2 - off - br))
    return img


def step_positions():
    if PORTRAIT:
        return [(W * 0.2, H * (0.25 + 0.135 * i)) for i in range(5)]
    return [(W * (0.14 + 0.18 * i), H * 0.46) for i in range(5)]


@lru_cache(maxsize=None)
def step_label(i):
    title, desc, _ = STEPS[i]
    if PORTRAIT:
        t_spr = text_sprite(title, font("semibold", 44), (255, 255, 255, 255))
        d_spr = text_sprite(desc.replace("\n", " "), font("sans", 30), MUTED + (255,))
        img = Image.new("RGBA", (max(t_spr.width, d_spr.width), t_spr.height + d_spr.height), (0, 0, 0, 0))
        img.alpha_composite(t_spr, (0, 0))
        img.alpha_composite(d_spr, (0, t_spr.height - 4))
        return img
    t_spr = text_sprite(title, font("semibold", 36), (255, 255, 255, 255))
    d_spr = para_sprite(desc, font("sans", 26), MUTED + (255,), spacing=6)
    img = Image.new("RGBA", (max(t_spr.width, d_spr.width), t_spr.height + d_spr.height + 6), (0, 0, 0, 0))
    img.alpha_composite(t_spr, ((img.width - t_spr.width) // 2, 0))
    img.alpha_composite(d_spr, ((img.width - d_spr.width) // 2, t_spr.height + 6))
    return img


@lru_cache(maxsize=None)
def pulse_dot():
    dot = supersample((22, 22), lambda d, s: d.ellipse((0, 0, 22 * s - 1, 22 * s - 1), fill=GOLD_SOFT + (255,)))
    g, p = glow(dot, 14, GOLD, 1.0)
    g.alpha_composite(dot, (p, p))
    return g


def video2(frame, t):
    headline(frame, t, [("How FibonAI works", "white", pick(130, 104)), ("in 5 steps.", "gold", pick(130, 104))], 0.3, 2.1, H * 0.5)
    if not 2.2 < t < 12.1:
        return
    out = ease_in_out(prog(t, 11.6, 12.0))
    o = 1 - out
    eyebrow(frame, t, "HOW IT WORKS", 2.3, 11.6, H * pick(0.15, 0.13))
    pos = step_positions()
    starts = [2.6 + 1.75 * i for i in range(5)]
    r = pick(78, 68)

    lines = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ld = ImageDraw.Draw(lines)
    heads = []
    for i in range(4):
        (x1, y1), (x2, y2) = pos[i], pos[i + 1]
        if PORTRAIT:
            a, b = (x1, y1 + r + 8), (x2, y2 - r - 8)
        else:
            a, b = (x1 + r + 8, y1), (x2 - r - 8, y2)
        ld.line([a, b], fill=STEEL_3 + (int(150 * o),), width=4)
        f = ease_in_out(prog(t, starts[i] + 0.7, starts[i + 1]))
        if f > 0:
            hx, hy = lerp(a[0], b[0], f), lerp(a[1], b[1], f)
            ld.line([a, (hx, hy)], fill=GOLD + (int(255 * o),), width=4)
            if f < 1:
                heads.append((hx, hy))
    frame.alpha_composite(lines)
    for hx, hy in heads:
        paste_center(frame, pulse_dot(), hx, hy, o)

    for i, (x, y) in enumerate(pos):
        a = ease_out(prog(t, starts[i], starts[i] + 0.5))
        appear = ease_out(prog(t, 2.3 + i * 0.08, 2.8 + i * 0.08))
        pop = 1 + 0.12 * math.sin(math.pi * a)
        paste_center(frame, step_node(i, False), x, y, appear * (1 - a) * o, scale=pop)
        paste_center(frame, step_node(i, True), x, y, a * o, scale=pop)
        lbl = step_label(i)
        lp = ease_out(prog(t, starts[i] + 0.2, starts[i] + 0.7))
        if PORTRAIT:
            paste_center(frame, lbl, x + r + 44 + lbl.width / 2 + (1 - lp) * 24, y, lp * o)
        else:
            paste_center(frame, lbl, x, y + r + 40 + lbl.height / 2 + (1 - lp) * 20, lp * o)

    captions(frame, t, [(10.9, 11.6, "Send a task. Get a verified result.")], H * pick(0.9, 0.9))


# ---------- video 3: verified by 3 phones ----------

ANSWERS = ["total: 1,240.00", "total: 1,240.00", "total: 1,204.00"]


@lru_cache(maxsize=None)
def task_card(verified):
    w, h = 580, 128
    card = rounded((w, h), 28, PANEL_2 + (245,), outline=(TEAL if verified else STEEL_3) + (255,), width=3 if verified else 2)
    d = ImageDraw.Draw(card)
    if verified:
        card.alpha_composite(check_sprite(64), (30, 32))
        d.text((118, 42), "Verified result", font=font("sans", 24), fill=TEAL + (255,), anchor="lm")
        d.text((118, 84), ANSWERS[0], font=font("mono", 30), fill=GOLD_SOFT + (255,), anchor="lm")
    else:
        d.rounded_rectangle((30, 26, 92, 102), 10, fill=HOLD + (255,))
        d.text((61, 64), "PDF", font=font("semibold", 20), fill=(255, 255, 255, 255), anchor="mm")
        d.text((118, 42), "Your task", font=font("sans", 24), fill=MUTED + (255,), anchor="lm")
        d.text((118, 84), "invoice-2291.pdf", font=font("mono", 30), fill=(255, 255, 255, 255), anchor="lm")
    return card


@lru_cache(maxsize=None)
def phone_body(pw, ph):
    def draw(d, s):
        d.rounded_rectangle((0, 0, pw * s - 1, ph * s - 1), int(pw * 0.17) * s, fill=(28, 31, 36, 255), outline=STEEL_3 + (255,), width=3 * s)
        d.rounded_rectangle((10 * s, 10 * s, (pw - 10) * s, (ph - 10) * s), int(pw * 0.14) * s, fill=PANEL + (255,))
        d.rounded_rectangle(((pw / 2 - 30) * s, 22 * s, (pw / 2 + 30) * s, 38 * s), 8 * s, fill=(6, 6, 8, 255))
    img = supersample((pw, ph), draw, scale=2)
    m = mark_sprite(30)
    img.alpha_composite(m, ((pw - m.width) // 2, 60))
    return img


def ring_sprite(d, frac, color):
    def draw(dr, s):
        dr.ellipse((6 * s, 6 * s, (d - 6) * s, (d - 6) * s), outline=SLATE + (255,), width=8 * s)
        if frac > 0:
            dr.arc((6 * s, 6 * s, (d - 6) * s, (d - 6) * s), -90, -90 + 360 * frac, fill=color + (255,), width=8 * s)
    return supersample((d, d), draw, scale=2)


@lru_cache(maxsize=None)
def answer_chip(text, state):
    outline = {"neutral": STEEL_3, "match": TEAL, "miss": HOLD}[state]
    w, h = pick(300, 300), 64
    chip = rounded((w, h), 18, PANEL_2 + (250,), outline=outline + (255,), width=3 if state != "neutral" else 2)
    ImageDraw.Draw(chip).text((24, h // 2), text, font=font("mono", 24), fill=(GOLD_SOFT if state != "miss" else MUTED) + (255,), anchor="lm")
    if state == "match":
        chip.alpha_composite(check_sprite(34), (w - 50, 15))
    elif state == "miss":
        chip.alpha_composite(cross_sprite(34), (w - 50, 15))
    return chip


def bezier(p0, p1, p2, x):
    return ((1 - x) ** 2 * p0[0] + 2 * (1 - x) * x * p1[0] + x * x * p2[0], (1 - x) ** 2 * p0[1] + 2 * (1 - x) * x * p1[1] + x * x * p2[1])


def video3(frame, t):
    headline(frame, t, [("Can you trust", "white", pick(140, 112)), ("the answer?", "gold", pick(140, 112))], 0.3, 2.2, H * 0.5)
    if not 2.3 < t < 12.1:
        return
    out = ease_in_out(prog(t, 11.6, 12.0))
    o = 1 - out
    card_y = H * pick(0.2, 0.25)
    pw, ph = pick(210, 200), pick(390, 380)
    phone_y = H * pick(0.53, 0.5)
    xs = [W * x for x in pick((0.3, 0.5, 0.7), (0.2, 0.5, 0.8))]
    chip_y = phone_y + ph / 2 + 56

    cp = ease_out(prog(t, 2.4, 2.9))
    morph = ease_in_out(prog(t, 8.9, 9.3))
    paste_center(frame, task_card(False), W / 2, card_y + (1 - cp) * 24, cp * (1 - morph) * o)
    if morph > 0:
        paste_center(frame, glow(task_card(True), 18, TEAL, 0.5)[0], W / 2, card_y, morph * o * 0.8)
        paste_center(frame, task_card(True), W / 2, card_y, morph * o, scale=1 + 0.06 * math.sin(math.pi * morph))

    trail_p = prog(t, 3.0, 3.9)
    if 0 < trail_p < 1:
        layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        d = ImageDraw.Draw(layer)
        start = (W / 2, card_y + 64)
        heads = []
        for x in xs:
            end = (x, phone_y - ph / 2 - 6)
            ctrl = ((W / 2 + x) / 2, (card_y + phone_y) / 2 - 40)
            q = ease_in_out(trail_p)
            pts = [bezier(start, ctrl, end, max(0.0, q - k * 0.02)) for k in range(18)]
            for k in range(len(pts) - 1):
                d.line([pts[k], pts[k + 1]], fill=GOLD_SOFT + (int(220 * (1 - k / 18)),), width=4)
            heads.append(pts[0])
        frame.alpha_composite(layer.filter(ImageFilter.GaussianBlur(1.0)))
        for hx, hy in heads:
            paste_center(frame, pulse_dot(), hx, hy)

    body = phone_body(pw, ph)
    speeds = [(3.8, 5.5), (3.85, 5.75), (3.9, 5.35)]
    for i, x in enumerate(xs):
        ap = ease_out(prog(t, 2.7 + i * 0.12, 3.25 + i * 0.12))
        if ap <= 0:
            continue
        y = phone_y + (1 - ap) * 40
        paste_center(frame, body, x, y, ap * o)
        a, b = speeds[i]
        f = prog(t, a, b)
        done = f >= 1
        if t > a - 0.2:
            color = GOLD if not done else (TEAL if i < 2 or t < 7.0 else HOLD)
            paste_center(frame, ring_sprite(int(pw * 0.56), 1.0 if done else f, color), x, y - 10, ap * o)
            if done:
                lbl = line_sprite("Done", "muted", 24) if t < 6.8 else (line_sprite("Match", "muted", 24) if i < 2 else line_sprite("Mismatch", "muted", 24))
                paste_center(frame, lbl, x, y + ph * 0.3, ap * o)

        chp = ease_out(prog(t, 5.8 + i * 0.18, 6.25 + i * 0.18))
        if chp > 0:
            state = "neutral" if t < 6.9 else ("match" if i < 2 else "miss")
            fade = 1 - 0.6 * prog(t, 7.4, 8.0) if i == 2 else 1.0
            paste_center(frame, answer_chip(ANSWERS[i], state), x, chip_y + (1 - chp) * 20, chp * o * fade)

    link = ease_out(prog(t, 6.95, 7.4))
    if link > 0 and o > 0:
        layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        x0, x1 = xs[0] + 150, xs[1] - 150
        ImageDraw.Draw(layer).line([(x0, chip_y), (lerp(x0, x1, link), chip_y)], fill=TEAL + (int(230 * o),), width=4)
        frame.alpha_composite(layer)

    fly = prog(t, 8.0, 9.0)
    if 0 < fly < 1:
        q = ease_in_out(fly)
        sx, sy = (xs[0] + xs[1]) / 2, chip_y
        px, py = bezier((sx, sy), (sx + pick(260, 0), (sy + card_y) / 2), (W / 2, card_y), q)
        paste_center(frame, answer_chip(ANSWERS[0], "match"), px, py, o, scale=lerp(1.0, 0.8, q))

    captions(
        frame,
        t,
        [
            (2.6, 5.7, "Every task goes to 3 phones."),
            (5.8, 7.95, "Their answers are compared."),
            (8.0, 10.0, "Only the match comes back to you."),
            (10.0, 11.6, "Phones that cheat are warned, then removed."),
        ],
        H * pick(0.92, 0.84),
    )


# ---------- video 4: invoices ----------

FIELDS = [("supplier", "Northwind Ltd"), ("invoice_no", "INV-2291"), ("date", "2026-10-14"), ("total", "1,240.00")]


@lru_cache(maxsize=None)
def invoice_paper():
    pw, ph = pick(500, 470), pick(660, 620)
    k = pw / 500
    img = Image.new("RGBA", (pw, ph), (0, 0, 0, 0))
    img.alpha_composite(rounded((pw, ph), int(18 * k), PAPER + (255,)))
    d = ImageDraw.Draw(img)
    boxes = []

    def text(xy, value, f, fill, anchor="la"):
        d.text(xy, value, font=f, fill=fill + (255,), anchor=anchor)
        boxes.append(d.textbbox(xy, value, font=f, anchor=anchor))

    d.text((40 * k, 40 * k), "INVOICE", font=font("display", int(44 * k)), fill=SLATE + (255,))
    text((40 * k, 112 * k), FIELDS[0][1], font("semibold", int(26 * k)), SLATE)
    for i, wdt in enumerate((200, 160)):
        d.rounded_rectangle((40 * k, (156 + i * 24) * k, (40 + wdt) * k, (168 + i * 24) * k), 4, fill=(214, 210, 202, 255))
    text((pw - 40 * k, 52 * k), "No. " + FIELDS[1][1], font("mono", int(22 * k)), SLATE, "ra")
    text((pw - 40 * k, 86 * k), FIELDS[2][1], font("mono", int(22 * k)), INK_2, "ra")
    boxes[1] = (boxes[1][0] + font("mono", int(22 * k)).getlength("No. "), *boxes[1][1:])
    d.line((40 * k, 236 * k, pw - 40 * k, 236 * k), fill=(200, 196, 188, 255), width=2)
    for i in range(6):
        y = (264 + i * 36) * k
        d.rounded_rectangle((40 * k, y, (40 + [220, 180, 240, 160, 200, 140][i]) * k, y + 12 * k), 4, fill=(222, 218, 210, 255))
        d.rounded_rectangle((pw - 130 * k, y, pw - 40 * k, y + 12 * k), 4, fill=(222, 218, 210, 255))
    d.line((40 * k, 500 * k, pw - 40 * k, 500 * k), fill=(200, 196, 188, 255), width=2)
    d.text((40 * k, 538 * k), "Total", font=font("semibold", int(28 * k)), fill=SLATE + (255,))
    text((pw - 40 * k, 528 * k), FIELDS[3][1], font("display", int(42 * k)), SLATE, "ra")
    return img, tuple(boxes)


@lru_cache(maxsize=None)
def back_paper(shade):
    pw, ph = invoice_paper()[0].size
    return rounded((pw, ph), 18, mix(PAPER, (120, 118, 112), shade) + (255,))


def json_layout():
    w, h = pick(700, 900), 540
    cx, cy = (W * 0.7, H * 0.53) if not PORTRAIT else (W / 2, H * 0.7)
    return w, h, cx, cy


@lru_cache(maxsize=None)
def json_card():
    w, h, _, _ = json_layout()
    card = rounded((w, h), 30, PANEL + (245,), outline=STEEL_3 + (160,), width=2)
    for i, c in enumerate((HOLD, GOLD, TEAL)):
        ImageDraw.Draw(card).ellipse((30 + i * 26, 26, 44 + i * 26, 40), fill=c + (200,))
    ImageDraw.Draw(card).text((w - 30, 33), "result.json", font=font("mono", 20), fill=MUTED + (255,), anchor="rm")
    return card


@lru_cache(maxsize=None)
def value_chip(text):
    return pill(text, kind="mono", size=24, fill=PANEL_2, text_fill=GOLD_SOFT, outline=GOLD, padx=18, height=48)


@lru_cache(maxsize=None)
def scan_beam(width):
    beam = rounded((width, 6), 3, GOLD_SOFT + (255,))
    g, p = glow(beam, 14, GOLD, 1.0)
    g.alpha_composite(beam, (p, p))
    return g


def video4(frame, t):
    headline(frame, t, [("500 invoices.", "white", pick(150, 124)), ("Zero typing.", "gold", pick(150, 124))], 0.3, 2.3, H * 0.5)
    if not 2.4 < t < 11.7:
        return
    out = ease_in_out(prog(t, 11.2, 11.6))
    o = 1 - out
    eyebrow(frame, t, "INVOICES TO STRUCTURED DATA", 2.5, 11.2, H * pick(0.13, 0.12))

    paper, boxes = invoice_paper()
    pcx, pcy = (W * 0.3, H * 0.55) if not PORTRAIT else (W / 2, H * 0.36)
    ap = ease_out(prog(t, 2.6, 3.2))
    pcx_a = pcx - (1 - ap) * 80
    paste_center(frame, back_paper(0.35), pcx_a + 26, pcy + 10, ap * o * 0.8, rotate=4)
    paste_center(frame, back_paper(0.2), pcx_a - 14, pcy + 6, ap * o * 0.9, rotate=-3)

    page = paper.copy()
    d = ImageDraw.Draw(page)
    scan = prog(t, 3.4, 5.0)
    beam_y = lerp(-10, page.height + 10, ease_in_out(scan))
    if 0 < scan < 1 and beam_y > 0:
        band = Image.new("RGBA", page.size, (0, 0, 0, 0))
        ImageDraw.Draw(band).rectangle((0, max(0, beam_y - 120), page.width, beam_y), fill=GOLD + (34,))
        page.alpha_composite(band)
    for i, (x0, y0, x1, y1) in enumerate(boxes):
        if (scan > 0 and beam_y > y1) or scan >= 1:
            hp = 1 - prog(t, 5.1 + i * 0.3, 5.5 + i * 0.3) * 0.6
            d.rounded_rectangle((x0 - 8, y0 - 6, x1 + 8, y1 + 6), 8, outline=GOLD_DEEP + (int(255 * hp),), width=3)
    paste_center(frame, page, pcx_a, pcy, ap * o)
    if 0 < scan < 1:
        paste_center(frame, scan_beam(page.width + 40), pcx_a, pcy - page.height / 2 + beam_y, o)

    w, h, jx, jy = json_layout()
    jp = ease_out(prog(t, 4.6, 5.1))
    card = json_card().copy()
    cd = ImageDraw.Draw(card)
    mono = font("mono", pick(28, 30))
    lh = 52
    top = 86
    cd.text((40, top), "{", font=mono, fill=MUTED + (255,))
    targets = []
    for i, (key, value) in enumerate(FIELDS):
        y = top + lh * (i + 1)
        kx = 40 + mono.getlength("  ")
        k_text = f'"{key}": '
        cd.text((kx, y), k_text, font=mono, fill=STEEL_1 + (255,))
        vx = kx + mono.getlength(k_text)
        arrive = 5.1 + i * 0.3 + 0.6
        n = int(round((len(value) + 2) * prog(t, arrive, arrive + 0.35)))
        typed = f'"{value}"'[:n] + ("," if n >= len(value) + 2 and i < 3 else "")
        cd.text((vx, y), typed, font=mono, fill=GOLD_SOFT + (255,))
        targets.append((jx - w / 2 + vx + 80, jy - h / 2 + y + 18))
    cd.text((40, top + lh * 5), "}", font=mono, fill=MUTED + (255,))

    cnt = ease_in_out(prog(t, 7.0, 9.2))
    if t > 6.8:
        cp = prog(t, 6.8, 7.1)
        by = h - 56
        cd.rounded_rectangle((40, by, w - 40, by + 10), 5, fill=SLATE + (int(255 * cp),))
        if cnt > 0:
            cd.rounded_rectangle((40, by, 40 + (w - 80) * cnt, by + 10), 5, fill=GOLD + (int(255 * cp),))
        cd.text((40, by - 22), f"{int(lerp(1, 500, cnt))} / 500 invoices", font=font("mono", 22), fill=MUTED + (int(255 * cp),), anchor="ls")
    paste_center(frame, card, jx, jy + (1 - jp) * 30, jp * o)

    for i, (x0, y0, x1, y1) in enumerate(boxes):
        f = prog(t, 5.1 + i * 0.3, 5.7 + i * 0.3)
        if 0 < f < 1:
            q = ease_in_out(f)
            sx = pcx_a - paper.width / 2 + (x0 + x1) / 2
            sy = pcy - paper.height / 2 + (y0 + y1) / 2
            tx, ty = targets[i]
            ctrl = ((sx + tx) / 2, min(sy, ty) - 120)
            px, py = bezier((sx, sy), ctrl, (tx, ty), q)
            paste_center(frame, value_chip(FIELDS[i][1]), px, py, o * min(1, (1 - q) * 6), scale=lerp(1.0, 0.85, q))

    wp = ease_out(prog(t, 9.1, 9.6))
    webhook = pill("Sent to your system by webhook", kind="medium", size=26, fill=PANEL_2, text_fill=(255, 255, 255), outline=TEAL, padx=26, icon=check_sprite(30))
    paste_center(frame, webhook, jx, jy + h / 2 + 60 + (1 - wp) * 16, wp * o)

    if PORTRAIT:
        captions(frame, t, [(2.8, 11.2, "Upload images or PDFs.")], H * 0.93)
    else:
        captions(frame, t, [(2.8, 11.2, "Upload images or PDFs. Get structured data back.")], H * 0.93, size=40)


# ---------- video 5: catalog clean-up ----------

PRODUCTS = ["bottle", "mug", "sneaker", "bag", "headphones", "mug", "bottle", "bag", "headphones", "bottle", "sneaker", "mug"]
BLURRY = {4, 7}
DUPES = (2, 10)
MESSY = [(120, 104, 88), (96, 104, 96), (130, 118, 110), (88, 92, 104), (112, 96, 104), (104, 112, 100)]


def draw_product(kind, size):
    def draw(d, s):
        k = size * s

        def R(a, b, c, e):
            return (a * k, b * k, c * k, e * k)

        if kind == "bottle":
            d.rounded_rectangle(R(0.32, 0.34, 0.68, 0.96), 0.08 * k, fill=STEEL_1 + (255,))
            d.rectangle(R(0.43, 0.18, 0.57, 0.36), fill=STEEL_1 + (255,))
            d.rounded_rectangle(R(0.41, 0.06, 0.59, 0.2), 0.03 * k, fill=GOLD + (255,))
            d.rectangle(R(0.32, 0.56, 0.68, 0.76), fill=LINE + (255,))
        elif kind == "mug":
            d.ellipse(R(0.56, 0.4, 0.92, 0.78), outline=GOLD_SOFT + (255,), width=int(0.08 * k))
            d.rounded_rectangle(R(0.14, 0.3, 0.7, 0.92), 0.08 * k, fill=GOLD_SOFT + (255,))
            d.rectangle(R(0.14, 0.46, 0.7, 0.54), fill=GOLD + (255,))
        elif kind == "sneaker":
            pts = [(0.04, 0.84), (0.04, 0.58), (0.3, 0.54), (0.48, 0.34), (0.68, 0.36), (0.74, 0.54), (0.96, 0.66), (0.96, 0.84)]
            d.polygon([(x * k, y * k) for x, y in pts], fill=LINE + (255,))
            d.rectangle(R(0.04, 0.8, 0.96, 0.9), fill=SLATE + (255,))
            d.line([(0.34 * k, 0.72 * k), (0.62 * k, 0.48 * k)], fill=GOLD + (255,), width=int(0.06 * k))
        elif kind == "bag":
            d.arc(R(0.32, 0.12, 0.68, 0.6), 180, 360, fill=GOLD_DEEP + (255,), width=int(0.05 * k))
            d.polygon([(0.16 * k, 0.38 * k), (0.84 * k, 0.38 * k), (0.92 * k, 0.94 * k), (0.08 * k, 0.94 * k)], fill=GOLD + (255,))
        elif kind == "headphones":
            d.arc(R(0.16, 0.1, 0.84, 0.82), 180, 360, fill=STEEL_2 + (255,), width=int(0.07 * k))
            for x0 in (0.1, 0.7):
                d.rounded_rectangle(R(x0, 0.44, x0 + 0.2, 0.84), 0.06 * k, fill=SLATE + (255,), outline=GOLD + (255,), width=int(0.025 * k))
    return supersample((size, size), draw)


@lru_cache(maxsize=None)
def tile_sprites(i, size):
    kind = PRODUCTS[i]
    seed = DUPES[0] if i in DUPES else i
    r = np.random.default_rng(seed + 11)
    base = np.array(MESSY[seed % len(MESSY)], np.float32)
    arr = np.ones((size, size, 3), np.float32) * base
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32) / size
    for _ in range(4):
        cx, cy, rad = r.uniform(0, 1), r.uniform(0, 1), r.uniform(0.15, 0.4)
        col = np.array(MESSY[r.integers(0, len(MESSY))], np.float32) * r.uniform(0.7, 1.3)
        w = (0.7 * np.exp(-((xx - cx) ** 2 + (yy - cy) ** 2) / (rad * rad)))[..., None]
        arr = arr * (1 - w) + col * w
    arr[int(size * 0.68):] *= 0.78
    arr += r.normal(0, 7, arr.shape)
    messy = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGB").convert("RGBA")
    clean = Image.new("RGBA", (size, size), PAPER + (255,))
    prod = draw_product(kind, int(size * 0.6))
    for bg, shadow_a in ((messy, 120), (clean, 60)):
        sh = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        ImageDraw.Draw(sh).ellipse((size * 0.24, size * 0.74, size * 0.76, size * 0.84), fill=(20, 20, 24, shadow_a))
        bg.alpha_composite(sh.filter(ImageFilter.GaussianBlur(size * 0.03)))
        bg.alpha_composite(prod, ((size - prod.width) // 2, int(size * 0.2)))
    if i in BLURRY:
        messy = messy.filter(ImageFilter.GaussianBlur(size * 0.03))
    mask = rounded((size, size), 22, (255, 255, 255, 255)).getchannel("A")
    for img in (messy, clean):
        img.putalpha(mask)
    return messy, clean


def grid_layout():
    cols, rows, size, gap = (4, 3, 210, 26) if not PORTRAIT else (3, 4, 290, 24)
    gw, gh = cols * size + (cols - 1) * gap, rows * size + (rows - 1) * gap
    cx, cy = W / 2, H * pick(0.52, 0.5)
    pos = [(cx - gw / 2 + size / 2 + (i % cols) * (size + gap), cy - gh / 2 + size / 2 + (i // cols) * (size + gap)) for i in range(cols * rows)]
    return pos, size, gw, gh, cy


@lru_cache(maxsize=None)
def flag(text, kind):
    fill, fg = {"blurry": (HOLD, (255, 255, 255)), "dupe": (GOLD, CANVAS), "tag": ((14, 15, 18), GOLD_SOFT)}[kind]
    return pill(text, kind="semibold", size=pick(20, 24), fill=fill, text_fill=fg, padx=16, height=pick(38, 44))


def video5(frame, t):
    headline(frame, t, [("Clean up your", "white", pick(140, 112)), ("whole catalog.", "gold", pick(140, 112))], 0.3, 2.3, H * 0.5)
    if not 2.4 < t < 11.7:
        return
    out = ease_in_out(prog(t, 11.2, 11.6))
    o = 1 - out
    eyebrow(frame, t, "PRODUCT PHOTOS", 2.5, 11.2, H * pick(0.1, 0.12))
    pos, size, gw, gh, gcy = grid_layout()
    removable = [i for i in range(len(pos)) if i not in BLURRY and i not in DUPES[1:]]

    dupe_p = ease_out(prog(t, 5.2, 5.7))
    if dupe_p > 0 and o > 0:
        layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        (x0, y0), (x1, y1) = pos[DUPES[0]], pos[DUPES[1]]
        d = ImageDraw.Draw(layer)
        n = 22
        for k in range(n):
            if k % 2 == 0 and k / n < dupe_p:
                a, b = k / n, min(dupe_p, (k + 1) / n)
                d.line([(lerp(x0, x1, a), lerp(y0, y1, a)), (lerp(x0, x1, b), lerp(y0, y1, b))], fill=GOLD + (int(230 * o),), width=4)
        frame.alpha_composite(layer)

    for i, (x, y) in enumerate(pos):
        ap = ease_out(prog(t, 2.6 + i * 0.06, 3.1 + i * 0.06))
        if ap <= 0:
            continue
        messy, clean = tile_sprites(i, size)
        tile = messy
        if i in removable:
            k = removable.index(i)
            wipe = ease_in_out(prog(t, 7.3 + k * 0.16, 7.8 + k * 0.16))
            if wipe > 0:
                tile = messy.copy()
                cut = clean.copy()
                clip = Image.new("L", (size, size), 0)
                ImageDraw.Draw(clip).rectangle((0, 0, int(size * wipe), size), fill=255)
                cut.putalpha(ImageChops.multiply(cut.getchannel("A"), clip))
                tile.alpha_composite(cut)
                if wipe < 1:
                    ImageDraw.Draw(tile).line([(int(size * wipe), 0), (int(size * wipe), size)], fill=GOLD_SOFT + (255,), width=4)
        paste_center(frame, tile, x, y + (1 - ap) * 30, ap * o, scale=lerp(0.9, 1.0, ap))

    scan = prog(t, 3.8, 4.8)
    if 0 < scan < 1:
        paste_center(frame, scan_beam(gw + 60), W / 2, gcy - gh / 2 + gh * ease_in_out(scan), o)

    for i, (x, y) in enumerate(pos):
        lx, ty = x - size / 2 + 12, y - size / 2 + 12
        if i in BLURRY:
            fp = ease_back(prog(t, 4.9 + (i == 7) * 0.15, 5.3 + (i == 7) * 0.15))
            spr = flag("Blurry", "blurry")
        elif i in DUPES:
            fp = ease_back(prog(t, 5.2, 5.6))
            spr = flag("Duplicate", "dupe")
        else:
            fp = ease_out(prog(t, 6.0 + (i % 5) * 0.08, 6.4 + (i % 5) * 0.08))
            spr = flag(PRODUCTS[i], "tag")
            ty = y + size / 2 - 12 - spr.height
        if fp > 0:
            paste_center(frame, spr, lx + spr.width / 2, ty + spr.height / 2, min(1, fp) * o, scale=max(0.01, fp) if fp < 1 else 1.0)

    captions(
        frame,
        t,
        [(4.0, 6.0, "Catch blurry photos and duplicates."), (6.0, 7.2, "Tag every product."), (7.2, 11.2, "Remove messy backgrounds.")],
        H * pick(0.93, 0.88),
    )


SCENES = {1: video1, 2: video2, 3: video3, 4: video4, 5: video5}


def render(video, t):
    _, dur, end0 = VIDEOS[video]
    bg = background(t, accent=ease_in_out(prog(t, end0 - 0.4, end0 + 0.6)))
    frame = Image.fromarray(bg, "RGB").convert("RGBA")
    SCENES[video](frame, t)
    end_card(frame, t, end0)
    brand_bug(frame, ease_out(prog(t, 0.2, 0.7)) * (1 - prog(t, end0 - 0.4, end0)))
    rgb = np.asarray(frame.convert("RGB")).astype(np.int16)
    rgb += GRAIN[int(t * FPS) % 4]
    fade = min(prog(t, 0.0, 0.25), 1 - ease_in_out(prog(t, dur - 0.6, dur)))
    if fade < 1:
        rgb = (rgb * fade).astype(np.int16)
    return np.clip(rgb, 0, 255).astype(np.uint8)


# ---------- music ----------

SR = 44100


def midi(n):
    return 440.0 * 2 ** ((n - 69) / 12)


def make_music(dur, end0, path, seed):
    n = int(SR * dur)
    t = np.arange(n) / SR
    L, R = np.zeros(n), np.zeros(n)
    bar, beat = 2.5, 0.625
    progs = [[(57, 60, 64), (53, 57, 60), (52, 55, 60), (50, 55, 59)], [(53, 57, 60), (48, 52, 55), (50, 53, 57), (52, 55, 59)]]
    chords = progs[seed % 2]
    roots = [c[0] - 12 for c in chords]

    def tone(f, tt, harmonics=4, falloff=1.6):
        return sum(np.sin(2 * np.pi * k * f * tt) / k**falloff for k in range(1, harmonics + 1))

    bars = int(math.ceil(dur / bar)) + 1
    for b in range(bars):
        a0, a1 = max(0.0, b * bar - 0.35), min(dur, (b + 1) * bar + 0.35)
        if a0 >= a1:
            continue
        i0, i1 = int(a0 * SR), int(a1 * SR)
        tt = t[i0:i1]
        env = np.minimum(1, np.minimum((tt - a0) / 0.7, (a1 - tt) / 0.7)).clip(0, 1)
        env = 0.5 - 0.5 * np.cos(np.pi * env)
        chord = chords[b % 4]
        for note in chord:
            f = midi(note)
            L[i0:i1] += 0.045 * env * tone(f * 0.9985, tt)
            R[i0:i1] += 0.045 * env * tone(f * 1.0015, tt)
        if b * bar >= 2.4 and b * bar < end0:
            rt = tt - b * bar
            benv = np.where(rt >= 0, (1 - np.exp(-rt / 0.02)) * np.exp(-rt * 0.7), 0) * (tt < (b + 1) * bar)
            bass = 0.15 * benv * (np.sin(2 * np.pi * midi(roots[b % 4]) * tt) + 0.25 * np.sin(4 * np.pi * midi(roots[b % 4]) * tt))
            L[i0:i1] += bass
            R[i0:i1] += bass

    pattern = [0, 1, 2, 1, 0, 2, 1, 2] if seed % 2 else [0, 2, 1, 2, 0, 1, 2, 1]
    step = beat / 2
    k = 0
    st = 1.0
    while st < dur - 0.4:
        chord = chords[int(st // bar) % 4]
        note = chord[pattern[k % 8]] + 12 + (12 if k % 16 >= 12 else 0)
        i0 = int(st * SR)
        i1 = min(n, i0 + int(0.7 * SR))
        tt = t[i0:i1] - st
        env = np.exp(-tt * 7) * (1 - np.exp(-tt * 300))
        level = 0.07 * (0.6 if st > end0 else 1.0)
        sig = level * env * (np.sin(2 * np.pi * midi(note) * tt) + 0.25 * np.sin(4 * np.pi * midi(note) * tt))
        pan = 0.3 if k % 2 else -0.3
        L[i0:i1] += sig * (1 - pan)
        R[i0:i1] += sig * (1 + pan)
        st += step
        k += 1

    noise = np.random.default_rng(seed).standard_normal(n)
    hp = noise - np.roll(noise, 1)
    bt = 2.5
    j = 0
    while bt < end0 - 0.05:
        i0 = int(bt * SR)
        if j % 2 == 0:
            i1 = min(n, i0 + int(0.4 * SR))
            tt = t[i0:i1] - bt
            phase = 2 * np.pi * np.cumsum(45 + 85 * np.exp(-tt * 30)) / SR
            kick = 0.32 * np.exp(-tt * 14) * np.sin(phase)
            L[i0:i1] += kick
            R[i0:i1] += kick
        h0 = int((bt + beat / 2) * SR)
        h1 = min(n, h0 + int(0.08 * SR))
        tt = t[h0:h1] - (bt + beat / 2)
        hat = 0.035 * np.exp(-tt * 70) * hp[h0:h1]
        L[h0:h1] += hat
        R[h0:h1] += hat * 0.8
        bt += beat
        j += 1

    r0, r1 = int((end0 - 1.3) * SR), int(end0 * SR)
    ramp = np.linspace(0, 1, r1 - r0) ** 2
    riser = 0.07 * ramp * hp[r0:r1]
    L[r0:r1] += riser
    R[r0:r1] += riser
    i0 = int(end0 * SR)
    tt = t[i0:] - end0
    boom = 0.34 * np.exp(-tt * 2.6) * (np.sin(2 * np.pi * 55 * tt) + 0.3 * np.sin(2 * np.pi * 110 * tt))
    bell = sum(0.035 * np.exp(-tt * 1.4) * np.sin(2 * np.pi * midi(note + 24) * tt) for note in chords[0])
    L[i0:] += boom + bell
    R[i0:] += boom + bell

    dry_l, dry_r = L.copy(), R.copy()
    for d, g in ((0.19, 0.26), (0.31, 0.18), (0.47, 0.12)):
        ds = int(d * SR)
        L[ds:] += g * dry_r[:-ds]
        R[ds:] += g * dry_l[:-ds]
    env = np.minimum(1, t / 0.15) * np.minimum(1, (dur - t) / 1.0).clip(0, 1)
    out = np.stack([L * env, R * env], axis=1)
    out *= 0.89 / max(1e-6, np.abs(out).max())
    pcm = (out * 32767).astype(np.int16)
    with wave.open(str(path), "wb") as wf:
        wf.setnchannels(2)
        wf.setsampwidth(2)
        wf.setframerate(SR)
        wf.writeframes(pcm.tobytes())


# ---------- main ----------

def render_one(video, ratio, preview=None):
    setup(ratio)
    name, dur, end0 = VIDEOS[video]
    if preview:
        folder = Path(tempfile.gettempdir()) / "fibonai-social-preview"
        folder.mkdir(exist_ok=True)
        for sec in preview:
            Image.fromarray(render(video, sec)).save(folder / f"v{video}-{ratio}-t{sec:05.2f}.png")
        print(folder)
        return
    out = HERE / f"{name}-{ratio}.mp4"
    audio = Path(tempfile.gettempdir()) / f"fibonai-music-{video}-{ratio}.wav"
    make_music(dur, end0, audio, video)
    cmd = [
        imageio_ffmpeg.get_ffmpeg_exe(), "-y", "-loglevel", "error",
        "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{W}x{H}", "-r", str(FPS), "-i", "-",
        "-i", str(audio),
        "-map", "0:v", "-map", "1:a",
        "-c:v", "libx264", "-preset", "medium", "-crf", "20", "-pix_fmt", "yuv420p",
        "-c:a", "aac", "-b:a", "160k", "-shortest", "-movflags", "+faststart",
        str(out),
    ]
    proc = subprocess.Popen(cmd, stdin=subprocess.PIPE)
    total = int(dur * FPS)
    for i in range(total):
        proc.stdin.write(render(video, i / FPS).tobytes())
        if i % 60 == 0:
            print(f"[{name} {ratio}] {i}/{total}", flush=True)
    proc.stdin.close()
    proc.wait()
    audio.unlink(missing_ok=True)
    if proc.returncode:
        raise SystemExit(f"ffmpeg failed with {proc.returncode}")
    print(f"Wrote {out}", flush=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--video", default="all", help="1-5 or 'all'")
    parser.add_argument("--ratio", default="both", choices=["16x9", "9x16", "both"])
    parser.add_argument("--preview", type=float, nargs="*", help="render PNG stills at these seconds")
    parser.add_argument("--jobs", type=int, default=1, help="parallel renders when more than one video/ratio")
    args = parser.parse_args()

    videos = list(VIDEOS) if args.video == "all" else [int(args.video)]
    ratios = ["16x9", "9x16"] if args.ratio == "both" else [args.ratio]
    jobs = [(v, r) for v in videos for r in ratios]
    if len(jobs) == 1:
        render_one(*jobs[0], args.preview)
        return

    def run(job):
        v, r = job
        extra = ["--preview", *map(str, args.preview)] if args.preview else []
        return subprocess.run([sys.executable, __file__, "--video", str(v), "--ratio", r, *extra]).returncode

    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        codes = list(pool.map(run, jobs))
    if any(codes):
        raise SystemExit(f"some renders failed: {codes}")


if __name__ == "__main__":
    os.environ.setdefault("PYTHONIOENCODING", "utf-8")
    main()
