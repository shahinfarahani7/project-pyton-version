"""Render the FibonAI "Join the waitlist / coming soon" teaser (16:9, 15 s, 30 fps).

Usage (from repository root):
    python docs/brand/waitlist-video/render_waitlist.py               # full MP4
    python docs/brand/waitlist-video/render_waitlist.py --preview 2 6 # PNG stills at given seconds

Requires: pip install pillow numpy opencv-python-headless fonttools imageio-ffmpeg
Fonts are converted from the marketing site's @fontsource packages (Cal Sans, Geist, Geist Mono).
"""

import argparse
import math
import os
import random
import subprocess
import tempfile
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
MARK_DARK = ROOT / "docs" / "brand" / "fibonai-mark-dark.png"
OUTPUT = HERE / "FibonAI-Waitlist-Teaser.mp4"

W, H, FPS, DURATION = 1920, 1080, 30, 15.0

CANVAS = (11, 12, 15)
PANEL = (16, 18, 22)
SLATE = (38, 47, 56)
GOLD = (205, 174, 111)
GOLD_DEEP = (192, 160, 100)
GOLD_SOFT = (241, 230, 207)
GOLD_INK = (128, 101, 51)
LINE = (236, 232, 223)
STEEL_1 = (166, 192, 203)
STEEL_2 = (127, 158, 173)
STEEL_3 = (77, 100, 114)
PAPER = (247, 245, 240)
MUTED = (179, 181, 189)
HOLD = (226, 69, 107)

EMAIL = "hello@yourcompany.com"


# ---------- timing helpers ----------

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


# ---------- fonts ----------

def _convert_font(family, weight):
    cache = Path(tempfile.gettempdir()) / "fibonai-fonts"
    cache.mkdir(exist_ok=True)
    target = cache / f"{family}-{weight}.ttf"
    if not target.exists():
        font = TTFont(FONTSOURCE / family / "files" / f"{family}-latin-{weight}-normal.woff")
        font.flavor = None
        font.save(target)
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


def text_size(text, fnt, tracking=0):
    box = fnt.getbbox(text)
    return box[2] - box[0] + tracking * max(0, len(text) - 1), box[3] - box[1]


def draw_tracked(draw, xy, text, fnt, fill, tracking=0):
    x, y = xy
    for ch in text:
        draw.text((x, y), ch, font=fnt, fill=fill)
        x += fnt.getlength(ch) + tracking


# ---------- sprites ----------

def rounded(size, radius, fill, outline=None, width=0, scale=2):
    """Anti-aliased rounded rectangle sprite (supersampled)."""
    w, h = size
    img = Image.new("RGBA", (w * scale, h * scale), (0, 0, 0, 0))
    ImageDraw.Draw(img).rounded_rectangle(
        (0, 0, w * scale - 1, h * scale - 1), radius * scale, fill=fill, outline=outline, width=width * scale
    )
    return img.resize((w, h), Image.LANCZOS)


def glow(sprite, radius, color, strength=1.0):
    """Soft glow from a sprite's alpha, returned with padding = 3 * radius."""
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


def text_sprite(text, fnt, fill, tracking=0, pad=8):
    w, h = text_size(text, fnt, tracking)
    box = fnt.getbbox(text)
    img = Image.new("RGBA", (int(w) + pad * 2, int(box[3]) + pad * 2), (0, 0, 0, 0))
    draw_tracked(ImageDraw.Draw(img), (pad - box[0], pad), text, fnt, fill, tracking)
    return img


def gradient_text(text, fnt, top, bottom, pad=10):
    mask = text_sprite(text, fnt, (255, 255, 255, 255), pad=pad).getchannel("A")
    grad = Image.new("RGBA", mask.size)
    arr = np.zeros((mask.height, mask.width, 4), np.uint8)
    for i, c in enumerate(top):
        arr[..., i] = np.linspace(c, bottom[i], mask.height)[:, None]
    arr[..., 3] = 255
    grad = Image.fromarray(arr, "RGBA")
    grad.putalpha(mask)
    return grad


