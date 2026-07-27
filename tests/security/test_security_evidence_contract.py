"""Security evidence contract test for WP-220."""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def test_security_evidence_passes_validation() -> None:
    result = subprocess.run(
        [sys.executable, "tools/validate_security_evidence.py", "evidence/actual/security"],
        cwd=ROOT,
        check=False,
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, result.stdout + result.stderr
