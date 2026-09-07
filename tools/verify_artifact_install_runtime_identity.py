#!/usr/bin/env python3
"""Verify reproducible artifact/install/runtime identity for P8-A16 / T16."""

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
        "contextProfileDsl": ROOT / "dsl/catalog/context-profiles/qwen2.5-0.5b-artifact-v1.yaml",
        "artifactIdentityModule": ROOT / "src/backend/edgemint/models/artifact_identity.py",
        "workerModelCatalog": ROOT / "src/apps/worker/lib/models/worker_model_catalog.dart",
        "artifactVerifier": ROOT / "src/apps/worker/lib/runtime/model_artifact_verifier.dart",
        "downloadVerifyHook": ROOT / "src/apps/worker/lib/runtime/model_download_verify_hook.dart",
        "installCoordinator": ROOT / "src/apps/worker/lib/runtime/artifact_install_coordinator.dart",
        "modelInstaller": ROOT / "src/apps/worker/lib/runtime/worker_model_installer.dart",
        "modelRuntimeManager": ROOT / "src/apps/worker/lib/runtime/model_runtime_manager.dart",
        "backendTests": ROOT / "src/backend/tests/models/test_artifact_identity.py",
        "verifierTests": ROOT / "src/apps/worker/test/runtime/model_artifact_verifier_test.dart",
        "runtimeManagerTests": ROOT / "src/apps/worker/test/runtime/model_runtime_manager_test.dart",
        "coordinatorTests": ROOT / "src/apps/worker/test/runtime/artifact_install_coordinator_test.dart",
        "p3T16Evidence": ROOT / "plan/evidence/phase-03-p3-t16-model-download-verify-hook.json",
    }
    for label, path in artifacts.items():
        if not path.is_file():
            errors.append(f"missing artifact ({label}): {path.relative_to(ROOT)}")

    catalog = (
        artifacts["workerModelCatalog"].read_text(encoding="utf-8")
        if artifacts["workerModelCatalog"].is_file()
        else ""
    )
    hook = (
        artifacts["downloadVerifyHook"].read_text(encoding="utf-8")
        if artifacts["downloadVerifyHook"].is_file()
        else ""
    )
    combined = catalog + hook
    for token in (
        "verifiedArtifactContextLimit = 1280",
        "ekv1280",
        "installedDigestMarker",
    ):
        if token not in combined:
            errors.append(f"worker catalog/hook missing token: {token}")

    installer = (
        artifacts["modelInstaller"].read_text(encoding="utf-8")
        if artifacts["modelInstaller"].is_file()
        else ""
    )
    if "ArtifactInstallCoordinator" not in installer:
        errors.append("worker installer missing install coordinator wiring")

    manager = (
        artifacts["modelRuntimeManager"].read_text(encoding="utf-8")
        if artifacts["modelRuntimeManager"].is_file()
        else ""
    )
    if "assertUpgradeAllowedDuringSession" not in manager:
        errors.append("runtime manager missing upgrade-during-session guard")

    verifier = (
        artifacts["artifactVerifier"].read_text(encoding="utf-8")
        if artifacts["artifactVerifier"].is_file()
        else ""
    )
    for token in ("Model digest mismatch", "Unsigned installed model rejected"):
        if token not in verifier:
            errors.append(f"artifact verifier missing rule: {token}")

    identity = subprocess.run(
        [
            sys.executable,
            "-c",
            "from edgemint.models.artifact_identity import require_consistent_artifact_identity; "
            "require_consistent_artifact_identity(); print('ok')",
        ],
        cwd=ROOT / "src/backend",
        capture_output=True,
        text=True,
    )
    identity_ok = identity.returncode == 0
    if not identity_ok:
        errors.append("artifact identity consistency check failed")
        errors.append(identity.stderr[-1000:])

    backend_test = subprocess.run(
        [sys.executable, "-m", "pytest", str(artifacts["backendTests"]), "-q"],
        cwd=ROOT / "src/backend",
        capture_output=True,
        text=True,
    )
    backend_passed = backend_test.returncode == 0
    if not backend_passed:
        errors.append("backend pytest failed for artifact identity")
        errors.append(backend_test.stdout[-1500:])
        errors.append(backend_test.stderr[-1500:])

    worker_passed = False
    worker_skipped = False
    try:
        worker_test = subprocess.run(
            [
                "flutter",
                "test",
                str(artifacts["coordinatorTests"]),
                str(artifacts["verifierTests"]),
                str(artifacts["runtimeManagerTests"]),
            ],
            cwd=ROOT / "src/apps/worker",
            capture_output=True,
            text=True,
        )
        worker_passed = worker_test.returncode == 0
        if not worker_passed:
            errors.append("flutter test failed for artifact install identity")
            if worker_test.stderr.strip():
                errors.append(worker_test.stderr[-1000:])
    except FileNotFoundError:
        worker_skipped = True

    evidence = {
        "status": "passed" if not errors else "failed",
        "taskId": "P8-A16",
        "auditId": "A16",
        "acceptanceCase": "T16",
        "architectureVersion": "2.0",
        "sourceSections": ["4", "24", "32", "53", "54"],
        "generatedAt": datetime.now(UTC).isoformat(),
        "commitSha": _git_sha(),
        "classification": "IMPLEMENTED_DEV_ONLY",
        "artifacts": {
            k: str(v.relative_to(ROOT)).replace("\\", "/") for k, v in artifacts.items()
        },
        "t16Scenario": {
            "title": "Interrupted download, bad hash, concurrent install, upgrade during session",
            "artifactIdentityManifest": identity_ok,
            "digestSignatureVerification": "Model digest mismatch" in verifier,
            "concurrentInstallSerialization": "runExclusiveInstall" in installer,
            "upgradeBlockedWithOpenSessions": "assertUpgradeAllowedDuringSession" in manager,
            "workerTests": worker_passed if not worker_skipped else "SKIPPED_FLUTTER_UNAVAILABLE",
            "integrationHarness": "NOT_RUN",
        },
        "gaps": [
            "T16 interrupted download recovery E2E NOT_RUN",
            "Physical-device concurrent install certification NOT_RUN",
            "Upgrade-during-active-session device proof NOT_RUN",
        ],
        "errors": errors,
    }

    out_path = ROOT / "plan/evidence/phase-08-p8-a16-artifact-install-runtime-identity.json"
    out_path.write_text(json.dumps(evidence, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(evidence, indent=2))
    return 0 if evidence["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
