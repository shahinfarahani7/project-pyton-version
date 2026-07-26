"""Security contract tests executed from repository root."""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def test_openapi_authorization_coverage_passes() -> None:
    result = subprocess.run(
        [sys.executable, "tools/test_openapi_authorization_coverage.py"],
        cwd=ROOT,
        check=False,
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, result.stdout + result.stderr
