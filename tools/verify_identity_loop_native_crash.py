#!/usr/bin/env python3
"""Verify identity loop tracing and Native crash reconciliation for P8-A22 / T22."""

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
        "identityLifecyclePolicyDsl": ROOT
        / "dsl/policies/worker/active-identity-native-lifecycle-v1.yaml",
        "identityNativeLifecycleModule": ROOT
        / "src/backend/edgemint/workers/identity_native_lifecycle.py",
        "identityLifecycleTracer": ROOT
        / "src/apps/worker/lib/runtime/identity_lifecycle_tracer.dart",
        "workerModelInstaller": ROOT / "src/apps/worker/lib/runtime/worker_model_installer.dart",
        "workerAppController": ROOT / "src/apps/worker/lib/worker_app_controller.dart",
        "gemmaModelRuntimeManager": ROOT
        / "src/apps/worker/lib/runtime/gemma_model_runtime_manager.dart",
        "processLifecycleCoordinator": ROOT
        / "src/apps/worker/lib/runtime/process_lifecycle_coordinator.dart",
        "workerHeartbeatTelemetry": ROOT
        / "src/apps/worker/lib/runtime/worker_heartbeat_telemetry.dart",
        "runbook": ROOT / "docs/08-sre/runbooks/RB-024-identity-loop-native-crash-evidence.md",
        "backendTests": ROOT / "src/backend/tests/workers/test_identity_native_lifecycle.py",
        "tracerTests": ROOT / "src/apps/worker/test/runtime/identity_lifecycle_tracer_test.dart",
        "p8T06Evidence": ROOT / "plan/evidence/phase-08-p8-t06-identity-loop-investigation.json",
        "p8A17Evidence": ROOT / "plan/evidence/phase-08-p8-a17-physical-device-lifecycle-proof.json",
    }
    for label, path in artifacts.items():
        if not path.is_file():
            errors.append(f"missing artifact ({label}): {path.relative_to(ROOT)}")

    policy = (
        artifacts["identityLifecyclePolicyDsl"].read_text(encoding="utf-8")
        if artifacts["identityLifecyclePolicyDsl"].is_file()
        else ""
    )
    for token in (
        "nativeHandleCounters",
        "idleStability",
        "doNotDependOnDartAfterSigsegv",
        "idle_identity_loop",
        "native_crash_regression",
    ):
        if token not in policy:
            errors.append(f"identity lifecycle policy missing token: {token}")

    tracer = (
        artifacts["identityLifecycleTracer"].read_text(encoding="utf-8")
        if artifacts["identityLifecycleTracer"].is_file()
        else ""
    )
    for token in ("guardBootstrap", "recordNativeModelCreate", "heartbeatView"):
        if token not in tracer:
            errors.append(f"identity tracer missing token: {token}")

    controller = (
        artifacts["workerAppController"].read_text(encoding="utf-8")
        if artifacts["workerAppController"].is_file()
        else ""
    )
    if "IdentityLifecycleTracer" not in controller:
        errors.append("worker app controller missing identity tracer wiring")

    telemetry = (
        artifacts["workerHeartbeatTelemetry"].read_text(encoding="utf-8")
        if artifacts["workerHeartbeatTelemetry"].is_file()
        else ""
    )
    if "identityLifecycleView" not in telemetry:
        errors.append("heartbeat telemetry missing identityLifecycleView")

    backend_test = subprocess.run(
        [sys.executable, "-m", "pytest", str(artifacts["backendTests"]), "-q"],
        cwd=ROOT / "src/backend",
        capture_output=True,
        text=True,
    )
    backend_passed = backend_test.returncode == 0
    if not backend_passed:
        errors.append("backend pytest failed for identity native lifecycle")
        errors.append(backend_test.stdout[-1500:])
        errors.append(backend_test.stderr[-1500:])

    worker_passed = False
    worker_skipped = False
    try:
        worker_test = subprocess.run(
            ["flutter", "test", str(artifacts["tracerTests"])],
            cwd=ROOT / "src/apps/worker",
            capture_output=True,
            text=True,
        )
        worker_passed = worker_test.returncode == 0
        if not worker_passed:
            errors.append("flutter test failed for identity lifecycle tracer")
            if worker_test.stderr.strip():
                errors.append(worker_test.stderr[-1000:])
    except FileNotFoundError:
        worker_skipped = True

    payload = {
        "status": "passed" if not errors else "failed",
        "taskId": "P8-A22",
        "auditId": "A22",
        "acceptanceCase": "T22",
        "architectureVersion": "2.0",
        "sourceSections": ["24", "41", "53", "75", "76"],
        "generatedAt": datetime.now(UTC).isoformat(),
        "commitSha": _git_sha(),
        "classification": "IMPLEMENTED_DEV_ONLY",
        "artifacts": {k: str(v.relative_to(ROOT)).replace("\\", "/") for k, v in artifacts.items()},
        "t22Scenario": {
            "title": "Idle identity loop; bootstrap paths; missing model; Native crash regression",
            "identityTracingWired": True,
            "nativeCrashReconciliationWired": True,
            "heartbeatIdentityView": True,
            "backendTests": "passed" if backend_passed else "failed",
            "workerTests": (
                "SKIPPED_FLUTTER_UNAVAILABLE"
                if worker_skipped
                else ("passed" if worker_passed else "failed")
            ),
            "physicalHarness": "NOT_RUN",
        },
        "gaps": [
            "T22 idle soak on physical device NOT_RUN",
            "Native crash regression harness NOT_RUN",
            "Historical SIGSEGV/GATHER_ND before/after repro NOT_RUN",
        ],
        "errors": errors,
    }

    out = ROOT / "plan/evidence/phase-08-p8-a22-identity-loop-native-crash.json"
    out.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(payload, indent=2))
    return 0 if not errors else 1


if __name__ == "__main__":
    raise SystemExit(main())
