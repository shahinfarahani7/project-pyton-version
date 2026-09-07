#!/usr/bin/env python3
"""Verify contract-specific semantic quality validation for P8-A18 / T18."""

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
        "semanticQualityPolicyDsl": ROOT / "dsl/policies/validation/semantic-quality-v1.yaml",
        "semanticQualityModule": ROOT / "src/backend/edgemint/results/semantic_quality.py",
        "resultValidator": ROOT / "src/backend/edgemint/results/validator.py",
        "qualityEscalation": ROOT / "src/backend/edgemint/routing/quality_escalation.py",
        "backendTests": ROOT / "src/backend/tests/results/test_semantic_quality_validation.py",
        "qualityEscalationTests": ROOT / "src/backend/tests/routing/test_quality_escalation.py",
        "p5Cross01Evidence": ROOT / "plan/evidence/phase-05-p5-cross-01-result-validation-framework.json",
    }
    for label, path in artifacts.items():
        if not path.is_file():
            errors.append(f"missing artifact ({label}): {path.relative_to(ROOT)}")

    validator_src = (
        artifacts["resultValidator"].read_text(encoding="utf-8")
        if artifacts["resultValidator"].is_file()
        else ""
    )
    for token in ("semantic_quality_valid", "_apply_semantic_quality", "evaluate_semantic_quality"):
        if token not in validator_src:
            errors.append(f"result validator missing token: {token}")

    escalation_src = (
        artifacts["qualityEscalation"].read_text(encoding="utf-8")
        if artifacts["qualityEscalation"].is_file()
        else ""
    )
    for token in ("escalation_class_for_failure", "SEMANTIC_QUALITY_FAILED"):
        if token not in escalation_src:
            errors.append(f"quality escalation missing token: {token}")

    policy = (
        artifacts["semanticQualityPolicyDsl"].read_text(encoding="utf-8")
        if artifacts["semanticQualityPolicyDsl"].is_file()
        else ""
    )
    if "rejectsSelfReportedConfidenceAsSoleProof" not in policy:
        errors.append("semantic quality policy missing confidence rule")

    backend_test = subprocess.run(
        [
            sys.executable,
            "-m",
            "pytest",
            str(artifacts["backendTests"]),
            str(artifacts["qualityEscalationTests"]),
            "-q",
        ],
        cwd=ROOT / "src/backend",
        capture_output=True,
        text=True,
    )
    backend_passed = backend_test.returncode == 0
    if not backend_passed:
        errors.append("backend pytest failed for semantic quality validation")
        errors.append(backend_test.stdout[-1500:])
        errors.append(backend_test.stderr[-1500:])

    evidence = {
        "status": "passed" if not errors else "failed",
        "taskId": "P8-A18",
        "auditId": "A18",
        "acceptanceCase": "T18",
        "architectureVersion": "2.0",
        "sourceSections": ["48", "49", "51", "58"],
        "generatedAt": datetime.now(UTC).isoformat(),
        "commitSha": _git_sha(),
        "classification": "IMPLEMENTED_DEV_ONLY",
        "artifacts": {
            k: str(v.relative_to(ROOT)).replace("\\", "/") for k, v in artifacts.items()
        },
        "t18Scenario": {
            "title": "Valid JSON wrong semantics; self-reported confidence; quality vs capacity escalation",
            "schemaDistinctFromSemanticQuality": "semantic_quality_valid" in validator_src,
            "wrongContentRejected": backend_passed,
            "selfReportedConfidenceNotSufficient": "self-reported confidence is not sufficient proof"
            in (artifacts["semanticQualityModule"].read_text(encoding="utf-8") if artifacts["semanticQualityModule"].is_file() else ""),
            "qualityEscalationDistinctFromCapacity": "escalation_class_for_failure" in escalation_src,
            "goldenHarnessExtended": "NOT_RUN",
        },
        "gaps": [
            "T18 full golden harness wrong-output matrix NOT_RUN",
            "Vision geometry golden fixtures for all families NOT_RUN",
            "Production verification path task_input wiring NOT_RUN",
        ],
        "errors": errors,
    }

    out_path = ROOT / "plan/evidence/phase-08-p8-a18-semantic-quality-validation.json"
    out_path.write_text(json.dumps(evidence, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(evidence, indent=2))
    return 0 if evidence["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
