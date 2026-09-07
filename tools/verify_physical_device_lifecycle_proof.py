#!/usr/bin/env python3
"""Verify physical-device process lifecycle proof for P8-A17 / T17."""

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
        "lifecyclePolicyDsl": ROOT / "dsl/policies/worker/android-process-lifecycle-v1.yaml",
        "physicalDeviceProofModule": ROOT
        / "src/backend/edgemint/workers/physical_device_proof.py",
        "processLifecycleCoordinator": ROOT
        / "src/apps/worker/lib/runtime/process_lifecycle_coordinator.dart",
        "assignmentCoordinator": ROOT
        / "src/apps/worker/lib/runtime/assignment_coordinator.dart",
        "workerAppController": ROOT / "src/apps/worker/lib/worker_app_controller.dart",
        "workerMain": ROOT / "src/apps/worker/lib/main.dart",
        "foregroundService": ROOT
        / "src/apps/worker/android/app/src/main/kotlin/io/edgemint/edgemint_worker/ExecutionForegroundService.kt",
        "androidManifest": ROOT / "src/apps/worker/android/app/src/main/AndroidManifest.xml",
        "runbook": ROOT
        / "docs/08-sre/runbooks/RB-023-physical-device-lifecycle-proof.md",
        "backendTests": ROOT / "src/backend/tests/workers/test_physical_device_lifecycle.py",
        "coordinatorTests": ROOT
        / "src/apps/worker/test/runtime/process_lifecycle_coordinator_test.dart",
        "p7LoadEvidence": ROOT / "plan/evidence/phase-07-p7-chaos-20-workers.json",
    }
    for label, path in artifacts.items():
        if not path.is_file():
            errors.append(f"missing artifact ({label}): {path.relative_to(ROOT)}")

    policy = (
        artifacts["lifecyclePolicyDsl"].read_text(encoding="utf-8")
        if artifacts["lifecyclePolicyDsl"].is_file()
        else ""
    )
    for token in (
        "ExecutionForegroundService",
        "emulatorAloneCannotCertifyProduction",
        "process_death",
        "device_reboot",
    ):
        if token not in policy:
            errors.append(f"lifecycle policy missing token: {token}")

    coordinator = (
        artifacts["processLifecycleCoordinator"].read_text(encoding="utf-8")
        if artifacts["processLifecycleCoordinator"].is_file()
        else ""
    )
    for token in (
        "requiresFreshGrantReconciliation",
        "markProcessTerminated",
        "runtimeGeneration",
    ):
        if token not in coordinator:
            errors.append(f"process lifecycle coordinator missing token: {token}")

    assignment = (
        artifacts["assignmentCoordinator"].read_text(encoding="utf-8")
        if artifacts["assignmentCoordinator"].is_file()
        else ""
    )
    if "blockedPendingFreshGrant" not in assignment:
        errors.append("assignment coordinator missing fresh-grant resume guard")

    controller = (
        artifacts["workerAppController"].read_text(encoding="utf-8")
        if artifacts["workerAppController"].is_file()
        else ""
    )
    if "ProcessLifecycleCoordinator" not in controller:
        errors.append("worker app controller missing lifecycle coordinator wiring")

    main_dart = (
        artifacts["workerMain"].read_text(encoding="utf-8")
        if artifacts["workerMain"].is_file()
        else ""
    )
    if "WidgetsBindingObserver" not in main_dart:
        errors.append("worker main missing app lifecycle observer")

    manifest = (
        artifacts["androidManifest"].read_text(encoding="utf-8")
        if artifacts["androidManifest"].is_file()
        else ""
    )
    if "ExecutionForegroundService" not in manifest:
        errors.append("android manifest missing foreground service declaration")

    matrix_ok = False
    matrix_check = subprocess.run(
        [
            sys.executable,
            "-c",
            "from edgemint.workers.physical_device_proof import "
            "load_android_process_lifecycle_policy, matrix_entries_from_policy; "
            "p=load_android_process_lifecycle_policy(); "
            "assert len(matrix_entries_from_policy(p)) >= 6; print('ok')",
        ],
        cwd=ROOT / "src/backend",
        capture_output=True,
        text=True,
    )
    matrix_ok = matrix_check.returncode == 0
    if not matrix_ok:
        errors.append("physical device matrix load failed")
        errors.append(matrix_check.stderr[-1000:])

    backend_test = subprocess.run(
        [sys.executable, "-m", "pytest", str(artifacts["backendTests"]), "-q"],
        cwd=ROOT / "src/backend",
        capture_output=True,
        text=True,
    )
    backend_passed = backend_test.returncode == 0
    if not backend_passed:
        errors.append("backend pytest failed for physical device lifecycle")
        errors.append(backend_test.stdout[-1500:])
        errors.append(backend_test.stderr[-1500:])

    worker_passed = False
    worker_skipped = False
    try:
        worker_test = subprocess.run(
            ["flutter", "test", str(artifacts["coordinatorTests"])],
            cwd=ROOT / "src/apps/worker",
            capture_output=True,
            text=True,
        )
        worker_passed = worker_test.returncode == 0
        if not worker_passed:
            errors.append("flutter test failed for process lifecycle coordinator")
            if worker_test.stderr.strip():
                errors.append(worker_test.stderr[-1000:])
    except FileNotFoundError:
        worker_skipped = True

    evidence = {
        "status": "passed" if not errors else "failed",
        "taskId": "P8-A17",
        "auditId": "A17",
        "acceptanceCase": "T17",
        "architectureVersion": "2.0",
        "sourceSections": ["24", "32", "39", "65"],
        "generatedAt": datetime.now(UTC).isoformat(),
        "commitSha": _git_sha(),
        "classification": "IMPLEMENTED_DEV_ONLY",
        "artifacts": {
            k: str(v.relative_to(ROOT)).replace("\\", "/") for k, v in artifacts.items()
        },
        "t17Scenario": {
            "title": "Background/suspend/process death/reboot/OS pressure on physical devices",
            "platformProfileDefined": matrix_ok,
            "freshGrantReconciliationGuard": "blockedPendingFreshGrant" in assignment,
            "foregroundServiceDeclared": "ExecutionForegroundService" in manifest,
            "appLifecycleObserverWired": "WidgetsBindingObserver" in main_dart,
            "workerTests": worker_passed if not worker_skipped else "SKIPPED_FLUTTER_UNAVAILABLE",
            "physicalDeviceHarness": "NOT_RUN",
        },
        "gaps": [
            "T17 background FGS physical-device proof NOT_RUN",
            "T17 app suspend / process death / reboot matrix NOT_RUN",
            "T17 OS memory pressure physical-device proof NOT_RUN",
            "Native handle counter idle soak NOT_RUN",
        ],
        "errors": errors,
    }

    out_path = ROOT / "plan/evidence/phase-08-p8-a17-physical-device-lifecycle-proof.json"
    out_path.write_text(json.dumps(evidence, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(evidence, indent=2))
    return 0 if evidence["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
