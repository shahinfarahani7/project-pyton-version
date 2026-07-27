from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

PATTERNS: tuple[tuple[str, re.Pattern[str]], ...] = (
    ("stripe_live_key", re.compile(r"sk_live_[0-9a-zA-Z]{8,}")),
    ("aws_access_key", re.compile(r"AKIA[0-9A-Z]{16}")),
    ("private_key_block", re.compile(r"-----BEGIN (?:RSA |EC )?PRIVATE KEY-----")),
    ("hardcoded_password", re.compile(r"(?i)(password|passwd|secret)\s*=\s*['\"][^'\"]{8,}['\"]")),
)

SCAN_ROOTS = (
    ROOT / "src" / "backend" / "edgemint",
    ROOT / "src" / "backend" / "tests",
    ROOT / "tests",
    ROOT / "tools",
)

ALLOWLIST_PATHS = frozenset(
    {
        "tools/run_postgresql_migrations.sh",
    }
)

ALLOWLIST_TOKENS = (
    "sk_live",
    "whsec_test_fixture",
    "whsec_integration_fixture",
)


def scan_file(path: Path) -> list[str]:
    rel = str(path.relative_to(ROOT)).replace("\\", "/")
    if rel in ALLOWLIST_PATHS:
        return []
    findings: list[str] = []
    try:
        text = path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        return findings
    for line_no, line in enumerate(text.splitlines(), 1):
        if any(token in line for token in ALLOWLIST_TOKENS):
            continue
        for name, pattern in PATTERNS:
            if pattern.search(line):
                findings.append(f"{rel}:{line_no}: {name}")
    return findings


def main() -> int:
    findings: list[str] = []
    for root in SCAN_ROOTS:
        if not root.exists():
            continue
        for path in root.rglob("*"):
            if path.suffix not in {".py", ".ts", ".tsx", ".js", ".json", ".yaml", ".yml", ".sh", ".env"}:
                continue
            if "node_modules" in path.parts:
                continue
            findings.extend(scan_file(path))
    report = {"critical": len(findings), "high": 0, "findings": findings[:50]}
    print(report)
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main())
