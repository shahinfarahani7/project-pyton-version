#!/usr/bin/env python3
"""Execute the Worker lightweight-vision math on decoded project PNGs."""
from __future__ import annotations

import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter, ImageOps

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "src/apps/worker/android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png"


def gray(image: Image.Image, size: tuple[int, int] | None = None) -> np.ndarray:
    value = ImageOps.grayscale(image)
    if size:
        value = value.resize(size, Image.Resampling.LANCZOS)
    return np.asarray(value, dtype=np.float64)


def laplacian_variance(image: Image.Image) -> float:
    values = gray(image)
    center = values[1:-1, 1:-1]
    lap = 4 * center - values[1:-1, :-2] - values[1:-1, 2:] - values[:-2, 1:-1] - values[2:, 1:-1]
    return float(lap.var())


def dhash(image: Image.Image) -> np.ndarray:
    values = gray(image, (9, 8))
    return values[:, :-1] > values[:, 1:]


def main() -> int:
    source = Image.open(SOURCE).convert("RGB")
    blurred = source.filter(ImageFilter.GaussianBlur(radius=6))
    resized = source.resize((max(16, source.width // 2), max(16, source.height // 2)))
    inverted = ImageOps.invert(source)
    sharp_variance = laplacian_variance(source)
    blurred_variance = laplacian_variance(blurred)
    same_distance = int(np.count_nonzero(dhash(source) != dhash(resized)))
    different_distance = int(np.count_nonzero(dhash(source) != dhash(inverted)))
    checks = {
        "decoded_real_png": source.width > 1 and source.height > 1,
        "blur_reduces_laplacian_variance": blurred_variance < sharp_variance,
        "resized_duplicate_within_threshold": same_distance <= 6,
        "different_image_outside_threshold": different_distance > 6,
    }
    result = {
        "status": "passed" if all(checks.values()) else "failed",
        "source": str(SOURCE.relative_to(ROOT)),
        "checks": checks,
        "measurements": {
            "sharpVariance": sharp_variance,
            "blurredVariance": blurred_variance,
            "resizedDuplicateHammingDistance": same_distance,
            "differentImageHammingDistance": different_distance,
        },
    }
    print(json.dumps(result, indent=2))
    return 0 if all(checks.values()) else 1


if __name__ == "__main__":
    raise SystemExit(main())
