"""Place the rendered artwork PNGs onto the blank surfaces of the environment photos.

The artwork is never redrawn: each print PNG is resampled once through a homography onto its surface.
Light comes from the photo itself: the blank surface, divided by its own paper/vinyl white, is the
illuminance that falls on it (the lamp pools, the backlight falloff, the fabric's folds), and the art is
multiplied by it in linear light. Grain and lens softness are matched to the photo so the print sits in it."""
import numpy as np, cv2

def to_lin(x):
    x = np.asarray(x, np.float32) / 255.0
    return np.where(x <= 0.04045, x / 12.92, ((x + 0.055) / 1.055) ** 2.4).astype(np.float32)

def to_srgb(x):
    x = np.clip(x, 0, 1)
    return (np.where(x <= 0.0031308, x * 12.92, 1.055 * np.power(x, 1 / 2.4) - 0.055) * 255.0).astype(np.float32)

def load(path):
    """BGR(A) uint8 → linear RGB float + alpha (1 where the file has none)."""
    im = cv2.imread(path, cv2.IMREAD_UNCHANGED)
    if im.ndim == 2: im = cv2.cvtColor(im, cv2.COLOR_GRAY2BGR)
    a = im[..., 3].astype(np.float32) / 255 if im.shape[2] == 4 else np.ones(im.shape[:2], np.float32)
    return to_lin(im[..., 2::-1][..., :3].copy()), a

def warp(art, alpha, quad, shape, ss=3, src_rect=None):
    """Resample `art` (H×W×3 linear) into the quad (TL TR BR BL, env pixels) on a canvas of `shape`,
    supersampled ss× and box-filtered down. Returns (rgb, coverage) in env pixels, only inside the quad's box."""
    H, W = shape[:2]
    q = np.asarray(quad, np.float32)
    x0, y0 = np.floor(q.min(0)).astype(int) - 2; x1, y1 = np.ceil(q.max(0)).astype(int) + 3
    x0, y0 = max(x0, 0), max(y0, 0); x1, y1 = min(x1, W), min(y1, H)
    bw, bh = (x1 - x0) * ss, (y1 - y0) * ss
    # pre-shrink the art to about the size it lands at (×ss), so the warp never minifies more than ~2×
    side = max(np.linalg.norm(q[1] - q[0]), np.linalg.norm(q[2] - q[3])) * ss * 1.5
    k = min(1.0, side / art.shape[1])
    if k < 1:
        art = cv2.resize(art, (int(art.shape[1] * k), int(art.shape[0] * k)), interpolation=cv2.INTER_AREA)
        alpha = cv2.resize(alpha, (art.shape[1], art.shape[0]), interpolation=cv2.INTER_AREA)
    h, w = art.shape[:2]
    sx, sy, sw, sh = src_rect if src_rect else (0, 0, w, h)
    if src_rect and k < 1: sx, sy, sw, sh = [v * k for v in src_rect]
    src = np.float32([[sx, sy], [sx + sw, sy], [sx + sw, sy + sh], [sx, sy + sh]])
    dst = (q - [x0, y0]) * ss
    M = cv2.getPerspectiveTransform(src, dst.astype(np.float32))
    rgb = cv2.warpPerspective(art, M, (bw, bh), flags=cv2.INTER_LINEAR, borderMode=cv2.BORDER_CONSTANT)
    cov = cv2.warpPerspective(alpha, M, (bw, bh), flags=cv2.INTER_LINEAR, borderMode=cv2.BORDER_CONSTANT)
    # coverage of the rectangle itself (antialiased edge), independent of the art's own alpha
    rect = np.zeros((bh, bw), np.float32); cv2.fillConvexPoly(rect, np.round(dst * 4).astype(np.int32), 1.0, lineType=cv2.LINE_AA, shift=2)
    rgb = cv2.resize(rgb, (x1 - x0, y1 - y0), interpolation=cv2.INTER_AREA)
    cov = cv2.resize(cov * rect, (x1 - x0, y1 - y0), interpolation=cv2.INTER_AREA)
    rect = cv2.resize(rect, (x1 - x0, y1 - y0), interpolation=cv2.INTER_AREA)
    return rgb, cov, rect, (x0, y0, x1, y1), M

def grain_sigma(env_lin_patch):
    """Photo noise level (sRGB units) from the high-pass of a flat patch."""
    s = to_srgb(env_lin_patch).mean(2)
    hp = s - cv2.GaussianBlur(s, (0, 0), 2)
    return float(1.4826 * np.median(np.abs(hp - np.median(hp))))   # robust: edges and gradients don't count

def soften(rgb, sigma):
    return cv2.GaussianBlur(rgb, (0, 0), sigma) if sigma > 0 else rgb

def add_grain(srgb, sigma, seed=3):
    rng = np.random.default_rng(seed)
    n = rng.normal(0, sigma, srgb.shape[:2]).astype(np.float32)[..., None]
    n = cv2.GaussianBlur(n, (0, 0), 0.6)[..., None] * 1.6 if n.ndim == 3 else n
    return srgb + n

def save(path, srgb, q=92):
    out = np.clip(srgb, 0, 255).astype(np.uint8)[..., ::-1]
    if path.endswith('.jpg'): cv2.imwrite(path, out, [cv2.IMWRITE_JPEG_QUALITY, q])
    else: cv2.imwrite(path, out)
