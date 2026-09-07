#!/usr/bin/env python3
"""Verify policy readiness gates and mixed-version rollout for P8-A23 / T23."""

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
        "policyReadinessGateDsl": ROOT / "dsl/policies/governance/policy-readiness-gate-v1.yaml",
        "policyReadinessRecordSchema": ROOT / "dsl/schemas/policyreadinessrecord.schema.json",
        "policyReadinessGateModule": ROOT
        / "src/backend/edgemint/governance/policy_readiness_gate.py",
        "policyReadinessSql": ROOT / "database/sql/036_policy_readiness_records.sql",
        "runbook": ROOT / "docs/08-sre/runbooks/RB-026-policy-readiness-mixed-version-gate.md",
        "backendTests": ROOT / "src/backend/tests/governance/test_policy_readiness_gate.py",
        "p8T04Evidence": ROOT / "plan/evidence/phase-08-p8-t04-policy-readiness-gap.json",
        "p8T05Evidence": ROOT / "plan/evidence/phase-08-p8-t05-current-state-register.json",
        "analyzePolicyReadinessTool": ROOT / "tools/analyze_v2_policy_readiness.py",
        "productionGateTool": ROOT / "tools/production_gate.py",
    }
    for label, path in artifacts.items():
        if not path.is_file():
            errors.append(f"missing artifact ({label}): {path.relative_to(ROOT)}")

    policy = (
        artifacts["policyReadinessGateDsl"].read_text(encoding="utf-8")
        if artifacts["policyReadinessGateDsl"].is_file()
        else ""
    )
    for token in (
        "failClosedOnMissingValues",
        "mixedVersionRollout",
        "requireOwnershipDedupRecovery",
        "missing_policy_evidence",
    ):
        if token not in policy:
            errors.append(f"policy readiness gate DSL missing token: {token}")

    module = (
        artifacts["policyReadinessGateModule"].read_text(encoding="utf-8")
        if artifacts["policyReadinessGateModule"].is_file()
        else ""
    )
    for token in (
        "PolicyReadinessRecord",
        "evaluate_activation_gate",
        "evaluate_mixed_version_rollout",
        "evaluate_storage_restore_dedup",
    ):
        if token not in module:
            errors.append(f"policy readiness gate module missing token: {token}")

    backend_test = subprocess.run(
        [sys.executable, "-m", "pytest", str(artifacts["backendTests"]), "-q"],
        cwd=ROOT / "src/backend",
        capture_output=True,
        text=True,
    )
    backend_passed = backend_test.returncode == 0
    if not backend_passed:
        errors.append("backend pytest failed for policy readiness gate")
        errors.append(backend_test.stdout[-1500:])
        errors.append(backend_test.stderr[-1500:])

    payload = {
        "status": "passed" if not errors else "failed",
        "taskId": "P8-A23",
        "auditId": "A23",
        "acceptanceCase": "T23",
        "architectureVersion": "2.0",
        "sourceSections": ["0.1", "3", "65", "66", "67", "68", "69", "70", "73", "74", "75"],
        "generatedAt": datetime.now(UTC).isoformat(),
        "commitSha": _git_sha(),
        "classification": "IMPLEMENTED_DEV_ONLY",
        "artifacts": {k: str(v.relative_to(ROOT)).replace("\\", "/") for k, v in artifacts.items()},
        "t23Scenario": {
            "title": "Missing policy/evidence gate; mixed-version rollout; storage restore",
            "activationGateWired": True,
            "policyReadinessRecordSchema": True,
            "mixedVersionRolloutWired": True,
            "storageRestoreDedupWired": True,
            "backendTests": "passed" if backend_passed else "failed",
            "integrationHarness": "NOT_RUN",
            "productionActivationGate": "CLOSED",
        },
        "gaps": [
            "T23 mixed-version rollout integration harness NOT_RUN",
            "Storage restore dedup integration harness NOT_RUN",
            "All §73 policy areas remain PARTIAL per P8-T04",
        ],
        "errors": errors,
    }

    out = ROOT / "plan/evidence/phase-08-p8-a23-policy-readiness-gates.json"
    out.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(payload, indent=2))
    return 0 if not errors else 1


if __name__ == "__main__":
    raise SystemExit(main())
