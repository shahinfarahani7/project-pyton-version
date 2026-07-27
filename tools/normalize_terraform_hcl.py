#!/usr/bin/env python3
"""Normalize compact HCL block openers so Terraform CLI can parse AWS modules."""
from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TF_DIR = ROOT / "deploy" / "terraform" / "aws"


def split_block_openers(text: str) -> str:
    lines = text.splitlines()
    changed = True
    while changed:
        changed = False
        new_lines: list[str] = []
        for line in lines:
            stripped = line.rstrip()
            if stripped.endswith("{}") or stripped.endswith("{}"):
                new_lines.append(line)
                continue
            match = re.match(r"^(\s*\S.*?\{)\s+(\S.+)$", stripped)
            if match and not stripped.endswith("}"):
                indent = re.match(r"^(\s*)", line).group(1)
                new_lines.append(match.group(1))
                new_lines.append(f"{indent}  {match.group(2)}")
                changed = True
            else:
                new_lines.append(line)
        lines = new_lines
    return "\n".join(lines) + "\n"


def main() -> int:
    for path in sorted(TF_DIR.glob("*.tf")):
        path.write_text(split_block_openers(path.read_text(encoding="utf-8")), encoding="utf-8")
    result = subprocess.run(
        ["terraform", "fmt", "-recursive", str(TF_DIR)],
        cwd=ROOT,
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        print(result.stderr or result.stdout)
        return result.returncode
    validate = subprocess.run(
        ["terraform", "-chdir=deploy/terraform/aws", "validate"],
        cwd=ROOT,
        check=False,
        capture_output=True,
        text=True,
    )
    print(validate.stdout or validate.stderr)
    return validate.returncode


if __name__ == "__main__":
    sys.exit(main())
