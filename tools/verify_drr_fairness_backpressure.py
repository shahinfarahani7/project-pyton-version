#!/usr/bin/env python3
"""Verify DRR fairness, backpressure and operating signals for P8-A19 / T19."""

from __future__ import annotations

import json
import subprocess
import sys
from datetime import UTC, datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def _git_sha() -> str:
    try:
        return (
            subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True)
            .strip()
        )
    except Exception:
        return "unknown"


def main() -> int:
    errors: list[str] = []
    artifacts = {
        "admissionBackpressurePolicyDsl": ROOT
        / "dsl/policies/scheduling/workspace-admission-backpressure-v1.yaml",
        "workspaceDrrModule": ROOT / "src/backend/edgemint/routing/workspace_drr.py",
        "admissionBackpressureModule": ROOT
        / "src/backend/edgemint/routing/admission_backpressure.py",
        "operatingSignalsModule": ROOT / "src/backend/edgemint/routing/operating_signals.py",
        "fairQueueModule": ROOT / "src/backend/edgemint/routing/fair_queue.py",
        "fairQueueMetricsModule": ROOT / "src/backend/edgemint/routing/fair_queue_metrics.py",
        "routerService": ROOT / "src/backend/edgemint/routing/service.py",
        "backendTests": ROOT / "src/backend/tests/routing/test_drr_fairness_backpressure.py",
        "fairQueueTests": ROOT / "src/backend/tests/routing/test_fair_queue_ordering.py",
        "fairQueueMetricsTests": ROOT / "src/backend/tests/routing/test_fair_queue_metrics.py",
        "p4QueueEvidence": ROOT / "plan/evidence/phase-04-p4-t06-queue-selection-ordering.json",
        "capacityDashboard": ROOT / "deploy/observability/capacity-dashboard.yaml",
    }
    for label, path in artifacts.items():
        if not path.is_file():
            errors.append(f"missing artifact ({label}): {path.relative_to(ROOT)}")

    policy = (
        artifacts["admissionBackpressurePolicyDsl"].read_text(encoding="utf-8")
        if artifacts["admissionBackpressurePolicyDsl"].is_file()
        else ""
    )
    for token in (
        "workspace_deficit_round_robin",
        "maxQueuedTasksPerWorkspace",
        "VALIDATION_BACKPRESSURE",
        "operatingSignals",
    ):
        if token not in policy:
            errors.append(f"admission policy missing token: {token}")

    router = (
        artifacts["routerService"].read_text(encoding="utf-8")
        if artifacts["routerService"].is_file()
        else ""
    )
    for token in (
        "evaluate_admission_backpressure",
        "collect_operating_signals",
        "compute_queue_cost_units",
    ):
        if token not in router:
            errors.append(f"router service missing hook: {token}")

    backend_test = subprocess.run(
        [
            sys.executable,
            "-m",
            "pytest",
            str(artifacts["backendTests"]),
            str(artifacts["fairQueueTests"]),
            str(artifacts["fairQueueMetricsTests"]),
            "-q",
        ],
        cwd=ROOT / "src/backend",
        capture_output=True,
        text=True,
    )
    backend_passed = backend_test.returncode == 0
    if not backend_passed:
        errors.append("backend pytest failed for DRR fairness/backpressure")
        errors.append(backend_test.stdout[-1500:])
        errors.append(backend_test.stderr[-1500:])

    evidence = {
        "status": "passed" if not errors else "failed",
        "taskId": "P8-A19",
        "auditId": "A19",
        "acceptanceCase": "T19",
        "architectureVersion": "2.0",
        "sourceSections": ["9", "31", "36", "40", "73"],
        "generatedAt": datetime.now(UTC).isoformat(),
        "commitSha": _git_sha(),
        "classification": "IMPLEMENTED_DEV_ONLY",
        "artifacts": {
            k: str(v.relative_to(ROOT)).replace("\\", "/") for k, v in artifacts.items()
        },
        "t19Scenario": {
            "title": "Competing workspaces; saturated queue/upload/validator; control path stress",
            "drrDeficitAccounting": "workspace_drr.py" in policy or artifacts["workspaceDrrModule"].is_file(),
            "distinctBackpressureReasons": "VALIDATION_BACKPRESSURE" in policy,
            "operatingSignalsWired": "collect_operating_signals" in router,
            "smallTaskStarvationMitigated": backend_passed,
            "saturationHarness": "NOT_RUN",
        },
        "gaps": [
            "T19 multi-workspace saturation load harness NOT_RUN",
            "Reconciler SLO proof under pipeline backpressure NOT_RUN",
            "Production alert wiring for operating signals NOT_RUN",
        ],
        "errors": errors,
    }

    out_path = ROOT / "plan/evidence/phase-08-p8-a19-drr-fairness-backpressure.json"
    out_path.write_text(json.dumps(evidence, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(evidence, indent=2))
    return 0 if evidence["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
