#!/usr/bin/env python3
from __future__ import annotations
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PREFIXES = "docs|dsl|contracts|database|tests|tools|reference|infra|build"
BACKTICK_PATH = re.compile(r"`((?:" + PREFIXES + r")/[^`\n]+?)`")
MD_LINK = re.compile(r"\[[^\]]+\]\(([^)]+)\)")
errors: list[str] = []
checked = 0

for path in sorted(ROOT.rglob("*.md")):
    if "archive" in path.parts:
        continue
    checked += 1
    text = path.read_text(encoding="utf-8")
    if "tools/validate_all.py" in text:
        errors.append(f"{path.relative_to(ROOT)}: references nonexistent tools/validate_all.py")
    for raw in BACKTICK_PATH.findall(text):
        target_text = raw.rstrip(".,;:)")
        # Skip wildcard/example fragments and API-like placeholders.
        if any(ch in target_text for ch in "*{}<>"):
            continue
        target = ROOT / target_text
        if not target.exists():
            errors.append(f"{path.relative_to(ROOT)}: missing referenced path {target_text}")
    for raw in MD_LINK.findall(text):
        if raw.startswith(("http://", "https://", "mailto:", "#")):
            continue
        target_text = raw.split("#", 1)[0]
        if not target_text:
            continue
        target = (path.parent / target_text).resolve()
        try:
            target.relative_to(ROOT.resolve())
        except ValueError:
            errors.append(f"{path.relative_to(ROOT)}: link escapes package {raw}")
            continue
        if not target.exists():
            errors.append(f"{path.relative_to(ROOT)}: broken local link {raw}")

print(json.dumps({"markdownFiles": checked, "errors": errors}, ensure_ascii=False, indent=2))
sys.exit(1 if errors else 0)
