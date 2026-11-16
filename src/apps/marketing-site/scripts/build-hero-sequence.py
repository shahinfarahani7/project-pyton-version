"""Turn hero videos into the scroll-scrubbed frame sequence used by HeroSequence.vue.

Usage (from src/apps/marketing-site):
    python scripts/build-hero-sequence.py --desktop path/to/hero-16x9.mp4 [--mobile path/to/hero-9x16.mp4]

Requires: pip install opencv-python-headless pillow
"""

import argparse
import json
from pathlib import Path

import cv2
from PIL import Image

OUTPUT = Path(__file__).resolve().parent.parent / "public" / "hero-sequence"


def export(video: Path, name: str, frames: int, width: int, quality: int) -> dict:
    capture = cv2.VideoCapture(str(video))
    if not capture.isOpened():
        raise SystemExit(f"Cannot open video: {video}")
    total = int(capture.get(cv2.CAP_PROP_FRAME_COUNT))
    if total < 2:
        raise SystemExit(f"Video has no readable frames: {video}")
    count = min(frames, total)

    folder = OUTPUT / name
    folder.mkdir(parents=True, exist_ok=True)
    for old in folder.glob("frame_*.webp"):
        old.unlink()

    wanted = {round(i * (total - 1) / (count - 1)): i for i in range(count)}
    written = 0
    size = (0, 0)
    for source_index in range(total):
        ok, frame = capture.read()
        if not ok:
            break
        if source_index not in wanted:
            continue
        image = Image.fromarray(cv2.cvtColor(frame, cv2.COLOR_BGR2RGB))
        if image.width > width:
            image = image.resize((width, round(image.height * width / image.width)), Image.LANCZOS)
        size = image.size
        image.save(folder / f"frame_{wanted[source_index] + 1:04d}.webp", "WEBP", quality=quality, method=6)
        written += 1
    capture.release()

    if written != count:
        raise SystemExit(f"Expected {count} frames from {video}, wrote {written}")
    megabytes = sum(path.stat().st_size for path in folder.glob("frame_*.webp")) / 1_000_000
    print(f"{name}: {written} frames, {size[0]}x{size[1]}, {megabytes:.1f} MB")
    return {"count": written, "path": f"/hero-sequence/{name}/frame_{{i}}.webp", "pad": 4, "width": size[0], "height": size[1]}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--desktop", type=Path, required=True, help="16:9 hero video")
    parser.add_argument("--mobile", type=Path, help="optional 9:16 hero video")
    parser.add_argument("--frames", type=int, default=120, help="frames to keep per video (default 120)")
    parser.add_argument("--quality", type=int, default=72, help="WebP quality 1-100 (default 72)")
    args = parser.parse_args()

    manifest = {"desktop": export(args.desktop, "desktop", args.frames, 1600, args.quality)}
    if args.mobile:
        manifest["mobile"] = export(args.mobile, "mobile", args.frames, 900, args.quality)
    (OUTPUT / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote {OUTPUT / 'manifest.json'}")


if __name__ == "__main__":
    main()
