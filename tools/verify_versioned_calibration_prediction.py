#!/usr/bin/env python3
"""Verify versioned calibration/prediction for P8-A20 / T20."""

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
        "versionedPredictionPolicyDsl": ROOT
        / "dsl/policies/calibration/versioned-prediction-v1.yaml",
        "calibrationPredictionModule": ROOT
        / "src/backend/edgemint/routing/calibration_prediction.py",
        "calibrationModule": ROOT / "src/backend/edgemint/routing/calibration.py",
        "costEstimator": ROOT / "src/backend/edgemint/routing/cost_estimator.py",
        "executionAllocation": ROOT / "src/backend/edgemint/routing/execution_allocation.py",
        "calibrationFeedback": ROOT / "src/backend/edgemint/workers/calibration_feedback.py",
        "routerService": ROOT / "src/backend/edgemint/routing/service.py",
        "backendTests": ROOT / "src/backend/tests/routing/test_versioned_calibration_prediction.py",
        "adaptiveExecutionTests": ROOT / "src/backend/tests/routing/test_adaptive_execution.py",
        "calibrationFeedbackTests": ROOT / "src/backend/tests/workers/test_calibration_feedback.py",
        "p6T03Evidence": ROOT / "plan/evidence/phase-06-p6-t03-device-calibration-loop.json",
        "p6T07Evidence": ROOT / "plan/evidence/phase-06-p6-t07-prediction-feedback-loop.json",
    }
    for label, path in artifacts.items():
        if not path.is_file():
            errors.append(f"missing artifact ({label}): {path.relative_to(ROOT)}")

    policy = (
        artifacts["versionedPredictionPolicyDsl"].read_text(encoding="utf-8")
        if artifacts["versionedPredictionPolicyDsl"].is_file()
        else ""
    )
    for token in (
        "maxAgeDays",
        "conservativeFallbackFactorBps",
        "retroactiveGrantIncreaseForbidden",
        "neverCompareWarmDecodeAverageToColdEndToEnd",
    ):
        if token not in policy:
            errors.append(f"versioned prediction policy missing token: {token}")

    module = (
        artifacts["calibrationPredictionModule"].read_text(encoding="utf-8")
        if artifacts["calibrationPredictionModule"].is_file()
        else ""
    )
    for token in (
        "apply_feedback_to_future_predictions_only",
        "evaluate_profile_freshness",
        "PredictionPhase",
        "build_versioned_prediction",
    ):
        if token not in module:
            errors.append(f"calibration prediction module missing token: {token}")

    router = (
        artifacts["routerService"].read_text(encoding="utf-8")
        if artifacts["routerService"].is_file()
        else ""
    )
    if "build_versioned_prediction_record" not in router:
        errors.append("router service missing versioned prediction hook")

    backend_test = subprocess.run(
        [
            sys.executable,
            "-m",
            "pytest",
            str(artifacts["backendTests"]),
            str(artifacts["adaptiveExecutionTests"]),
            str(artifacts["calibrationFeedbackTests"]),
            "-q",
        ],
        cwd=ROOT / "src/backend",
        capture_output=True,
        text=True,
    )
    backend_passed = backend_test.returncode == 0
    if not backend_passed:
        errors.append("backend pytest failed for versioned calibration prediction")
        errors.append(backend_test.stdout[-1500:])
        errors.append(backend_test.stderr[-1500:])

    evidence = {
        "status": "passed" if not errors else "failed",
        "taskId": "P8-A20",
        "auditId": "A20",
        "acceptanceCase": "T20",
        "architectureVersion": "2.0",
        "sourceSections": ["13", "33", "34", "73"],
        "generatedAt": datetime.now(UTC).isoformat(),
        "commitSha": _git_sha(),
        "classification": "IMPLEMENTED_DEV_ONLY",
        "artifacts": {
            k: str(v.relative_to(ROOT)).replace("\\", "/") for k, v in artifacts.items()
        },
        "t20Scenario": {
            "title": "Cold/warm prediction; aged profile; changed artifact; underestimated peak",
            "coldWarmDistinction": "PredictionPhase" in module,
            "profileExpiryFallback": "evaluate_profile_freshness" in module,
            "futureOnlyFeedback": "retroactiveGrantIncreaseForbidden" in policy,
            "routerVersionedPredictionHook": "build_versioned_prediction_record" in router,
            "integrationHarness": "NOT_RUN",
        },
        "gaps": [
            "T20 cold/warm end-to-end allocation identity proof NOT_RUN",
            "Profile expiry production sweeper NOT_RUN",
            "Underestimated peak device matrix NOT_RUN",
        ],
        "errors": errors,
    }

    out_path = ROOT / "plan/evidence/phase-08-p8-a20-versioned-calibration-prediction.json"
    out_path.write_text(json.dumps(evidence, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(evidence, indent=2))
    return 0 if evidence["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
