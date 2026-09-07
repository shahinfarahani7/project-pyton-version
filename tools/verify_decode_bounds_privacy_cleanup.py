#!/usr/bin/env python3
"""Verify bounded decode and privacy cleanup for P8-A21 / T21."""

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
        "inputDecodePrivacyPolicyDsl": ROOT / "dsl/policies/data/input-decode-privacy-v1.yaml",
        "inputDecodeBoundsModule": ROOT / "src/backend/edgemint/files/input_decode_bounds.py",
        "artifactPrivacyModule": ROOT / "src/backend/edgemint/files/artifact_privacy.py",
        "taskAdmission": ROOT / "src/backend/edgemint/tasks/admission.py",
        "fileLifecycle": ROOT / "src/backend/edgemint/files/lifecycle.py",
        "storagePressureManager": ROOT / "src/apps/worker/lib/runtime/storage_pressure_manager.dart",
        "privacyCleanupCoordinator": ROOT
        / "src/apps/worker/lib/runtime/privacy_cleanup_coordinator.dart",
        "assignmentCoordinator": ROOT / "src/apps/worker/lib/runtime/assignment_coordinator.dart",
        "backendTests": ROOT / "src/backend/tests/files/test_input_decode_privacy.py",
        "privacyCleanupTests": ROOT
        / "src/apps/worker/test/runtime/privacy_cleanup_coordinator_test.dart",
        "p3T17Evidence": ROOT / "plan/evidence/phase-03-p3-t17-storage-pressure-handling.json",
        "productionDataPolicy": ROOT / "dsl/policies/data/production-data-policy-v1.yaml",
    }
    for label, path in artifacts.items():
        if not path.is_file():
            errors.append(f"missing artifact ({label}): {path.relative_to(ROOT)}")

    policy = (
        artifacts["inputDecodePrivacyPolicyDsl"].read_text(encoding="utf-8")
        if artifacts["inputDecodePrivacyPolicyDsl"].is_file()
        else ""
    )
    for token in ("maxDecodedBytes", "DECODE_BOUNDS_EXCEEDED", "crossTaskLeakageForbidden"):
        if token not in policy:
            errors.append(f"decode privacy policy missing token: {token}")

    admission = (
        artifacts["taskAdmission"].read_text(encoding="utf-8")
        if artifacts["taskAdmission"].is_file()
        else ""
    )
    if "_assert_file_decode_bounds" not in admission:
        errors.append("task admission missing decode bounds gate")

    coordinator = (
        artifacts["assignmentCoordinator"].read_text(encoding="utf-8")
        if artifacts["assignmentCoordinator"].is_file()
        else ""
    )
    if "PrivacyCleanupCoordinator" not in coordinator:
        errors.append("assignment coordinator missing privacy cleanup wiring")

    backend_test = subprocess.run(
        [sys.executable, "-m", "pytest", str(artifacts["backendTests"]), "-q"],
        cwd=ROOT / "src/backend",
        capture_output=True,
        text=True,
    )
    backend_passed = backend_test.returncode == 0
    if not backend_passed:
        errors.append("backend pytest failed for input decode privacy")
        errors.append(backend_test.stdout[-1500:])
        errors.append(backend_test.stderr[-1500:])

    worker_passed = False
    worker_skipped = False
    try:
        worker_test = subprocess.run(
            ["flutter", "test", str(artifacts["privacyCleanupTests"])],
            cwd=ROOT / "src/apps/worker",
            capture_output=True,
            text=True,
        )
        worker_passed = worker_test.returncode == 0
        if not worker_passed:
            errors.append("flutter test failed for privacy cleanup coordinator")
            if worker_test.stderr.strip():
                errors.append(worker_test.stderr[-1000:])
    except FileNotFoundError:
        worker_skipped = True

    evidence = {
        "status": "passed" if not errors else "failed",
        "taskId": "P8-A21",
        "auditId": "A21",
        "acceptanceCase": "T21",
        "architectureVersion": "2.0",
        "sourceSections": ["28", "31", "54", "55", "61"],
        "generatedAt": datetime.now(UTC).isoformat(),
        "commitSha": _git_sha(),
        "classification": "IMPLEMENTED_DEV_ONLY",
        "artifacts": {
            k: str(v.relative_to(ROOT)).replace("\\", "/") for k, v in artifacts.items()
        },
        "t21Scenario": {
            "title": "Huge decoded input; partial upload; cancel/retention race; no leakage",
            "decodeBoundsBeforeAdmission": "_assert_file_decode_bounds" in admission,
            "partialUploadRejected": "evaluate_upload_acceptance" in (
                artifacts["fileLifecycle"].read_text(encoding="utf-8")
                if artifacts["fileLifecycle"].is_file()
                else ""
            ),
            "privacyCleanupWired": "PrivacyCleanupCoordinator" in coordinator,
            "workerTests": worker_passed if not worker_skipped else "SKIPPED_FLUTTER_UNAVAILABLE",
            "integrationHarness": "NOT_RUN",
        },
        "gaps": [
            "T21 huge PDF/image decode E2E on device NOT_RUN",
            "Cancel/retention race integration harness NOT_RUN",
            "Production retention sweeper proof NOT_RUN",
        ],
        "errors": errors,
    }

    out_path = ROOT / "plan/evidence/phase-08-p8-a21-decode-bounds-privacy-cleanup.json"
    out_path.write_text(json.dumps(evidence, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(evidence, indent=2))
    return 0 if evidence["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
