import sys, numpy as np, cv2
sys.path.insert(0, 'tools'); from quad import find_quad, refine; from composite import *
env = cv2.imread('env/billboard-street.png'); H, W = env.shape[:2]
q = refine(env, find_quad(env, (950, 20, 1700, 380)), inset=0.6)
art, a = load('print/billboard_10920x3640mm_1-10scale_300dpi.png')
# the print is 1102 × 374 mm with bleed; the face shows the 1092 × 364 trim (the bleed wraps the frame)
s = art.shape[1] / 1102
rgb, cov, rect, (x0, y0, x1, y1), M = warp(art, a, q, env.shape, ss=3, src_rect=(5 * s, 5 * s, 1092 * s, 364 * s))
E = to_lin(env[y0:y1, x0:x1, ::-1].copy())
# illuminance on the face: the blank vinyl divided by its own white (≈0.82 reflectance), smoothed a touch
# so the photo's grain rides on top rather than being multiplied into the dark print
white = 0.82
illum = cv2.GaussianBlur(E, (0, 0), 1.2) / white
out_lin = soften(rgb, 0.55) * illum
sig = grain_sigma(to_lin(env[180:300, 1150:1500, ::-1].copy()))
out = add_grain(to_srgb(out_lin), sig)
base = to_srgb(E)
m = rect[..., None]
comp = base * (1 - m) + out * m
res = env[..., ::-1].astype(np.float32).copy(); res[y0:y1, x0:x1] = comp
save('mock/billboard-street.jpg', res, 93)
save('mock/billboard-street_detail.jpg', res[0:420, 900:1720], 94)
print('quad', q.round(2).tolist(), 'grain', round(sig, 2))
