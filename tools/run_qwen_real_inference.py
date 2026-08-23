#!/usr/bin/env python3
"""Fail-closed real Qwen probe; never substitutes a mock for model evidence."""
from __future__ import annotations

import argparse
import hashlib
import json
import shutil
from pathlib import Path

EXPECTED_SHA256 = "555579ff2f4fd13379abe69c1c3ab5200f7338bc92471557f1d6614a6e5ab0b4"


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(8 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", type=Path, default=Path("models/Qwen3-0.6B.litertlm"))
    args = parser.parse_args()
    blockers = []
    if not args.model.is_file():
        blockers.append("QWEN_LITERTLM_ARTIFACT_MISSING")
    elif sha256_file(args.model) != EXPECTED_SHA256:
        blockers.append("QWEN_ARTIFACT_DIGEST_MISMATCH")
    cli = shutil.which("litert-lm")
    if cli is None:
        blockers.append("LITERT_LM_RUNTIME_MISSING")
    if blockers:
        print(json.dumps({"status": "blocked", "realModelExecuted": False, "blockers": blockers}, indent=2))
        return 2
    print(json.dumps({"status": "ready", "realModelExecuted": False, "reason": "invoke on ARM device via Worker integration test"}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
