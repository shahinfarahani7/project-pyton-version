"""Turn the mascot clips into transparent PNG sequences for the app.

States (played in this order when work stops):
    run-loop      working: loops while a task is running
    run-to-sleep  plays once when the job finishes or no task is available
    nap           plays once (cut before the mouth opens), then hands over to sleep-loop
    sleep-loop    loops while idle; starts and ends on the nap's last frame

All sequences share one canvas size and anchor, so switching state never jumps.
Also writes animated WebP versions (2/3 size) plus two stills to src/apps/worker/assets/mascot/.

The source clips in clips/ were exported and then removed. The PNG sequences are
only an intermediate; the app keeps src/apps/worker/assets/mascot/*.webp.
To run this again, put the four clips back in clips/ first.

Usage (from repository root):
    python docs/brand/mascot/build_sequences.py
Requires: pip install pillow numpy opencv-python-headless imageio-ffmpeg
"""

import json
import re
import shutil
import subprocess
from pathlib import Path

import cv2
import imageio_ffmpeg
import numpy as np
from PIL import Image

HERE = Path(__file__).resolve().parent
CLIPS = HERE / "clips"
OUT = HERE / "sequences"
APP_ASSETS = HERE.parents[2] / "src" / "apps" / "worker" / "assets" / "mascot"
APP_SCALE = 2 / 3
W, H, FPS = 848, 480, 24

# The nap clip was generated at 736x400 with a tighter crop; this maps it onto the 848x480 framing
# measured from the run-to-sleep last frame (robot box matched in both clips).
NAP_SCALE = 1.159
NAP_OFFSET = (-3, 8)
# Frames after this the sleeping face's left arc opens into an "o"; the nap ends here.
NAP_LAST_FRAME = 100
# sleep-loop was generated from nap frame 100, upscaled 1.2x to 848x480 with 17.6 px cropped per side.
SLEEP_SCALE = NAP_SCALE / 1.2
SLEEP_OFFSET = (17.6 * SLEEP_SCALE + NAP_OFFSET[0], NAP_OFFSET[1])

# name, clip, loop, (scale, offset) onto the shared canvas, frames kept, next state
SEQUENCES = [
    ("run-loop", "fibonai-mascot-run-loop.mp4", True, (1.0, (0, 0)), None, None),
    ("run-to-sleep", "fibonai-mascot-run-to-sleep.mp4", False, (1.0, (0, 0)), None, "nap"),
    ("nap", "fibonai-mascot-nap.mp4", False, (NAP_SCALE, NAP_OFFSET), NAP_LAST_FRAME, "sleep-loop"),
    ("sleep-loop", "fibonai-mascot-sleep-loop.mp4", True, (SLEEP_SCALE, SLEEP_OFFSET), None, None),
]


def read_frames(path):
    ff = imageio_ffmpeg.get_ffmpeg_exe()
    info = subprocess.run([ff, "-hide_banner", "-i", str(path)], capture_output=True, text=True).stderr
    w, h = map(int, re.search(r"Video:.*?, (\d{2,5})x(\d{2,5})", info).groups())
    proc = subprocess.run([ff, "-loglevel", "error", "-i", str(path), "-f", "rawvideo", "-pix_fmt", "rgb24", "-"], capture_output=True, check=True)
    frames = np.frombuffer(proc.stdout, np.uint8).reshape(-1, h, w, 3)
    return frames, w, h


def to_canvas(frame, transform, bg):
    scale, (ox, oy) = transform
    if frame.shape[:2] == (H, W) and transform == (1.0, (0, 0)):
        return frame
    m = np.float32([[scale, 0, ox], [0, scale, oy]])
    return cv2.warpAffine(frame, m, (W, H), flags=cv2.INTER_CUBIC, borderMode=cv2.BORDER_CONSTANT,
                          borderValue=tuple(int(c) for c in bg))


