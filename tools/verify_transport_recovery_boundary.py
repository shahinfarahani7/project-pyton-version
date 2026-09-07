#!/usr/bin/env python3
"""Verify local bounded Plan and transport recovery boundary for P8-A09 / T09."""

from __future__ import annotations

import json
import subprocess
import sys
from datetime import UTC, datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FORBIDDEN = (
    "LocalTaskSelector",
    "LocalRetryOrchestrator",
    "LocalReassignmentManager",
    "LocalCloudFallbackDecision",
)


def _git_sha() -> str:
    try:
        return (
            subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True)
            .strip()
        )
    except Exception:
        return "unknown"


def _forbidden_scheduler_audit() -> dict[str, object]:
    worker_lib = ROOT / "src/apps/worker/lib"
    lib_matches: list[str] = []
    for path in worker_lib.rglob("*.dart"):
        text = path.read_text(encoding="utf-8")
        for component in FORBIDDEN:
            if component in text:
                lib_matches.append(f"{path.relative_to(ROOT)}:{component}")
    return {
        "libMatches": lib_matches,
        "passed": len(lib_matches) == 0,
    }


def main() -> int:
    errors: list[str] = []
    artifacts = {
        "policyDsl": ROOT / "dsl/policies/worker/transport-recovery-boundary-v1.yaml",
        "sqlMigration": ROOT / "database/sql/033_assignment_transport_receipts.sql",
        "transportRecovery": ROOT / "src/backend/edgemint/workers/transport_recovery.py",
        "assignmentsWiring": ROOT / "src/backend/edgemint/workers/assignments.py",
        "workerJournal": ROOT / "src/apps/worker/lib/runtime/transport_recovery_journal.dart",
        "eventReporter": ROOT / "src/apps/worker/lib/runtime/assignment_event_reporter.dart",
        "backendTests": ROOT / "src/backend/tests/workers/test_transport_recovery.py",
        "workerTests": ROOT / "src/apps/worker/test/runtime/transport_recovery_journal_test.dart",
        "forbiddenAuditBaseline": ROOT / "plan/evidence/phase-03-p3-t20-forbidden-scheduler-audit.json",
    }
    for label, path in artifacts.items():
        if not path.is_file():
            errors.append(f"missing artifact ({label}): {path.relative_to(ROOT)}")

    policy_yaml = (
        artifacts["policyDsl"].read_text(encoding="utf-8")
        if artifacts["policyDsl"].is_file()
        else ""
    )
    for token in (
        "mustNotRerunInferenceOnLostAck: true",
        "forbiddenWorkerComponents:",
        "transportRecovery:",
    ):
        if token not in policy_yaml:
            errors.append(f"transport policy DSL missing token: {token}")

    assignments = (
        artifacts["assignmentsWiring"].read_text(encoding="utf-8")
        if artifacts["assignmentsWiring"].is_file()
        else ""
    )
    if "transport_recovery" not in assignments:
        errors.append("assignments missing transport_recovery wiring")
    if "progressAssignmentReplay" not in assignments:
        errors.append("assignments progress replay operation missing")

    forbidden = _forbidden_scheduler_audit()
    if not forbidden["passed"]:
        errors.append(f"forbidden scheduler components found in worker lib: {forbidden['libMatches']}")

    backend_test = subprocess.run(
        [sys.executable, "-m", "pytest", str(artifacts["backendTests"]), "-q"],
        cwd=ROOT / "src/backend",
        capture_output=True,
        text=True,
    )
    backend_passed = backend_test.returncode == 0
    if not backend_passed:
        errors.append("backend pytest failed for transport recovery tests")
        errors.append(backend_test.stdout[-1500:])
        errors.append(backend_test.stderr[-1500:])

    worker_passed = False
    worker_skipped = False
    try:
        worker_test = subprocess.run(
            ["flutter", "test", str(artifacts["workerTests"])],
            cwd=ROOT / "src/apps/worker",
            capture_output=True,
            text=True,
        )
        worker_passed = worker_test.returncode == 0
        if not worker_passed:
            errors.append("flutter test failed for transport journal")
            if worker_test.stderr.strip():
                errors.append(worker_test.stderr[-1000:])
    except FileNotFoundError:
        worker_skipped = True

    evidence = {
        "status": "passed" if not errors else "failed",
        "taskId": "P8-A09",
        "auditId": "A09",
        "acceptanceCase": "T09",
        "architectureVersion": "2.0",
        "sourceSections": ["2.4", "8", "14", "21", "43"],
        "generatedAt": datetime.now(UTC).isoformat(),
        "commitSha": _git_sha(),
        "classification": "IMPLEMENTED_DEV_ONLY",
        "artifacts": {k: str(v.relative_to(ROOT)).replace("\\", "/") for k, v in artifacts.items()},
        "t09Scenario": {
            "title": "Lost ACK/result retransmission vs unauthorized task retry",
            "transportReceiptDedup": backend_passed,
            "workerTransportJournal": (
                worker_passed if not worker_skipped else "SKIPPED_FLUTTER_UNAVAILABLE"
            ),
            "forbiddenSchedulerAbsentInLib": forbidden["passed"],
            "boundedPlanPolicyDocumented": "stageRetryRequiresSeparateServerAuthorization" in policy_yaml,
            "integrationHarness": "NOT_RUN",
        },
        "gaps": [
            "T09 lost-result-ACK end-to-end integration harness NOT_RUN",
            "Unauthorized local retry attempt negative E2E NOT_RUN",
            "Server-authorized plan stage cap enforcement on device NOT_RUN",
        ],
        "errors": errors,
    }

    out_path = ROOT / "plan/evidence/phase-08-p8-a09-transport-recovery-boundary.json"
    out_path.write_text(json.dumps(evidence, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(evidence, indent=2))
    return 0 if evidence["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
