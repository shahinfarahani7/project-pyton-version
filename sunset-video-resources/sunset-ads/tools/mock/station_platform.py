"""Platform: the B0 5連 corridor panel on the far wall across the tracks.

The generated lightbox was 3.08:1 (perspective-corrected, 35 mm lens); a B0 5連 shows 3.55:1 inside its frame.
So the frame is retouched out along the wall plane first: its two end pieces move out 140 rectified px each,
the top and bottom rails are resampled 15% longer, and the rebuilt frame is warped back through the wall's
own homography (perspective stays exact). Then the five sheet PNGs, trimmed and butted, go on the face."""
import sys, numpy as np, cv2
sys.path.insert(0, 'tools'); from quad import find_quad, refine, order; from composite import *

env = cv2.imread('env/platform-v2.png'); H, W = env.shape[:2]
# the face (the diffuser inside the frame), refined to its edge lines
g = cv2.cvtColor(env, cv2.COLOR_BGR2GRAY)
x0, y0, x1, y1 = 600, 200, 1420, 560
m = (g[y0:y1, x0:x1] > 205).astype(np.uint8) * 255
m = cv2.morphologyEx(m, cv2.MORPH_CLOSE, np.ones((1, 15), np.uint8))
cs, _ = cv2.findContours(m, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE); c = max(cs, key=cv2.contourArea)
ap = cv2.approxPolyDP(c, 0.01 * cv2.arcLength(c, True), True)
qf = refine(env, order(ap.reshape(-1, 2).astype(float) + [x0, y0]), band=4).astype(np.float32)

Hr, RA = 600, 3.083                        # rectified face height; its true aspect at f = 1991 px
Wf = int(round(RA * Hr)); mx, my = 140, 110
Hm = cv2.getPerspectiveTransform(np.float32([[0, 0], [Wf, 0], [Wf, Hr], [0, Hr]]), qf)
T = lambda tx, ty: np.array([[1, 0, tx], [0, 1, ty], [0, 0, 1]], np.float64)
R0 = cv2.warpPerspective(env, Hm @ T(-mx, -my), (Wf + 2 * mx, Hr + 2 * my), flags=cv2.WARP_INVERSE_MAP | cv2.INTER_CUBIC)

# ---- the rebuilt frame, in rectified px; old face u in [0, Wf], new face u' in [0, Wn], u = u' - ext
TARGET = (5150 - 12) / (1456 - 12)       # visible area of a B0 5連 inside a 6 mm lip
Wn = int(round(TARGET * Hr)); ext = (Wn - Wf) // 2; Wn = Wf + 2 * ext
FL, FT, FB = 33, 34, 29                 # frame widths (left/right, top, bottom) incl. the outer shadow line
ml = 60
L = np.zeros((Hr + 2 * my, Wn + 2 * ml, 3), np.uint8); A = np.zeros(L.shape[:2], np.float32)
L[:, ml - FL:ml + 3] = R0[:, mx - FL:mx + 3]                                  # left end piece
L[:, ml + Wn - 3:ml + Wn + FL] = R0[:, mx + Wf - 3:mx + Wf + FL]              # right end piece
for (a, b) in ((my - FT, my + 3), (my + Hr - 3, my + Hr + FB)):               # top and bottom rails
    L[a:b, ml + 3:ml + Wn - 3] = cv2.resize(R0[a:b, mx + 3:mx + Wf - 3], (Wn - 6, b - a), interpolation=cv2.INTER_CUBIC)
A[my - FT:my + Hr + FB, ml - FL:ml + Wn + FL] = 1
A[my + 2:my + Hr - 2, ml + 2:ml + Wn - 2] = 0                                   # the face is handled below
# feather the outer 1.5 px of the frame so its edge sits in the wall like the original's
A = cv2.GaussianBlur(A, (0, 0), 0.7)

ss = 3
S = np.diag([ss, ss, 1.0])
ML = S @ Hm @ T(-ml - ext, -my)
Lw = cv2.warpPerspective(L.astype(np.float32), ML, (W * ss, H * ss), flags=cv2.INTER_LINEAR)
Aw = cv2.warpPerspective(A, ML, (W * ss, H * ss), flags=cv2.INTER_LINEAR)
Lw = cv2.resize(Lw, (W, H), interpolation=cv2.INTER_AREA); Aw = cv2.resize(Aw, (W, H), interpolation=cv2.INTER_AREA)
res = env.astype(np.float32).copy()
res = res * (1 - Aw[..., None]) + Lw * Aw[..., None]
res = res[..., ::-1]

# ---- the face: the five B0 sheets, bleed trimmed, butted edge to edge, minus the 6 mm lip all round
sheets = []
for k in range(1, 6):
    im = cv2.imread(f'print/corridor_sheet{k}_B0_150dpi.png')[..., ::-1]
    s = im.shape[1] / 1036
    im = im[int(3 * s):int((3 + 1456) * s), int(3 * s):int((3 + 1030) * s)]
    sheets.append(cv2.resize(im, (im.shape[1] // 3, im.shape[0] // 3), interpolation=cv2.INTER_AREA))
hh = min(i.shape[0] for i in sheets); pano = np.concatenate([i[:hh] for i in sheets], 1)
s = pano.shape[1] / 5150; lip = 6 * s
pano = pano[int(lip):int(hh - lip), int(lip):int(pano.shape[1] - lip)]
art = to_lin(pano.copy())
# the joins: five sheets butted in one frame show as hairlines, a paper edge's worth of shadow
jw = max(1, int(round(0.9 * s)))
for k in range(1, 5):
    x = int(round(1030 * k * s - lip)); art[:, x - jw:x + jw] *= 0.62
# backlight: the original diffuser's vertical falloff, measured across its middle, same along the length
face = to_lin(R0[my + 4:my + Hr - 4, mx + 60:mx + Wf - 60, ::-1].copy()).mean(2)
prof = np.median(face, 1); prof = cv2.GaussianBlur(prof[:, None], (0, 0), 6).ravel(); prof /= np.percentile(prof, 95)
illum = cv2.resize(prof[:, None].astype(np.float32), (1, art.shape[0]), interpolation=cv2.INTER_LINEAR)[:, :, None]
art = art * np.clip(illum, 0, 1.03)
qn = cv2.perspectiveTransform(np.float32([[[0, 0], [Wn, 0], [Wn, Hr], [0, Hr]]]), Hm @ T(-ext, 0)).reshape(4, 2)
rgb, cov, rect, (a0, b0, a1, b1), M = warp(art, np.ones(art.shape[:2], np.float32), qn, env.shape, ss=3)
sig = grain_sigma(to_lin(env[140:200, 300:560, ::-1].copy()))
out = add_grain(to_srgb(soften(rgb, 0.45)), sig, seed=11)
mm = rect[..., None]
res[b0:b1, a0:a1] = res[b0:b1, a0:a1] * (1 - mm) + out * mm
save('mock/station-platform.jpg', res, 93)
save('mock/station-platform_detail.jpg', res[180:600, 440:1560], 94)
print('face', qf.round(1).tolist(), 'new face', qn.round(1).tolist(), 'ext', ext, 'grain', round(sig, 2))
