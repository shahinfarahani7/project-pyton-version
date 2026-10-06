"""Meishi on the hinoki desk: the English side on the left card, the Japanese side on the turned card.

Each card face takes the print PNG (trim only). The photo's own blank card supplies the light and the paper's
tooth (art × photo / photo's paper median). The letterpress bite comes from the real plates: sumi, vermilion
and the split-fountain sun press ink into the board, the blind plate presses the grid rules with no ink.
Their depth map is lit from the window (upper left) so the impressions read as relief, never as a gloss."""
import sys, numpy as np, cv2
sys.path.insert(0, 'tools'); from quad import find_quad, refine; from composite import *

env = cv2.imread('env/desk-cards.png'); H, W = env.shape[:2]
hsv = cv2.cvtColor(env, cv2.COLOR_BGR2HSV); paper = (hsv[..., 1] < 32) & (hsv[..., 2] > 150)
envlin = to_lin(env[..., ::-1].copy())
res = env[..., ::-1].astype(np.float32).copy()
sig = grain_sigma(envlin[450:650, 420:900])
cards = [('en', (320, 380, 1020, 760)), ('jp', (1010, 360, 1750, 840))]
LIGHT = np.array([-0.62, -0.78])          # from the window, upper left, in the card's own axes
for side, roi in cards:
    q = refine(env, find_quad(env, roi, mask=paper), band=3, inset=0.9)
    im = cv2.imread(f'print/meishi_{side}_91x55mm_600dpi.png')[..., ::-1]
    s = im.shape[1] / 97; b = int(round(3 * s))
    trim = lambda a: a[b:b + int(round(55 * s)), b:b + int(round(91 * s))]
    art = trim(im)
    plate = lambda n: 1 - trim(cv2.imread(f'print/plates/meishi_{side}_plate-{n}_600dpi.png', cv2.IMREAD_GRAYSCALE)).astype(np.float32) / 255
    ink = np.clip(plate('sumi') + plate('verm') + plate('fount'), 0, 1); blind = plate('blind')
    # work at ~3× the size the card lands at
    Wt = int(np.linalg.norm(q[1] - q[0]) * 3); Ht = int(Wt * 55 / 91)
    rs = lambda a: cv2.resize(a, (Wt, Ht), interpolation=cv2.INTER_AREA)
    art = to_lin(rs(art).astype(np.float32)); ink = rs(ink); blind = rs(blind)
    pxmm = Wt / 91
    depth = -(0.55 * ink + 1.0 * blind)                          # ink bites less than the blind rules
    depth = cv2.GaussianBlur(depth, (0, 0), 0.09 * pxmm)
    gx = cv2.Sobel(depth, cv2.CV_32F, 1, 0, ksize=3) / 8 * pxmm / 0.12
    gy = cv2.Sobel(depth, cv2.CV_32F, 0, 1, ksize=3) / 8 * pxmm / 0.12
    shade = 1 + 0.10 * np.clip(gx * LIGHT[0] + gy * LIGHT[1], -1.5, 1.5)
    art = art * shade[..., None]
    # the card's paper colour in the art, to divide out: the median of the un-inked area
    paper_art = np.median(art[(ink < .02) & (blind < .02)], 0)
    rgb, cov, rect, (x0, y0, x1, y1), M = warp(art / paper_art, np.ones(art.shape[:2], np.float32), q, env.shape, ss=2)
    E = envlin[y0:y1, x0:x1]
    inside = rect > .99
    ref = np.median(E[inside], 0)
    # the cream board: the design's paper colour, carrying the photo's light and tooth
    board = to_lin(np.array([[[0xf6, 0xee, 0xdd]]], np.float32))[0, 0]
    out = rgb * board * (E / ref)
    out = add_grain(to_srgb(soften(out, 0.35)), sig, seed=5 if side == 'en' else 6)
    m = rect[..., None]
    res[y0:y1, x0:x1] = res[y0:y1, x0:x1] * (1 - m) + out * m
    print(side, q.round(1).tolist())
save('mock/meishi-desk.jpg', res, 93)
save('mock/meishi-desk_detail.jpg', res[330:840, 300:1760], 95)
