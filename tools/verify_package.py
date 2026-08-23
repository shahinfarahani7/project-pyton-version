#!/usr/bin/env python3
"""Verify complete distribution integrity and manifest/checksum agreement."""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CHECKSUMS = ROOT / "CHECKSUMS.sha256"
MANIFEST = ROOT / "PACKAGE-MANIFEST.json"
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


def checksum_rows() -> list[tuple[str, str]]:
    rows=[]
    for line_number, raw in enumerate(CHECKSUMS.read_text(encoding="utf-8").splitlines(),1):
        if not raw.strip(): continue
        if "  " not in raw: raise ValueError(f"invalid checksum line {line_number}")
        digest,relative=raw.split("  ",1)
        if len(digest)!=64 or any(char not in "0123456789abcdef" for char in digest): raise ValueError(f"invalid checksum digest line {line_number}")
        if relative.startswith("/") or "\\" in relative or ".." in Path(relative).parts: raise ValueError(f"unsafe checksum path line {line_number}:{relative}")
        rows.append((digest,relative))
    return rows


def main() -> int:
    parser=argparse.ArgumentParser(); parser.add_argument("--skip-checksums-if-absent",action="store_true"); args=parser.parse_args()
    errors=[]
    if not CHECKSUMS.exists():
        if args.skip_checksums_if_absent:
            print(json.dumps({"status":"skipped","reason":"CHECKSUMS.sha256 absent"})); return 0
        errors.append("CHECKSUMS.sha256 is missing"); rows=[]
    else:
        try: rows=checksum_rows()
        except Exception as exc: errors.append(str(exc)); rows=[]
    listed={}
    for digest,relative in rows:
        if relative in listed: errors.append(f"duplicate checksum entry:{relative}"); continue
        listed[relative]=digest
        target=ROOT/relative
        try: target.resolve().relative_to(ROOT.resolve())
        except ValueError: errors.append(f"checksum path escapes package:{relative}"); continue
        if not target.is_file() or target.is_symlink(): errors.append(f"missing or symlink checksum target:{relative}"); continue
        if sha256_file(target)!=digest: errors.append(f"checksum mismatch:{relative}")
    actual={
        p.relative_to(ROOT).as_posix()
        for p in ROOT.rglob("*")
        if p.is_file() and p != CHECKSUMS and is_distributable(p.relative_to(ROOT).as_posix())
    }
    if set(listed)!=actual:
        for relative in sorted(actual-set(listed)): errors.append(f"unlisted package file:{relative}")
        for relative in sorted(set(listed)-actual): errors.append(f"checksum entry has no file:{relative}")
    if not MANIFEST.exists():
        errors.append("PACKAGE-MANIFEST.json is missing")
    else:
        try:
            manifest=json.loads(MANIFEST.read_text(encoding="utf-8"))
            if manifest.get("package",{}).get("name")!="EdgeMint-Production-Execution-Pack": errors.append("manifest package.name is invalid")
            entries=manifest.get("files")
            if not isinstance(entries,list): errors.append("manifest files must be an array"); entries=[]
            entry_paths=[]
            for entry in entries:
                if not isinstance(entry,dict) or not all(key in entry for key in ["path","sizeBytes","sha256"]): errors.append("manifest entry is incomplete"); continue
                relative=entry["path"]; entry_paths.append(relative); target=ROOT/relative
                if relative in {"PACKAGE-MANIFEST.json","CHECKSUMS.sha256"}: errors.append(f"self-referential manifest entry:{relative}"); continue
                if not target.is_file(): errors.append(f"manifest file missing:{relative}"); continue
                if target.stat().st_size!=entry["sizeBytes"]: errors.append(f"manifest size mismatch:{relative}")
                if sha256_file(target)!=entry["sha256"]: errors.append(f"manifest hash mismatch:{relative}")
            expected_manifest=actual-{"PACKAGE-MANIFEST.json"}
            if set(entry_paths)!=expected_manifest:
                for relative in sorted(expected_manifest-set(entry_paths)): errors.append(f"manifest missing file:{relative}")
                for relative in sorted(set(entry_paths)-expected_manifest): errors.append(f"manifest extra file:{relative}")
            if len(entry_paths)!=len(set(entry_paths)): errors.append("manifest contains duplicate paths")
            if manifest.get("counts",{}).get("manifestEntries")!=len(entry_paths): errors.append("manifest count mismatch")
        except Exception as exc: errors.append(f"manifest invalid:{exc}")
    result={"status":"passed" if not errors else "failed","checksumEntries":len(rows),"actualFilesExcludingChecksum":len(actual),"errors":errors}
    print(json.dumps(result,indent=2)); return 0 if not errors else 1


if __name__=="__main__": raise SystemExit(main())