def cut_out(frame):
    img = frame.astype(np.float32)
    border = np.concatenate([img[:6].reshape(-1, 3), img[-6:].reshape(-1, 3), img[:, :6].reshape(-1, 3), img[:, -6:].reshape(-1, 3)])
    bg = np.median(border, axis=0)
    d = np.linalg.norm(img - bg, axis=2)

    low = (d < 48).astype(np.uint8)
    n, lab, stats, _ = cv2.connectedComponentsWithStats(low, 8)
    edge_labels = set(np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]])))
    background = np.zeros(low.shape, bool)
    for i in range(1, n):
        region = lab == i
        if i in edge_labels:
            background |= region
            continue
        mean = img[region].mean(axis=0)
        if np.abs(mean - bg).max() < 12 and np.ptp(mean) < 8:
            background |= region

    soft = np.clip((d - 14) / (48 - 14), 0, 1)
    alpha = np.where(background, soft, 1.0).astype(np.float32)
    alpha = cv2.GaussianBlur(alpha, (3, 3), 0)
    a = alpha[..., None]
    fg = np.clip(np.where(a > 0.01, (img - bg * (1 - a)) / np.maximum(a, 0.01), 0), 0, 255)
    return np.dstack([fg, alpha * 255]).astype(np.uint8)


def main():
    rendered = {}
    for name, clip, loop, transform, keep, _ in SEQUENCES:
        frames, w, h = read_frames(CLIPS / clip)
        if keep:
            frames = frames[:keep]
        if loop:
            frames = frames[:-1]
        bg = np.median(frames[0][:6].reshape(-1, 3), axis=0).astype(np.uint8)
        rendered[name] = [cut_out(to_canvas(f, transform, bg)) for f in frames]
        print(f"{name}: {len(frames)} frames from {w}x{h}")

    union = np.zeros((H, W), bool)
    for seq in rendered.values():
        for f in seq:
            union |= f[..., 3] > 8
    ys, xs = np.where(union)
    pad = 8
    x0, x1 = max(0, xs.min() - pad), min(W, xs.max() + pad + 1)
    y0, y1 = max(0, ys.min() - pad), min(H, ys.max() + pad + 1)
    x1 -= (x1 - x0) % 2
    y1 -= (y1 - y0) % 2

    if OUT.exists():
        shutil.rmtree(OUT)
    manifest = {"fps": FPS, "width": int(x1 - x0), "height": int(y1 - y0), "sequences": {}}
    for name, _, loop, _, _, then in SEQUENCES:
        folder = OUT / name
        folder.mkdir(parents=True)
        for i, f in enumerate(rendered[name], 1):
            Image.fromarray(f[y0:y1, x0:x1], "RGBA").save(folder / f"frame_{i:04d}.png", optimize=True)
        manifest["sequences"][name] = {
            "folder": name,
            "frames": len(rendered[name]),
            "pattern": "frame_%04d.png",
            "loop": loop,
            "then": then,
        }
    (OUT / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"canvas {manifest['width']}x{manifest['height']} -> {OUT}")
    export_app_assets(rendered, (x0, y0, x1, y1))


def export_app_assets(rendered, box):
    """Animated WebP per state for the worker app (decoded frame by frame, so memory stays small)."""
    x0, y0, x1, y1 = box
    size = (round((x1 - x0) * APP_SCALE), round((y1 - y0) * APP_SCALE))
    APP_ASSETS.mkdir(parents=True, exist_ok=True)

    def frames(name):
        return [Image.fromarray(f[y0:y1, x0:x1], "RGBA").resize(size, Image.LANCZOS) for f in rendered[name]]

    for name, *_ in SEQUENCES:
        seq = frames(name)
        target = APP_ASSETS / f"{name.replace('-', '_')}.webp"
        seq[0].save(
            target, save_all=True, append_images=seq[1:], duration=round(1000 / FPS), loop=0,
            quality=82, alpha_quality=90, method=6,
        )
        print(f"app asset {target.name}: {len(seq)} frames, {target.stat().st_size // 1024} KB")
    frames("sleep-loop")[0].save(APP_ASSETS / "asleep.webp", quality=90, alpha_quality=95, method=6)
    frames("run-loop")[0].save(APP_ASSETS / "working.webp", quality=90, alpha_quality=95, method=6)


if __name__ == "__main__":
    main()
