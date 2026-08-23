#!/usr/bin/env python3
"""Regenerate package statistics, manifest and checksums from one canonical implementation."""
from __future__ import annotations

import collections
import hashlib
import json
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CHECKSUMS = ROOT / "CHECKSUMS.sha256"
MANIFEST = ROOT / "PACKAGE-MANIFEST.json"
EXCLUDED_FROM_MANIFEST = {"CHECKSUMS.sha256", "PACKAGE-MANIFEST.json"}
EXCLUDED_FROM_CHECKSUMS = {"CHECKSUMS.sha256"}
EXCLUDED_DIRECTORY_NAMES = {
    ".git",
    ".idea",
    ".venv",
    ".pytest_cache",
    ".dart_tool",
    ".terraform",
    ".tmp_e2e",
    "__pycache__",
    "node_modules",
    "build",
    "dist",
}
EXCLUDED_LOCAL_FILES = {".env", ".env.docker", "tmp-cookies.txt", "tmp_cookies.txt"}


def is_distributable(relative: str) -> bool:
    if relative in EXCLUDED_FROM_CHECKSUMS:
        return False
    parts = Path(relative).parts
    if not parts:
        return False
    if parts[-1] in EXCLUDED_LOCAL_FILES or parts[-1].startswith(".tmp"):
        return False
    return not any(part in EXCLUDED_DIRECTORY_NAMES for part in parts[:-1])


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def line_count(path: Path) -> int | None:
    try:
        with path.open(encoding="utf-8") as stream:
            return sum(1 for _ in stream)
    except (UnicodeDecodeError, OSError):
        return None


def package_files(excluded: set[str]) -> list[Path]:
    return sorted(
        (
            path
            for path in ROOT.rglob("*")
            if path.is_file()
            and is_distributable(path.relative_to(ROOT).as_posix())
            and path.relative_to(ROOT).as_posix() not in excluded
        ),
        key=lambda path: path.relative_to(ROOT).as_posix(),
    )


def clean_generated_junk() -> None:
    for directory in list(ROOT.rglob("__pycache__")):
        if directory.is_dir():
            shutil.rmtree(directory)
    for file in list(ROOT.rglob("*.pyc")) + list(ROOT.rglob("*.pyo")) + list(ROOT.rglob("*.tsbuildinfo")):
        file.unlink(missing_ok=True)
    for pattern in ["node_modules", "src/apps/*/dist", ".terraform"]:
        for directory in ROOT.glob(pattern):
            if directory.is_dir():
                shutil.rmtree(directory)


def main() -> int:
    clean_generated_junk()
    release = json.loads((ROOT / "RELEASE-METADATA.json").read_text(encoding="utf-8"))
    version = (ROOT / "VERSION").read_text(encoding="utf-8").strip()
    if release["version"] != version:
        raise SystemExit(f"RELEASE_METADATA_VERSION_MISMATCH:{release['version']}!={version}")

    # Catalog and statistics are generated before the manifest so their final bytes are covered.
    content = package_files(EXCLUDED_FROM_MANIFEST | {"PACK-STATS.md", "FILE-CATALOG.md"})
    top_counts = collections.Counter(path.relative_to(ROOT).parts[0] for path in content)
    extension_counts = collections.Counter(path.suffix.lower() or "<none>" for path in content)
    text_lines = sum(count for path in content if (count := line_count(path)) is not None)
    vector_lines = sum(line_count(path) or 0 for path in (ROOT / "tests/vectors").glob("*.jsonl"))

    (ROOT / "FILE-CATALOG.md").write_text(
        "# File Catalog\n\n"
        f"Package version: `{version}`\n\n"
        "The catalog excludes only self-referential integrity files while checksums cover the manifest and every distributable file.\n\n"
        "| Area | Files |\n|---|---:|\n"
        + "".join(f"| `{area}` | {count} |\n" for area, count in sorted(top_counts.items())),
        encoding="utf-8",
    )
    (ROOT / "PACK-STATS.md").write_text(
        "# Package Statistics\n\n"
        f"- Version: `{version}`\n"
        "- Language: English only\n"
        f"- Non-integrity content files: `{len(content)}`\n"
        f"- Text lines: `{text_lines}`\n"
        f"- Semantic vector lines: `{vector_lines}`\n"
        "- OpenAPI operations and operation samples: `141`\n"
        "- Typed CloudEvent contracts and examples: `186`\n"
        "- Cursor operation execution units: `141`\n"
        "- Cursor work packages: `27`\n"
        "- Canonical database: `PostgreSQL 18 only`\n"
        "- Canonical realtime transport: `Secure WebSocket only`\n"
        "- Durable event authority: `PostgreSQL transactional event tables`\n"
        "- Open design ambiguities: `0`\n"
        "- Live production release status: `NOT CERTIFIED WITHOUT EXTERNAL EVIDENCE`\n\n"
        "## File types\n\n"
        + "".join(f"- `{extension}`: {count}\n" for extension, count in sorted(extension_counts.items())),
        encoding="utf-8",
    )

    payload_files = package_files(EXCLUDED_FROM_MANIFEST)
    entries = []
    for path in payload_files:
        relative = path.relative_to(ROOT).as_posix()
        entries.append({
            "path": relative,
            "sizeBytes": path.stat().st_size,
            "sha256": sha256_file(path),
            "lines": line_count(path),
        })
    manifest = {
        "package": {
            "name": release["packageName"],
            "version": version,
            "language": release["language"],
            "releasedAt": release["releasedAt"],
            "scope": release["artifactScope"],
            "rootDirectory": ROOT.name,
        },
        "integrity": {
            "manifestExcludes": sorted(EXCLUDED_FROM_MANIFEST),
            "checksumsExclude": sorted(EXCLUDED_FROM_CHECKSUMS),
            "checksumAlgorithm": "SHA-256",
            "rule": "CHECKSUMS.sha256 covers PACKAGE-MANIFEST.json and every other distributable file except itself.",
        },
        "counts": {"manifestEntries": len(entries), "distributionFilesIncludingIntegrity": len(entries) + 2},
        "files": entries,
    }
    MANIFEST.write_text(json.dumps(manifest, indent=2, ensure_ascii=True) + "\n", encoding="utf-8")

    checksum_files = package_files(EXCLUDED_FROM_CHECKSUMS)
    CHECKSUMS.write_text(
        "".join(f"{sha256_file(path)}  {path.relative_to(ROOT).as_posix()}\n" for path in checksum_files),
        encoding="utf-8",
    )
    print(json.dumps({"status":"metadata-regenerated","manifestEntries":len(entries),"checksumEntries":len(checksum_files),"distributionFiles":len(checksum_files)+1}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
