"""The back print, worn. The film PNG is wrapped onto the back as a cylinder (R ≈ 180 mm), nudged along the
fabric's folds (a small displacement from the photo's own shading gradient), and lit by the photo: the back is
in shade with the low sun ahead, so the ink takes the shirt's own luminance, rim light and knit included."""
import sys, numpy as np, cv2
sys.path.insert(0, 'tools'); from composite import *

env = cv2.imread('env/tee-worn.png'); H, W = env.shape[:2]
envlin = to_lin(env[..., ::-1].copy())
lum = lambda x: x[..., 0] * .2126 + x[..., 1] * .7152 + x[..., 2] * .0722
garment_design = lum(to_lin(np.array([[[0x1f, 0x2a, 0x4f]]], np.float32)))[0, 0]
PXMM = 550 / 400                          # torso 550 px across a ~400 mm visible back
CX, NECK = 578, 510                       # spine line and back neck seam
R = 180 * PXMM                            # the back's curvature, px
film, fa = load('print/tee_back_film_300dpi.png'); film = film * fa[..., None]
FW, FH = 300, 470                         # film size, mm
top = NECK + (80 - 8) * PXMM
ss = 3
x0, x1 = int(CX - R * np.sin(FW / 2 * PXMM / R)) - 4, int(CX + R * np.sin(FW / 2 * PXMM / R)) + 5
y0, y1 = int(top) - 4, int(top + FH * PXMM) + 5
# the art, pre-shrunk to ~ss× its landing size
k = FW * PXMM * ss * 1.2 / film.shape[1]
art = cv2.resize(film, None, fx=k, fy=k, interpolation=cv2.INTER_AREA); al = cv2.resize(fa, (art.shape[1], art.shape[0]), interpolation=cv2.INTER_AREA)
appmm = art.shape[1] / FW
# fold displacement: fabric pushed along its shading gradient, up to ~2 px
S = cv2.GaussianBlur(lum(envlin), (0, 0), 5)
gx = cv2.Sobel(S, cv2.CV_32F, 1, 0, ksize=5); gy = cv2.Sobel(S, cv2.CV_32F, 0, 1, ksize=5)
g = np.sqrt(gx ** 2 + gy ** 2); sc = 2.0 / (np.percentile(g[y0:y1, x0:x1], 99) + 1e-6)
ys, xs = np.mgrid[y0 * ss:y1 * ss, x0 * ss:x1 * ss].astype(np.float32) / ss
dx = cv2.resize(gx[y0:y1, x0:x1] * sc, (xs.shape[1], xs.shape[0])); dy = cv2.resize(gy[y0:y1, x0:x1] * sc, (xs.shape[1], xs.shape[0]))
xs2, ys2 = xs - dx, ys - dy
# cylinder: image x → arc length on the back → film mm
t = np.clip((xs2 - CX) / R, -0.999, 0.999)
u_mm = R * np.arcsin(t) / PXMM + FW / 2
v_mm = (ys2 - top) / PXMM
mx, my = (u_mm * appmm).astype(np.float32), (v_mm * appmm).astype(np.float32)
rgb = cv2.remap(art, mx, my, cv2.INTER_LINEAR, borderMode=cv2.BORDER_CONSTANT)
cov = cv2.remap(al, mx, my, cv2.INTER_LINEAR, borderMode=cv2.BORDER_CONSTANT)
rgb = cv2.resize(rgb, (x1 - x0, y1 - y0), interpolation=cv2.INTER_AREA); cov = cv2.resize(cov, (x1 - x0, y1 - y0), interpolation=cv2.INTER_AREA)
E = envlin[y0:y1, x0:x1]
light = np.clip(lum(E) / garment_design, 0, 3)[..., None]
ink = soften(rgb, 0.4) / np.maximum(cov[..., None], 1e-4)
out = add_grain(to_srgb(ink * light), grain_sigma(envlin[1000:1200, 450:700]), seed=31)
res = env[..., ::-1].astype(np.float32).copy()
res[y0:y1, x0:x1] = res[y0:y1, x0:x1] * (1 - cov[..., None]) + out * cov[..., None]
save('mock/tee-worn.jpg', res, 93)
print('box', x0, y0, x1, y1)
