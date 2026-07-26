#!/usr/bin/env python3
"""Windows-compatible generated-code drift check."""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main() -> None:
    subprocess.run([sys.executable, "tools/generate_contracts.py"], cwd=ROOT, check=True)
    result = subprocess.run(
        ["git", "diff", "--quiet", "--", "generated"],
        cwd=ROOT,
        check=False,
    )
    if result.returncode != 0:
        diff = subprocess.run(
            ["git", "diff", "--stat", "--", "generated"],
            cwd=ROOT,
            check=False,
            capture_output=True,
            text=True,
        )
        sys.stderr.write(diff.stdout)
        sys.stderr.write("GENERATED_DRIFT_DETECTED\n")
        sys.exit(1)
    print(json.dumps({"status": "passed", "drift": False}))


if __name__ == "__main__":
    main()
