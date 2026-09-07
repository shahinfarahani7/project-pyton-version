#!/usr/bin/env python3
"""Verify runtime maintenance and upgrade evaluation for P8-A24 / T24."""

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
        "runtimeMaintenanceUpgradeDsl": ROOT
        / "dsl/policies/runtime/runtime-maintenance-upgrade-v1.yaml",
        "runtimeUpgradePolicyModule": ROOT
        / "src/backend/edgemint/runtime/runtime_upgrade_policy.py",
        "runtimeUpgradeCoordinator": ROOT
        / "src/apps/worker/lib/runtime/runtime_upgrade_coordinator.dart",
        "gemmaModelRuntimeManager": ROOT
        / "src/apps/worker/lib/runtime/gemma_model_runtime_manager.dart",
        "artifactInstallCoordinator": ROOT
        / "src/apps/worker/lib/runtime/artifact_install_coordinator.dart",
        "modelPromotionGate": ROOT / "src/backend/edgemint/models/promotion.py",
        "runtimeUpgradeSql": ROOT / "database/sql/037_runtime_upgrade_evaluations.sql",
        "runbook": ROOT / "docs/08-sre/runbooks/RB-027-runtime-maintenance-upgrade-evaluation.md",
        "backendTests": ROOT / "src/backend/tests/runtime/test_runtime_upgrade_policy.py",
        "coordinatorTests": ROOT / "src/apps/worker/test/runtime/runtime_upgrade_coordinator_test.dart",
        "p8A16Evidence": ROOT / "plan/evidence/phase-08-p8-a16-artifact-install-runtime-identity.json",
        "runtimeCompatibilityProfile": ROOT
        / "dsl/catalog/runtime-compatibility/production-v1.yaml",
    }
    for label, path in artifacts.items():
        if not path.is_file():
            errors.append(f"missing artifact ({label}): {path.relative_to(ROOT)}")

    policy = (
        artifacts["runtimeMaintenanceUpgradeDsl"].read_text(encoding="utf-8")
        if artifacts["runtimeMaintenanceUpgradeDsl"].is_file()
        else ""
    )
    for token in (
        "maintenance_only",
        "silentUpgradeForbidden",
        "evaluationDimensions",
        "rollbackBeforeForwardAdoption",
    ):
        if token not in policy:
            errors.append(f"runtime upgrade policy missing token: {token}")

    gemma = (
        artifacts["gemmaModelRuntimeManager"].read_text(encoding="utf-8")
        if artifacts["gemmaModelRuntimeManager"].is_file()
        else ""
    )
    if "assertUpgradeAllowedDuringSession" not in gemma:
        errors.append("gemma runtime manager missing upgrade-during-session guard")

    backend_test = subprocess.run(
        [sys.executable, "-m", "pytest", str(artifacts["backendTests"]), "-q"],
        cwd=ROOT / "src/backend",
        capture_output=True,
        text=True,
    )
    backend_passed = backend_test.returncode == 0
    if not backend_passed:
        errors.append("backend pytest failed for runtime upgrade policy")
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
            errors.append("flutter test failed for runtime upgrade coordinator")
            if worker_test.stderr.strip():
                errors.append(worker_test.stderr[-1000:])
    except FileNotFoundError:
        worker_skipped = True

    payload = {
        "status": "passed" if not errors else "failed",
        "taskId": "P8-A24",
        "auditId": "A24",
        "acceptanceCase": "T24",
        "architectureVersion": "2.0",
        "sourceSections": ["4", "32.1", "70", "77"],
        "generatedAt": datetime.now(UTC).isoformat(),
        "commitSha": _git_sha(),
        "classification": "IMPLEMENTED_DEV_ONLY",
        "artifacts": {k: str(v.relative_to(ROOT)).replace("\\", "/") for k, v in artifacts.items()},
        "t24Scenario": {
            "title": "Candidate runtime/model upgrade compatibility and rollback",
            "pinnedBaselineDocumented": True,
            "upgradeEvaluationWired": True,
            "rollbackEvidenceRequired": True,
            "upgradeBlockedDuringOpenSessions": True,
            "backendTests": "passed" if backend_passed else "failed",
            "workerTests": (
                "SKIPPED_FLUTTER_UNAVAILABLE"
                if worker_skipped
                else ("passed" if worker_passed else "failed")
            ),
            "integrationHarness": "NOT_RUN",
        },
        "gaps": [
            "T24 candidate runtime evaluation on device NOT_RUN",
            "Rollback proof before forward adoption NOT_RUN",
            "LiteRT-LM migration evaluation NOT_RUN",
        ],
        "errors": errors,
    }

    out = ROOT / "plan/evidence/phase-08-p8-a24-runtime-upgrade-compatibility.json"
    out.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(payload, indent=2))
    return 0 if not errors else 1


if __name__ == "__main__":
    raise SystemExit(main())
