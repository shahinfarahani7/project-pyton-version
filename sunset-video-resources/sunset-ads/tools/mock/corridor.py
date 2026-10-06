import sys, numpy as np, cv2
sys.path.insert(0, 'tools'); from quad import find_quad, refine; from composite import *
env = cv2.imread('env/station-corridor.png'); H, W = env.shape[:2]
res = env[..., ::-1].astype(np.float32).copy()
envlin = to_lin(env[..., ::-1].copy())
sig = grain_sigma(envlin[300:420, 440:520])       # the tiled wall between frames 1 and 2
rois = [(180, 50, 580, 820), (660, 190, 880, 700), (900, 260, 1040, 640)]
quads = []
for n, roi in enumerate(rois, 1):
    q = refine(env, find_quad(env, roi, thresh=225), band=5, inset=0.4)
    quads.append(q.round(2).tolist())
    art, a = load(f'print/b0_{n}_1030x1456mm_150dpi.png')
    s = art.shape[1] / 1036
    lip = 6                                          # the frame's lip covers 6 mm of the trim on each side
    rgb, cov, rect, (x0, y0, x1, y1), M = warp(art, a, q, env.shape, ss=3, src_rect=((3 + lip) * s, (3 + lip) * s, (1030 - 2 * lip) * s, (1456 - 2 * lip) * s))
    E = envlin[y0:y1, x0:x1]
    # backlight: the blank diffuser's own brightness (its centre-to-edge falloff), normalised to its bright core
    core = np.percentile(E[rect > .99].mean(1), 97)
    illum = np.clip(cv2.GaussianBlur(E, (0, 0), 2.0) / core, 0, 1.05)
    out = add_grain(to_srgb(soften(rgb, 0.5) * illum), sig, seed=n)
    m = rect[..., None]
    res[y0:y1, x0:x1] = res[y0:y1, x0:x1] * (1 - m) + out * m
save('mock/station-corridor.jpg', res, 93)
print('grain', round(sig, 2)); print(quads)
