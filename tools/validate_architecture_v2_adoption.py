#!/usr/bin/env python3
"""Verify architecture v2 adoption: authority pointers, supersession, registries."""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
V1 = ROOT / "docs" / "EDGE-MINT-TARGET-ARCHITECTURE-v1.md"
V2 = ROOT / "docs" / "EDGE-MINT-TARGET-ARCHITECTURE-v2.md"
REGISTRY = ROOT / "plan" / "evidence" / "phase-08-p8-t03-acceptance-scenarios-registry.json"

CHECKS: dict[str, bool] = {}


def _contains(path: Path, needle: str) -> bool:
    return needle in path.read_text(encoding="utf-8")


CHECKS["v2_document_exists"] = V2.is_file()
CHECKS["v1_superseded_banner"] = _contains(V1, "SUPERSEDED") and _contains(V1, "EDGE-MINT-TARGET-ARCHITECTURE-v2.md")
CHECKS["start_here_points_to_v2"] = _contains(ROOT / "START-HERE.md", "EDGE-MINT-TARGET-ARCHITECTURE-v2.md")
CHECKS["plan_todo_points_to_v2"] = _contains(ROOT / "plan" / "TODO.md", "EDGE-MINT-TARGET-ARCHITECTURE-v2.md")
CHECKS["closure_checklist_points_to_v2"] = _contains(ROOT / "plan" / "closure-checklist.md", "EDGE-MINT-TARGET-ARCHITECTURE-v2.md")
CHECKS["canonical_decisions_v2"] = _contains(
    ROOT / "production" / "canonical-decisions.yaml",
    "architectureVersion: '2.0'",
)
CHECKS["acceptance_registry_exists"] = REGISTRY.is_file()
if REGISTRY.is_file():
    registry = json.loads(REGISTRY.read_text(encoding="utf-8"))
    CHECKS["acceptance_registry_24_cases"] = len(registry.get("cases", [])) == 24
else:
    CHECKS["acceptance_registry_24_cases"] = False

CHECKS["phase_8_file_exists"] = (ROOT / "plan" / "phases" / "phase-08-v2-audit-integration.md").is_file()
CHECKS["audit_matrix_v2_section"] = _contains(ROOT / "plan" / "audit-matrix.md", "v2 Audit Integration")

failed = [name for name, ok in CHECKS.items() if not ok]
for name, ok in CHECKS.items():
    print(f"{'PASS' if ok else 'FAIL'} {name}")
raise SystemExit(1 if failed else 0)
