"""Quad helpers for the mockups: find a bright blank surface's corners, refine them to sub-pixel edge lines,
and recover the rectangle's true aspect ratio from its perspective image (Zhang & He, 'Whiteboard scanning')."""
import numpy as np, cv2

def find_quad(img, roi, thresh=None, mask=None):
    x0, y0, x1, y1 = roi
    if mask is not None: m = mask[y0:y1, x0:x1].astype(np.uint8) * 255
    else:
        g = cv2.cvtColor(img[y0:y1, x0:x1], cv2.COLOR_BGR2GRAY)
        if thresh is None: thresh, _ = cv2.threshold(g, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
        m = (g > thresh).astype(np.uint8) * 255
    m = cv2.morphologyEx(m, cv2.MORPH_OPEN, np.ones((5, 5), np.uint8))
    cs, _ = cv2.findContours(m, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)
    c = max(cs, key=cv2.contourArea)
    peri = cv2.arcLength(c, True)
    for eps in np.linspace(0.005, 0.05, 40):
        ap = cv2.approxPolyDP(c, eps * peri, True)
        if len(ap) == 4: break
    q = ap.reshape(4, 2).astype(float) + [x0, y0]
    return order(q)

def order(q):
    q = np.asarray(q, float); s = q.sum(1); d = q[:, 1] - q[:, 0]
    return np.array([q[np.argmin(s)], q[np.argmin(d)], q[np.argmax(s)], q[np.argmax(d)]])   # TL TR BR BL

def refine(img, q, band=6, inset=0.0):
    """Fit each side as a line through the strongest luminance edge near it; corners = line intersections."""
    g = cv2.GaussianBlur(cv2.cvtColor(img, cv2.COLOR_BGR2GRAY).astype(np.float32), (0, 0), 0.8)
    gx = cv2.Sobel(g, cv2.CV_32F, 1, 0); gy = cv2.Sobel(g, cv2.CV_32F, 0, 1)
    lines = []
    for i in range(4):
        a, b = q[i], q[(i + 1) % 4]
        t = (b - a) / np.linalg.norm(b - a); n = np.array([-t[1], t[0]])
        pts = []
        for s in np.linspace(0.06, 0.94, 60):
            p = a + (b - a) * s
            best, bo = -1, 0
            for o in np.arange(-band, band + 0.01, 0.25):
                x, y = p + n * o
                xi, yi = int(round(x)), int(round(y))
                if not (0 <= xi < g.shape[1] and 0 <= yi < g.shape[0]): continue
                v = abs(gx[yi, xi] * n[0] + gy[yi, xi] * n[1])
                if v > best: best, bo = v, o
            pts.append(p + n * bo)
        pts = np.array(pts, np.float32)
        vx, vy, x0, y0 = cv2.fitLine(pts, cv2.DIST_HUBER, 0, 0.01, 0.01).ravel()
        lines.append((np.array([x0, y0]), np.array([vx, vy])))
    out = []
    for i in range(4):
        (p1, d1), (p2, d2) = lines[i - 1], lines[i]
        A = np.array([d1, -d2]).T
        s = np.linalg.solve(A, p2 - p1)
        out.append(p1 + d1 * s[0])
    q2 = np.array(out)
    if inset:   # pull each corner toward the centre by `inset` px (to stay inside a frame lip)
        c = q2.mean(0); q2 = q2 + (c - q2) / np.linalg.norm(c - q2, axis=1)[:, None] * inset
    return q2

def aspect(q, W, H, f=None):
    """True width/height of the rectangle imaged as quad q (TL TR BR BL), principal point at the centre.
    Returns (ratio, focal) — focal is estimated when not given (needs real perspective)."""
    u0, v0 = W / 2, H / 2
    m1, m2, m3, m4 = [np.array([x, y, 1.0]) for x, y in (q[3], q[2], q[0], q[1])]   # BL BR TL TR as in the paper
    k2 = np.dot(np.cross(m1, m4), m3) / np.dot(np.cross(m2, m4), m3)
    k3 = np.dot(np.cross(m1, m4), m2) / np.dot(np.cross(m3, m4), m2)
    n2 = k2 * m2 - m1; n3 = k3 * m3 - m1
    if f is None:
        num = (n2[0] * n3[0] - (n2[0] * n3[2] + n2[2] * n3[0]) * u0 + n2[2] * n3[2] * u0 * u0 +
               n2[1] * n3[1] - (n2[1] * n3[2] + n2[2] * n3[1]) * v0 + n2[2] * n3[2] * v0 * v0)
        f2 = -num / (n2[2] * n3[2])
        f = np.sqrt(f2) if f2 > 0 else None
    if f is None: return None, None
    A = np.array([[f, 0, u0], [0, f, v0], [0, 0, 1.0]]); Ai = np.linalg.inv(A)
    r = np.sqrt((n2 @ Ai.T @ Ai @ n2) / (n3 @ Ai.T @ Ai @ n3))
    return r, f
