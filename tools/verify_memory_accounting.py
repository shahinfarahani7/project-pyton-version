#!/usr/bin/env python3
"""Verify resident/base/peak memory accounting artifacts for P8-A04 / T04."""

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
        "sql": ROOT / "database/sql/028_worker_memory_accounting.sql",
        "service": ROOT / "src/backend/edgemint/routing/memory_accounting.py",
        "reservationWiring": ROOT / "src/backend/edgemint/routing/resource_reservations.py",
        "heartbeatWiring": ROOT / "src/backend/edgemint/workers/enrollment.py",
        "workerModule": ROOT / "src/apps/worker/lib/runtime/memory_accounting.dart",
        "heartbeatTelemetry": ROOT / "src/apps/worker/lib/runtime/worker_heartbeat_telemetry.dart",
        "backendTests": ROOT / "src/backend/tests/routing/test_memory_accounting.py",
        "workerTests": ROOT / "src/apps/worker/test/runtime/memory_accounting_test.dart",
        "reservationLedger": ROOT / "database/sql/018_worker_resource_reservations.sql",
    }
    for label, path in artifacts.items():
        if not path.is_file():
            errors.append(f"missing artifact ({label}): {path.relative_to(ROOT)}")

    sql = artifacts["sql"].read_text(encoding="utf-8") if artifacts["sql"].is_file() else ""
    for token in (
        "worker_memory_commitments",
        "upsert_worker_memory_commitment",
        "release_worker_memory_commitment_by_assignment",
        "commitment_kind IN ('base', 'resident', 'task_peak', 'transfer')",
    ):
        if token not in sql:
            errors.append(f"SQL missing token: {token}")

    backend_test = subprocess.run(
        [sys.executable, "-m", "pytest", str(artifacts["backendTests"]), "-q"],
        cwd=ROOT / "src/backend",
        capture_output=True,
        text=True,
    )
    backend_passed = backend_test.returncode == 0
    if not backend_passed:
        errors.append("backend pytest failed for test_memory_accounting.py")
        errors.append(backend_test.stdout[-1500:])
        errors.append(backend_test.stderr[-1500:])

    worker_test_status = "SKIPPED_NO_FLUTTER"
    try:
        worker_test = subprocess.run(
            ["flutter", "test", str(artifacts["workerTests"])],
            cwd=ROOT / "src/apps/worker",
            capture_output=True,
            text=True,
        )
        if worker_test.returncode == 0:
            worker_test_status = "PASSED"
        elif worker_test.returncode == 69:
            worker_test_status = "SKIPPED_NETWORK"
            errors.append("flutter test skipped: pub.dev/network unavailable")
        else:
            worker_test_status = "FAILED"
            errors.append("flutter test failed for memory_accounting_test.dart")
    except FileNotFoundError:
        errors.append("flutter CLI unavailable; memory_accounting_test.dart not executed")

    hard_errors = [
        error
        for error in errors
        if not error.startswith("flutter test skipped") and "flutter CLI unavailable" not in error
    ]

    evidence = {
        "status": "passed" if not hard_errors else "failed",
        "taskId": "P8-A04",
        "auditId": "A04",
        "acceptanceCase": "T04",
        "architectureVersion": "2.0",
        "sourceSections": ["12", "16", "19", "24", "40"],
        "generatedAt": datetime.now(UTC).isoformat(),
        "commitSha": _git_sha(),
        "classification": "IMPLEMENTED_DEV_ONLY",
        "artifacts": {k: str(v.relative_to(ROOT)).replace("\\", "/") for k, v in artifacts.items()},
        "t04Scenario": {
            "title": "Scheduler race; warm model; snapshot reconciliation",
            "residentDedupUnitProof": backend_passed,
            "warmModelRetainedAfterTaskPeakRelease": backend_passed,
            "workerMemoryAccountingTest": worker_test_status,
            "integrationHarness": "NOT_RUN",
        },
        "gaps": [
            "T04 dual-scheduler race integration harness NOT_RUN",
            "Transfer memory bucket not yet populated from telemetry",
            "OpenAPI/heartbeat schema sync for memoryAccounting pending",
        ],
        "errors": errors,
    }

    out_path = ROOT / "plan/evidence/phase-08-p8-a04-memory-accounting.json"
    out_path.write_text(json.dumps(evidence, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(evidence, indent=2))
    return 0 if evidence["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
