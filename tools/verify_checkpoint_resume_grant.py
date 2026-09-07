#!/usr/bin/env python3
"""Verify immutable checkpoint provenance and ResumeGrant for P8-A12 / T12."""

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
        "sqlMigration": ROOT / "database/sql/034_checkpoint_resume_grants.sql",
        "checkpointResumeService": ROOT / "src/backend/edgemint/workers/checkpoint_resume.py",
        "assignmentsWiring": ROOT / "src/backend/edgemint/workers/assignments.py",
        "workerResumeGrant": ROOT / "src/apps/worker/lib/runtime/resume_grant.dart",
        "workerCheckpointManager": ROOT / "src/apps/worker/lib/runtime/checkpoint_manager.dart",
        "failureEvidence": ROOT / "src/apps/worker/lib/runtime/failure_evidence.dart",
        "backendTests": ROOT / "src/backend/tests/workers/test_checkpoint_resume.py",
        "workerTests": ROOT / "src/apps/worker/test/runtime/resume_grant_test.dart",
        "checkpointManagerTests": ROOT / "src/apps/worker/test/runtime/checkpoint_manager_test.dart",
    }
    for label, path in artifacts.items():
        if not path.is_file():
            errors.append(f"missing artifact ({label}): {path.relative_to(ROOT)}")

    sql = (
        artifacts["sqlMigration"].read_text(encoding="utf-8")
        if artifacts["sqlMigration"].is_file()
        else ""
    )
    for token in (
        "checkpoint_manifests",
        "resume_grants",
        "issue_resume_grant",
        "UQ_checkpoint_manifest_chunk",
    ):
        if token not in sql:
            errors.append(f"SQL migration missing token: {token}")

    service = (
        artifacts["checkpointResumeService"].read_text(encoding="utf-8")
        if artifacts["checkpointResumeService"].is_file()
        else ""
    )
    for token in (
        "evaluate_resume_compatibility",
        "publish_manifest",
        "issue_grant",
        "ResumeCompatibilityDecision",
    ):
        if token not in service:
            errors.append(f"checkpoint resume service missing token: {token}")

    assignments = (
        artifacts["assignmentsWiring"].read_text(encoding="utf-8")
        if artifacts["assignmentsWiring"].is_file()
        else ""
    )
    if "checkpoint_resume.publish_manifest" not in assignments:
        errors.append("assignments missing checkpoint manifest publish wiring")

    manager = (
        artifacts["workerCheckpointManager"].read_text(encoding="utf-8")
        if artifacts["workerCheckpointManager"].is_file()
        else ""
    )
    for token in (
        "ResumeGrant?",
        "ResumeGrantValidator.evaluate",
        "producerAssignmentId",
    ):
        if token not in manager:
            errors.append(f"checkpoint manager missing token: {token}")

    failure = (
        artifacts["failureEvidence"].read_text(encoding="utf-8")
        if artifacts["failureEvidence"].is_file()
        else ""
    )
    if "checkpointIncompatible" not in failure:
        errors.append("failure evidence missing checkpointIncompatible mapping")

    backend_test = subprocess.run(
        [sys.executable, "-m", "pytest", str(artifacts["backendTests"]), "-q"],
        cwd=ROOT / "src/backend",
        capture_output=True,
        text=True,
    )
    backend_passed = backend_test.returncode == 0
    if not backend_passed:
        errors.append("backend pytest failed for checkpoint resume tests")
        errors.append(backend_test.stdout[-1500:])
        errors.append(backend_test.stderr[-1500:])

    worker_passed = False
    worker_skipped = False
    try:
        worker_test = subprocess.run(
            [
                "flutter",
                "test",
                str(artifacts["workerTests"]),
                str(artifacts["checkpointManagerTests"]),
            ],
            cwd=ROOT / "src/apps/worker",
            capture_output=True,
            text=True,
        )
        worker_passed = worker_test.returncode == 0
        if not worker_passed:
            errors.append("flutter test failed for resume grant / checkpoint manager")
            if worker_test.stderr.strip():
                errors.append(worker_test.stderr[-1000:])
    except FileNotFoundError:
        worker_skipped = True

    evidence = {
        "status": "passed" if not errors else "failed",
        "taskId": "P8-A12",
        "auditId": "A12",
        "acceptanceCase": "T12",
        "architectureVersion": "2.0",
        "sourceSections": ["28", "46", "49", "61"],
        "generatedAt": datetime.now(UTC).isoformat(),
        "commitSha": _git_sha(),
        "classification": "IMPLEMENTED_DEV_ONLY",
        "artifacts": {
            k: str(v.relative_to(ROOT)).replace("\\", "/") for k, v in artifacts.items()
        },
        "t12Scenario": {
            "title": "Cross-Worker Resume; incompatible checkpoint/model space",
            "manifestPublishOnCheckpoint": "checkpoint_resume.publish_manifest" in assignments,
            "compatibilityEvaluator": backend_passed,
            "workerResumeGrantValidator": (
                worker_passed if not worker_skipped else "SKIPPED_FLUTTER_UNAVAILABLE"
            ),
            "producerFenceProvenanceOnly": "producerFenceToken" in manager,
            "integrationHarness": "NOT_RUN",
        },
        "gaps": [
            "T12 cross-Worker reassignment end-to-end integration harness NOT_RUN",
            "Incomplete checkpoint rejection on device NOT_RUN",
            "Model-space / execution-plan mismatch negative E2E NOT_RUN",
        ],
        "errors": errors,
    }

    out_path = ROOT / "plan/evidence/phase-08-p8-a12-checkpoint-resume-grant.json"
    out_path.write_text(json.dumps(evidence, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(evidence, indent=2))
    return 0 if evidence["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
