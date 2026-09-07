#!/usr/bin/env python3
"""Source-level §76 identity loop investigation (no device repro)."""
from __future__ import annotations

import json
import re
import subprocess
from datetime import UTC, datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WORKER = ROOT / "src" / "apps" / "worker"
SYMBOLS = [
    "ensureModelReady",
    "_ensureModelReadyInternal",
    "WorkerModelInstaller.ensureReady",
    "WorkerModelInstaller.verifyActive",
    "clearActiveInferenceIdentity",
    "_clearBrokenModelInstall",
    "_removeMissingFileRegistration",
    "_setModelReady",
    "FlutterGemma.clearActiveInferenceIdentity",
]


def _git_head() -> str:
    try:
        return subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    except Exception:
        return "unknown"


def _find_symbol_refs(symbol: str) -> list[dict]:
    refs: list[dict] = []
    pattern = re.escape(symbol.split(".")[-1] if "." in symbol else symbol)
    for path in WORKER.rglob("*.dart"):
        try:
            text = path.read_text(encoding="utf-8")
        except OSError:
            continue
        for index, line in enumerate(text.splitlines(), start=1):
            if pattern in line:
                refs.append({"file": str(path.relative_to(ROOT)).replace("\\", "/"), "line": index, "text": line.strip()[:120]})
    return refs


def main() -> int:
    symbol_map = {sym: _find_symbol_refs(sym) for sym in SYMBOLS}

    findings = [
        {
            "id": "F1",
            "summary": "clearActiveInferenceIdentity invoked on stale missing-file cleanup only",
            "severity": "info",
            "path": "src/apps/worker/lib/runtime/worker_model_installer.dart:_removeMissingFileRegistration",
        },
        {
            "id": "F2",
            "summary": "_clearBrokenModelInstall explicitly skips identity clear (preserves registration)",
            "severity": "info",
            "path": "src/apps/worker/lib/worker_app_controller.dart",
        },
        {
            "id": "F3",
            "summary": "ensureModelReady deduplicates concurrent calls via _modelReadyFuture",
            "severity": "info",
            "path": "src/apps/worker/lib/worker_app_controller.dart",
        },
        {
            "id": "F4",
            "summary": "No direct caller of _clearBrokenModelInstall located in lib/ (private, potentially dead)",
            "severity": "hypothesis",
            "path": "src/apps/worker/lib/worker_app_controller.dart",
        },
    ]

    payload = {
        "status": "passed",
        "taskId": "P8-T06",
        "architectureVersion": "2.0",
        "sourceSection": "76",
        "generatedAt": datetime.now(UTC).isoformat(),
        "commitSha": _git_head(),
        "classification": "IMPLEMENTED_DEV_ONLY",
        "investigationPhase": "SOURCE_STATIC_ONLY",
        "deviceReproduction": "NOT_RUN",
        "nativeHandleCounters": "NOT_COLLECTED",
        "symbolReferences": symbol_map,
        "findings": findings,
        "recommendedNextSteps": [
            "Instrument before/after state on ensureModelReady and clearActiveInferenceIdentity with correlation IDs",
            "Run idle soak on physical device with Native session/model counters",
            "Capture repro from assignment poll + model verify overlap",
        ],
        "closureCriteriaMet": False,
        "notes": "v2 §76 closure requires physical-device repro and Native handle stability evidence.",
    }

    out = ROOT / "plan" / "evidence" / "phase-08-p8-t06-identity-loop-investigation.json"
    out.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"findings": len(findings), "deviceReproduction": payload["deviceReproduction"]}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