def with_shadow(sprite, radius=22, strength=0.75):
    shadow, pad = glow(sprite, radius, (16, 20, 26), strength=strength)
    shadow.alpha_composite(sprite, (pad, pad - 4))
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


def plane_sprite(size):
    s = size * 4
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.polygon([(0.04 * s, 0.46 * s), (0.96 * s, 0.12 * s), (0.42 * s, 0.6 * s)], fill=GOLD_SOFT + (255,))
    d.polygon([(0.42 * s, 0.6 * s), (0.96 * s, 0.12 * s), (0.56 * s, 0.9 * s)], fill=GOLD + (255,))
    d.polygon([(0.42 * s, 0.6 * s), (0.5 * s, 0.86 * s), (0.56 * s, 0.68 * s)], fill=GOLD_DEEP + (255,))
    return img.resize((size, size), Image.LANCZOS)


def device_tile(size, blur):
    w, h = size, int(size * 1.9)
    pad = 40
    img = Image.new("RGBA", (w + pad * 2, h + pad * 2), (0, 0, 0, 0))
    body = rounded((w, h), w // 6, SLATE + (255,), outline=STEEL_3 + (255,), width=max(2, w // 40))
    img.alpha_composite(body, (pad, pad))
    screen = rounded((w - w // 6, h - w // 6), w // 9, PANEL + (255,))
    img.alpha_composite(screen, (pad + w // 12, pad + w // 12))
    d = ImageDraw.Draw(img)
    r = w // 4
    cx, cy = pad + w // 2, pad + h // 2
    ring = Image.new("RGBA", (r * 8, r * 8), (0, 0, 0, 0))
    ImageDraw.Draw(ring).arc((8, 8, r * 8 - 8, r * 8 - 8), -90, 200, fill=GOLD + (255,), width=r)
    ring = ring.resize((r * 2, r * 2), Image.LANCZOS)
    img.alpha_composite(ring, (cx - r, cy - r))
    d.rounded_rectangle((cx - w // 4, cy + r + w // 6, cx + w // 4, cy + r + w // 6 + max(3, w // 30)), 3, fill=(25, 199, 180, 255))
    if blur:
        img = img.filter(ImageFilter.GaussianBlur(blur))
    return img


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
    frame.alpha_composite(spr, (x, y)) if 0 <= x and 0 <= y and x + spr.width <= W and y + spr.height <= H else _paste_clipped(frame, spr, x, y)


def _paste_clipped(frame, spr, x, y):
    left, top = max(0, -x), max(0, -y)
    right, bottom = min(spr.width, W - x), min(spr.height, H - y)
    if right <= left or bottom <= top:
        return
    frame.alpha_composite(spr.crop((left, top, right, bottom)), (x + left, y + top))


# ---------- backgrounds ----------

LOW_W, LOW_H = 240, 135
_yy, _xx = np.mgrid[0:LOW_H, 0:LOW_W].astype(np.float32)
_xx /= LOW_W
_yy /= LOW_W  # keep blobs circular


def field(base, blobs, t):
    img = np.empty((LOW_H, LOW_W, 3), np.float32)
    img[:] = np.array(base, np.float32)
    for cx, cy, r, color, amp, sx, sy, ph in blobs:
        x = cx + 0.04 * math.sin(t * sx + ph)
        y = (cy + 0.04 * math.cos(t * sy + ph)) * LOW_H / LOW_W
        w = amp * np.exp(-((_xx - x) ** 2 + (_yy - y) ** 2) / (r * r))[..., None]
        img = img * (1 - w) + np.array(color, np.float32) * w
    return img


DARK_BLOBS = [
    (0.16, 0.12, 0.30, STEEL_3, 0.55, 0.5, 0.4, 0.0),
    (0.86, 0.22, 0.22, (34, 52, 60), 0.6, 0.4, 0.6, 1.3),
    (0.50, 1.10, 0.42, GOLD_DEEP, 0.38, 0.3, 0.5, 2.1),
]

BRIGHT_BLOBS = [
    (0.18, 0.20, 0.30, LINE, 0.65, 0.6, 0.5, 0.0),
    (0.80, 0.18, 0.34, STEEL_1, 0.8, 0.4, 0.7, 1.0),
    (0.30, 0.82, 0.34, GOLD_SOFT, 0.9, 0.5, 0.4, 2.0),
    (0.82, 0.86, 0.30, GOLD, 0.75, 0.7, 0.5, 3.0),
    (0.52, 0.50, 0.22, (214, 196, 160), 0.35, 0.3, 0.3, 4.0),
    (0.05, 0.80, 0.22, STEEL_3, 0.5, 0.4, 0.6, 5.0),
]

LOGO_BLOBS = [
    (0.50, 0.50, 0.30, (60, 52, 36), 0.7, 0.3, 0.3, 0.0),
    (0.15, 0.15, 0.30, STEEL_3, 0.35, 0.4, 0.4, 1.0),
]


def background(t):
    dark = field(CANVAS, DARK_BLOBS, t)
    bright = field((112, 142, 158), BRIGHT_BLOBS, t)
    logo = field(CANVAS, LOGO_BLOBS, t)
    a = ease_in_out(prog(t, 4.45, 4.85))
    b = ease_in_out(prog(t, 11.7, 12.4))
    img = dark * (1 - a) + bright * a
    img = img * (1 - b) + logo * b
    big = cv2.resize(np.clip(img, 0, 255).astype(np.uint8), (W, H), interpolation=cv2.INTER_CUBIC)
    return big


GRAIN = [np.random.default_rng(i).integers(-5, 6, (H, W, 1), dtype=np.int16) for i in range(4)]


# ---------- scene 1: email field ----------

PLANE = plane_sprite(96)


def scene_email(frame, t):
    if t > 4.9:
        return
    appear = ease_back(prog(t, 0.0, 0.7))
    grow = ease_in_out(prog(t, 0.7, 1.4))
    push = ease_in_out(prog(t, 3.6, 4.7))
    fade = 1 - prog(t, 4.45, 4.8)
    w = int(lerp(220, 1180, grow) * lerp(0.6, 1.0, appear))
    h = int(lerp(64, 132, grow) * lerp(0.6, 1.0, appear))
    zoom = lerp(1.0, 1.35, push)
    w, h = int(w * zoom), int(h * zoom)
    cx, cy = W // 2, H // 2 + int(lerp(0, -40, push))
    opacity = min(1.0, prog(t, 0.0, 0.35)) * fade
    if w < 10:
        return

    pressed = prog(t, 3.0, 3.15) - prog(t, 3.15, 3.35) * 0.0
    filled = ease_out(prog(t, 3.0, 3.25))
    rim = 0.55 + 0.45 * ease_out(prog(t, 2.9, 3.4)) + 0.4 * push

    body = rounded((w, h), h // 2, (18, 20, 25, 225), outline=mix(STEEL_1, GOLD, 0.6 + 0.4 * filled) + (255,), width=3)
    hl = ImageDraw.Draw(body)
    hl.arc((h // 2 - 4, 6, w - h // 2 + 4, h - 6), 200, 340, fill=(255, 255, 255, 40), width=2)
    g, pad = glow(body, 26, GOLD_SOFT if filled > 0.5 else STEEL_1, strength=0.55 * rim)
    paste_center(frame, g, cx, cy, opacity)
    paste_center(frame, body, cx, cy, opacity)

    content = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(content)
    fs = int(h * 0.36)
    typed = int(len(EMAIL) * prog(t, 1.3, 2.7))
    txt = EMAIL[:typed]
    tx = int(h * 0.45) - int(ease_in_out(prog(t, 3.2, 3.9)) * w * 0.55)
    d.text((tx, h // 2), txt, font=font("sans", fs), fill=LINE + (255,), anchor="lm")
    if t < 3.1 and int(t * 2.2) % 2 == 0 and grow > 0.9:
        cx_caret = tx + font("sans", fs).getlength(txt) + 6
        d.rectangle((cx_caret, h // 2 - fs // 2, cx_caret + 3, h // 2 + fs // 2), fill=GOLD + (255,))

    if grow > 0.6:
        bw, bh = int(h * 3.3), h - int(h * 0.22)
        press = 1 - 0.05 * math.sin(math.pi * prog(t, 2.95, 3.3))
        bw2, bh2 = int(bw * press), int(bh * press)
        btn = rounded(
            (bw2, bh2),
            bh2 // 2,
            mix((40, 42, 48), GOLD, filled) + (255,),
            outline=GOLD + (int(255 * (1 - filled * 0.6)),),
            width=2,
        )
        bd = ImageDraw.Draw(btn)
        bd.text((bw2 // 2, bh2 // 2), "Join the waitlist", font=font("medium", int(bh2 * 0.34)), fill=mix(GOLD_SOFT, CANVAS, filled) + (255,), anchor="mm")
        alpha = prog(t, 0.95, 1.3)
        a = btn.getchannel("A").point(lambda v: int(v * alpha))
        btn.putalpha(a)
        content.alpha_composite(btn, (w - bw2 - (h - bh2) // 2 - (bw - bw2) // 2, (h - bh2) // 2))

    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).rounded_rectangle((2, 2, w - 3, h - 3), h // 2, fill=255)
    content.putalpha(ImageChops.multiply(content.getchannel("A"), mask))
    paste_center(frame, content, cx, cy, opacity)

    ring_p = prog(t, 3.05, 3.8)
    if 0 < ring_p < 1:
        ring = rounded((int(w * (1 + 0.15 * ring_p)), int(h * (1 + 0.5 * ring_p))), int(h * (1 + 0.5 * ring_p)) // 2, (0, 0, 0, 0), outline=GOLD_SOFT + (255,), width=2)
        paste_center(frame, ring, cx, cy, (1 - ring_p) * 0.8 * fade)

    fly = prog(t, 3.15, 4.4)
    if 0 < fly < 1:
        bx = cx + w // 2 - int(h * 1.7)
        by = cy
        p = ease_in_out(fly)
        trail = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        td = ImageDraw.Draw(trail)
        prev = None
        for i in range(28):
            q = max(0.0, p - i * 0.018)
            x = lerp(bx, W * 0.9, q) - 120 * math.sin(math.pi * q)
            y = lerp(by, H * 0.08, q ** 1.3) - 60 * math.sin(math.pi * q)
            if prev:
                td.line([prev, (x, y)], fill=GOLD_SOFT + (int(200 * (1 - i / 28)),), width=4)
            prev = (x, y)
        frame.alpha_composite(trail.filter(ImageFilter.GaussianBlur(1.2)))
        x = lerp(bx, W * 0.9, p) - 120 * math.sin(math.pi * p)
        y = lerp(by, H * 0.08, p ** 1.3) - 60 * math.sin(math.pi * p)
        paste_center(frame, PLANE, x, y, min(1, fly * 6), scale=lerp(0.8, 1.2, p), rotate=18 - 20 * p)


# ---------- shared sparkles + floating devices ----------

rng = random.Random(7)
SPARKLES = [
    (rng.uniform(0.05, 0.95), rng.uniform(0.08, 0.92), rng.choice([18, 26, 36, 48]), rng.uniform(0, 6.28), rng.choice([GOLD_SOFT, (255, 255, 255), GOLD]))
    for _ in range(14)
]
STAR_CACHE = {}

DEVICES = []
for i in range(7):
    z = [0.35, 0.5, 0.65, 0.8, 0.95, 0.45, 0.7][i]
    DEVICES.append(
        dict(
            x=[0.12, 0.86, 0.22, 0.78, 0.08, 0.62, 0.36][i],
            y=[0.30, 0.66, 0.78, 0.22, 0.62, 0.86, 0.14][i],
            z=z,
            ph=i * 1.7,
            sprite=device_tile(int(70 + 90 * z), blur=int((1 - z) * 9) if z < 0.8 else (4 if z > 0.9 else 0)),
        )
    )


def sparkles(frame, t, strength):
    if strength <= 0:
        return
    for x, y, size, ph, color in SPARKLES:
        tw = 0.5 + 0.5 * math.sin(t * 2.6 + ph)
        key = (size, color)
        if key not in STAR_CACHE:
            star = star_sprite(size, color)
            g, _ = glow(star, max(6, size // 3), color, strength=0.9)
            g.alpha_composite(star, ((g.width - size) // 2, (g.height - size) // 2))
            STAR_CACHE[key] = g
        paste_center(frame, STAR_CACHE[key], x * W, y * H + math.sin(t + ph) * 8, strength * (0.35 + 0.65 * tw), scale=0.7 + 0.4 * tw, rotate=t * 20 + ph * 10)


def devices(frame, t, strength):
    if strength <= 0:
        return
    for dev in sorted(DEVICES, key=lambda d: d["z"]):
        drift = (t - 4.6) * 18 * dev["z"]
        x = dev["x"] * W + math.sin(t * 0.7 + dev["ph"]) * 26
        y = dev["y"] * H - drift + math.cos(t * 0.9 + dev["ph"]) * 14
        paste_center(frame, dev["sprite"], x, y, strength * (0.55 + 0.45 * dev["z"]), rotate=math.sin(t * 0.5 + dev["ph"]) * 10)


# ---------- scene 2: join the waitlist now ----------

WORD_JOIN = with_shadow(text_sprite("Join the", font("medium", 70), (255, 255, 255, 255)), 16, 0.6)
WORD_WAIT = with_shadow(gradient_text("waitlist", font("display", 210), (255, 250, 238), GOLD), 34, 0.8)
WORD_NOW = with_shadow(text_sprite("now", font("medium", 70), (255, 255, 255, 255)), 16, 0.6)


def scene_waitlist(frame, t):
    if not 4.6 < t < 8.6:
        return
    out = prog(t, 7.7, 8.3)
    zoom = 1 + 0.6 * ease_in_out(out)
    fade = 1 - out
    for i, (spr, dy) in enumerate([(WORD_JOIN, -150), (WORD_WAIT, 0), (WORD_NOW, 150)]):
        p = prog(t, 4.95 + i * 0.22, 5.55 + i * 0.22)
        if p <= 0:
            continue
        s = lerp(0.6, 1.0, ease_back(p)) * zoom
        blur = (1 - p) * 10 + out * 8
        paste_center(frame, spr, W / 2, H / 2 + dy * zoom, min(1, p * 1.5) * fade, scale=s, blur=blur)


# ---------- scene 3: phone with the quote ----------

MARK_SMALL = Image.open(MARK_DARK).convert("RGBA").resize((44, 42), Image.LANCZOS)


def phone_sprite(t):
    pw, ph = 560, 1140
    s = 2
    img = Image.new("RGBA", (pw * s, ph * s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((0, 0, pw * s - 1, ph * s - 1), 86 * s, fill=(28, 31, 36, 255), outline=STEEL_3 + (255,), width=3 * s)
    d.rounded_rectangle((14 * s, 14 * s, (pw - 14) * s, (ph - 14) * s), 74 * s, fill=PAPER + (255,))
    d.rounded_rectangle(((pw / 2 - 60) * s, 30 * s, (pw / 2 + 60) * s, 62 * s), 16 * s, fill=(12, 12, 14, 255))
    img = img.resize((pw, ph), Image.LANCZOS)
    d = ImageDraw.Draw(img)

    d.text((70, 52), "9:41", font=font("semibold", 24), fill=SLATE + (255,))
    img.alpha_composite(MARK_SMALL, (58, 112))
    d.text((112, 133), "FibonAI", font=font("semibold", 30), fill=SLATE + (255,), anchor="lm")
    d.text((pw - 58, 133), "New task", font=font("sans", 24), fill=(91, 99, 108, 255), anchor="rm")

    def fade_in(a, b):
        return ease_out(prog(t, a, b))

    p1 = fade_in(8.7, 9.1)
    chip = rounded((420, 74), 37, (255, 255, 255, int(255 * p1)), outline=(38, 47, 56, int(30 * p1)), width=1)
    cd = ImageDraw.Draw(chip)
    cd.rounded_rectangle((18, 20, 74, 54), 8, fill=HOLD + (int(255 * p1),))
    cd.text((46, 37), "PDF", font=font("semibold", 18), fill=(255, 255, 255, int(255 * p1)), anchor="mm")
    cd.text((92, 37), "invoice-2291.pdf", font=font("mono", 22), fill=SLATE + (int(255 * p1),), anchor="lm")
    img.alpha_composite(chip, ((pw - 420) // 2, 200 + int((1 - p1) * 20)))

    p2 = fade_in(9.0, 9.5)
    card = rounded((460, 470), 34, (255, 255, 255, int(255 * p2)))
    shadow, spad = glow(card, 18, (38, 47, 56), strength=0.25 * p2)
    img.alpha_composite(shadow, ((pw - 460) // 2 - spad, 310 - spad + 16))
    cdr = ImageDraw.Draw(card)
    a = int(255 * p2)
    cdr.text((36, 40), "Document OCR", font=font("medium", 26), fill=(91, 99, 108, a))
    price_p = fade_in(9.3, 9.8)
    cdr.text((36, 92), "€0.0025", font=font("display", 96), fill=SLATE + (int(255 * price_p),))
    cdr.text((40, 205), "per page", font=font("sans", 26), fill=(91, 99, 108, int(255 * price_p)))
    rows = [("Route", "edge preferred"), ("Verification", "standard")]
    for i, (k, v) in enumerate(rows):
        rp = fade_in(9.6 + i * 0.2, 10.0 + i * 0.2)
        y = 270 + i * 64
        cdr.line((36, y, 424, y), fill=(38, 47, 56, int(25 * rp)), width=2)
        cdr.text((36, y + 32), k, font=font("sans", 24), fill=(91, 99, 108, int(255 * rp)), anchor="lm")
        cdr.text((424, y + 32), v, font=font("mono", 22), fill=SLATE + (int(255 * rp),), anchor="rm")
    img.alpha_composite(card, ((pw - 460) // 2, 310 + int((1 - p2) * 24)))

    lock = ease_out(prog(t, 10.2, 10.5))
    lp = fade_in(10.0, 10.3)
    pill = rounded((300, 72), 36, mix((231, 226, 216), GOLD, lock) + (int(255 * lp),))
    pd = ImageDraw.Draw(pill)
    pd.rounded_rectangle((34, 32, 58, 52), 4, fill=SLATE + (int(255 * lp),))
    pd.arc((38, 16 - int((1 - lock) * 6), 54, 40 - int((1 - lock) * 6)), 180, 360, fill=SLATE + (int(255 * lp),), width=4)
    pd.text((76, 36), "Quote locked", font=font("semibold", 26), fill=SLATE + (int(255 * lp),), anchor="lm")
    if lock > 0:
        pg, ppad = glow(pill, 16, GOLD, strength=0.7 * lock)
        img.alpha_composite(pg, ((pw - 300) // 2 - ppad, 810 - ppad))
    img.alpha_composite(pill, ((pw - 300) // 2, 810))

    bp = fade_in(10.4, 10.8)
    btn = rounded((460, 96), 30, SLATE + (int(255 * bp),))
    ImageDraw.Draw(btn).text((230, 48), "Confirm & run", font=font("semibold", 30), fill=GOLD_SOFT + (int(255 * bp),), anchor="mm")
    img.alpha_composite(btn, ((pw - 460) // 2, 960))
    return img


LINES_A = [("See the price", (255, 255, 255)), ("first.", None)]
LINES_B = [("Run on", (255, 255, 255)), ("real devices.", None)]


def headline_sprites(lines, size):
    out = []
    for text, color in lines:
        if color is None:
            spr = gradient_text(text, font("display", size), (255, 248, 232), GOLD_DEEP)
        else:
            spr = text_sprite(text, font("display", size), color + (255,))
        out.append(with_shadow(spr, 22, 0.75))
    return out


HEAD_A = headline_sprites(LINES_A, 112)
HEAD_B = headline_sprites(LINES_B, 112)


def scene_phone(frame, t):
    if not 8.0 < t < 12.4:
        return
    enter = ease_out(prog(t, 8.0, 8.9))
    leave = ease_in_out(prog(t, 11.6, 12.3))
    phone = phone_sprite(t)
    g, _ = glow(phone, 40, (30, 34, 40), strength=0.5)
    px = lerp(W * 0.98, W * 0.7, enter) + leave * 120
    py = lerp(H * 1.2, H * 0.53, enter) - leave * H * 0.9
    rot = lerp(-24, -9, enter) - leave * 8
    scale = 0.86
    paste_center(frame, g, px, py + 30, 0.7 * (1 - leave), scale=scale, rotate=rot)
    paste_center(frame, phone, px, py, 1 - leave * 0.3, scale=scale, rotate=rot, blur=leave * 6)

    for sprites, a, b in ((HEAD_A, 8.9, 10.75), (HEAD_B, 10.9, 11.9)):
        for i, spr in enumerate(sprites):
            p = ease_out(prog(t, a + i * 0.3, a + i * 0.3 + 0.5))
            o = (1 - ease_in_out(prog(t, b, b + 0.3)))
            if p <= 0 or o <= 0:
                continue
            x = W * 0.08 + spr.width / 2
            y = H * 0.42 + i * 130 + (1 - p) * 40
            paste_center(frame, spr, x, y, p * o, blur=(1 - p) * 8)


# ---------- scene 4: logo + coming soon ----------

MARK_IMG = Image.open(MARK).convert("RGBA")
MARK_BIG = MARK_IMG.resize((int(MARK_IMG.width * 0.72), int(MARK_IMG.height * 0.72)), Image.LANCZOS)
MARK_GLOW, _ = glow(MARK_BIG, 30, GOLD, strength=0.5)


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
            y1 = top + (bottom - top) * 0.58
            y2 = top + (bottom - top) * 0.74
            band = Image.new("RGBA", img.size, (0, 0, 0, 0))
            ImageDraw.Draw(band).text((x, 10), "A", font=f, fill=GOLD + (255,))
            clip = Image.new("L", img.size, 0)
            ImageDraw.Draw(clip).rectangle((x, y1, x + aw, y2), fill=255)
            band.putalpha(ImageChops.multiply(band.getchannel("A"), clip))
            img.alpha_composite(band)
        x += f.getlength(text)
    return img


WORDMARK = wordmark(150)
COMING = text_sprite("COMING SOON", font("mono", 30), GOLD_SOFT + (255,), tracking=12)
JOIN_LINE = text_sprite("Join the waitlist — AI that runs on real devices, priced first.", font("sans", 30), MUTED + (255,))


def scene_logo(frame, t):
    if t < 12.0:
        return
    pop = prog(t, 12.25, 12.85)
    slide = ease_in_out(prog(t, 12.95, 13.55))
    total_w = MARK_BIG.width + 40 + WORDMARK.width
    mark_x = lerp(W / 2, W / 2 - total_w / 2 + MARK_BIG.width / 2, slide)
    mark_y = H * 0.44
    s = lerp(0.4, 1.0, ease_back(pop)) if pop < 1 else 1.0
    paste_center(frame, MARK_GLOW, mark_x, mark_y, min(1, pop * 2) * 0.8, scale=s)
    paste_center(frame, MARK_BIG, mark_x, mark_y, min(1, pop * 2), scale=s)

    reveal = ease_out(prog(t, 13.1, 13.75))
    if reveal > 0:
        wm = WORDMARK.copy()
        clip = Image.new("L", wm.size, 0)
        ImageDraw.Draw(clip).rectangle((0, 0, int(wm.width * reveal), wm.height), fill=255)
        wm.putalpha(ImageChops.multiply(wm.getchannel("A"), clip))
        wx = W / 2 - total_w / 2 + MARK_BIG.width + 40 + WORDMARK.width / 2
        paste_center(frame, wm, wx + (1 - reveal) * -30, mark_y + 6, 1.0)

    cp = ease_out(prog(t, 13.6, 14.1))
    paste_center(frame, COMING, W / 2, H * 0.65 + (1 - cp) * 16, cp)
    jp = ease_out(prog(t, 13.85, 14.3))
    paste_center(frame, JOIN_LINE, W / 2, H * 0.72 + (1 - jp) * 16, jp)


# ---------- compositor ----------

def flash(frame, t):
    f = math.sin(math.pi * prog(t, 4.3, 4.95))
    if f <= 0:
        return
    layer = Image.new("RGBA", (W, H), GOLD_SOFT + (int(170 * f),))
    frame.alpha_composite(layer)


def render(t):
    bg = background(t)
    frame = Image.fromarray(bg, "RGB").convert("RGBA")
    bright = prog(t, 4.6, 5.1) * (1 - prog(t, 11.8, 12.3))
    devices(frame, t, bright * (1 - 0.6 * prog(t, 7.9, 8.6)))
    scene_email(frame, t)
    scene_waitlist(frame, t)
    scene_phone(frame, t)
    scene_logo(frame, t)
    sparkles(frame, t, max(bright, 0.6 * prog(t, 12.6, 13.2)))
    flash(frame, t)
    rgb = np.asarray(frame.convert("RGB")).astype(np.int16)
    rgb += GRAIN[int(t * FPS) % 4]
    end = 1 - ease_in_out(prog(t, 14.35, 15.0))
    if end < 1:
        rgb = (rgb * end).astype(np.int16)
    return np.clip(rgb, 0, 255).astype(np.uint8)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--preview", type=float, nargs="*", help="render PNG stills at these seconds")
    parser.add_argument("--out", type=Path, default=OUTPUT)
    args = parser.parse_args()

    if args.preview:
        folder = Path(tempfile.gettempdir()) / "fibonai-waitlist-preview"
        folder.mkdir(exist_ok=True)
        for sec in args.preview:
            Image.fromarray(render(sec)).save(folder / f"t{sec:05.2f}.png")
        print(folder)
        return

    cmd = [
        imageio_ffmpeg.get_ffmpeg_exe(), "-y", "-loglevel", "error",
        "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{W}x{H}", "-r", str(FPS), "-i", "-",
        "-c:v", "libx264", "-preset", "slow", "-crf", "18", "-pix_fmt", "yuv420p", "-movflags", "+faststart",
        str(args.out),
    ]
    proc = subprocess.Popen(cmd, stdin=subprocess.PIPE)
    total = int(DURATION * FPS)
    for i in range(total):
        proc.stdin.write(render(i / FPS).tobytes())
        if i % 30 == 0:
            print(f"{i}/{total}", flush=True)
    proc.stdin.close()
    proc.wait()
    if proc.returncode:
        raise SystemExit(f"ffmpeg failed with {proc.returncode}")
    print(f"Wrote {args.out}")


if __name__ == "__main__":
    os.environ.setdefault("PYTHONIOENCODING", "utf-8")
    main()
