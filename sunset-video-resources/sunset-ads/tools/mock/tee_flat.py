"""Tees flat on tatami: the chest mark on the face-up shirt (wearer's left chest, image right), the back print on
the face-down one. Prints are the transparent film PNGs; the light on each ink is the photo's own fabric
luminance divided by the design's garment luminance, so folds, knit and exposure all carry into the ink."""
import sys, numpy as np, cv2
sys.path.insert(0, 'tools'); from composite import *

env = cv2.imread('env/tee-flatlay.png'); H, W = env.shape[:2]
envlin = to_lin(env[..., ::-1].copy())
lum = lambda x: x[..., 0] * .2126 + x[..., 1] * .7152 + x[..., 2] * .0722
garment_design = lum(to_lin(np.array([[[0x1f, 0x2a, 0x4f]]], np.float32)))[0, 0]
PXMM = 615 / 530                         # pit to pit: 615 px on a 530 mm body
res = env[..., ::-1].astype(np.float32).copy()
sig = grain_sigma(envlin[600:800, 300:700])

def place(film_path, cx, top, w_mm, h_mm, seed):
    art, a = load(film_path); art = art * a[..., None]          # premultiplied, so edges don't fringe
    w, h = w_mm * PXMM, h_mm * PXMM
    q = np.float32([[cx - w / 2, top], [cx + w / 2, top], [cx + w / 2, top + h], [cx - w / 2, top + h]])
    rgb, cov, rect, (x0, y0, x1, y1), M = warp(art, a, q, env.shape, ss=3)
    E = envlin[y0:y1, x0:x1]
    # fabric light: local luminance (folds + knit), relative to the colour the print was designed on
    k = (lum(E) / garment_design)[..., None]
    k = cv2.GaussianBlur(k, (0, 0), 0.6)[..., None] if k.ndim == 3 else k
    ink = soften(rgb, 0.45) / np.maximum(cov[..., None], 1e-4)          # un-premultiply the warped film
    out = ink * np.clip(k, 0, 2.0)
    al = cov[..., None]
    res[y0:y1, x0:x1] = res[y0:y1, x0:x1] * (1 - al) + add_grain(to_srgb(out), sig, seed) * al
    return q

# back: the film is 300 × 470 mm; the print's top sits 8 mm into it, 80 mm below the back neck seam
qb = place('print/tee_back_film_300dpi.png', cx=1503, top=196 + (80 - 8) * PXMM, w_mm=300, h_mm=470, seed=21)
# chest: 100 × 30 mm film, centred 95 mm off the centre line on the wearer's left, 185 mm below the shoulder point
qc = place('print/tee_chest_film_300dpi.png', cx=528 + 95 * PXMM, top=172 + 185 * PXMM, w_mm=100, h_mm=30, seed=22)
save('mock/tee-flatlay.jpg', res, 93)
save('mock/tee-flatlay_back-detail.jpg', res[200:1010, 1150:1860], 95)
save('mock/tee-flatlay_chest-detail.jpg', res[300:560, 500:820], 95)
print('back', qb.round(1).tolist(), 'chest', qc.round(1).tolist(), 'grain', round(sig, 2))
