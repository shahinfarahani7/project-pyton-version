#!/usr/bin/env python3
"""Verify static envelope vs per-input ExecutionAllocation artifacts for P8-A05 / T05."""

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
        "sql": ROOT / "database/sql/029_task_execution_allocations.sql",
        "service": ROOT / "src/backend/edgemint/routing/execution_allocation.py",
        "admissionWiring": ROOT / "src/backend/edgemint/tasks/admission.py",
        "atomicWiring": ROOT / "src/backend/edgemint/routing/atomic_assignment.py",
        "envelopeRegistry": ROOT / "src/backend/edgemint/routing/envelope_registry.py",
        "executionPlanResolver": ROOT / "src/backend/edgemint/routing/execution_plan_resolver.py",
        "backendTests": ROOT / "src/backend/tests/routing/test_execution_allocation.py",
        "envelopeCatalog": ROOT / "dsl/catalog/resource-envelopes/text-summarize.yaml",
    }
    for label, path in artifacts.items():
        if not path.is_file():
            errors.append(f"missing artifact ({label}): {path.relative_to(ROOT)}")

    sql = artifacts["sql"].read_text(encoding="utf-8") if artifacts["sql"].is_file() else ""
    for token in (
        "task_execution_allocations",
        "execution_allocation_id",
        "UQ_task_execution_allocations_task_run",
        "stage_peaks_json",
    ):
        if token not in sql:
            errors.append(f"SQL missing token: {token}")

    service = (
        artifacts["service"].read_text(encoding="utf-8")
        if artifacts["service"].is_file()
        else ""
    )
    for token in (
        "derive_execution_allocation",
        "ExecutionAllocationSpec",
        "create_for_task_run",
        "load_vector_for_attempt",
    ):
        if token not in service:
            errors.append(f"service missing token: {token}")

    backend_test = subprocess.run(
        [sys.executable, "-m", "pytest", str(artifacts["backendTests"]), "-q"],
        cwd=ROOT / "src/backend",
        capture_output=True,
        text=True,
    )
    backend_passed = backend_test.returncode == 0
    if not backend_passed:
        errors.append("backend pytest failed for test_execution_allocation.py")
        errors.append(backend_test.stdout[-1500:])
        errors.append(backend_test.stderr[-1500:])

    evidence = {
        "status": "passed" if not errors else "failed",
        "taskId": "P8-A05",
        "auditId": "A05",
        "acceptanceCase": "T05",
        "architectureVersion": "2.0",
        "sourceSections": ["12", "12.1", "13", "20", "60"],
        "generatedAt": datetime.now(UTC).isoformat(),
        "commitSha": _git_sha(),
        "classification": "IMPLEMENTED_DEV_ONLY",
        "artifacts": {k: str(v.relative_to(ROOT)).replace("\\", "/") for k, v in artifacts.items()},
        "t05Scenario": {
            "title": "Same Revision 300 vs 30k tokens; stage demand increases",
            "staticEnvelopeIndependentOfInput": backend_passed,
            "allocationScalesWithTokensAndPlan": backend_passed,
            "assignmentReferencesAllocation": "wired_in_atomic_assignment.py",
            "integrationHarness": "NOT_RUN",
        },
        "gaps": [
            "T05 end-to-end admission→assignment integration harness NOT_RUN",
            "create_revision path does not yet mint TaskRun/allocation",
            "OpenAPI assignment payload sync for executionAllocationId pending",
        ],
        "errors": errors,
    }

    out_path = ROOT / "plan/evidence/phase-08-p8-a05-execution-allocation.json"
    out_path.write_text(json.dumps(evidence, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(evidence, indent=2))
    return 0 if evidence["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
