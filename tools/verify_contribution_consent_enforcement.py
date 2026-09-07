#!/usr/bin/env python3
"""Verify contribution units, consent, and CPU enforcement artifacts for P8-A06 / T06."""

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
        "policyDsl": ROOT / "dsl/policies/consent/production-resource-policy-v1.yaml",
        "policySchema": ROOT / "dsl/schemas/userresourcepolicy.schema.json",
        "resourcePolicy": ROOT / "src/backend/edgemint/workers/resource_policy.py",
        "contributionEnforcement": ROOT / "src/backend/edgemint/workers/contribution_enforcement.py",
        "consentTransitions": ROOT / "src/backend/edgemint/workers/consent_transitions.py",
        "consentOptIn": ROOT / "src/backend/edgemint/workers/consent_opt_in.py",
        "enrollmentWiring": ROOT / "src/backend/edgemint/workers/enrollment.py",
        "hardEligibility": ROOT / "src/backend/edgemint/routing/hard_eligibility.py",
        "sqlCertification": ROOT / "database/sql/030_worker_cpu_enforcement_certification.sql",
        "sqlContributionMode": ROOT / "database/sql/017_worker_contribution_mode.sql",
        "sqlOptInEvents": ROOT / "database/sql/024_worker_contribution_opt_in_events.sql",
        "workerModule": ROOT / "src/apps/worker/lib/runtime/contribution_enforcement.dart",
        "workerEnforcer": ROOT / "src/apps/worker/lib/runtime/worker_resource_enforcer.dart",
        "backendTests": ROOT / "src/backend/tests/workers/test_contribution_enforcement.py",
        "consentOptInTests": ROOT / "src/backend/tests/workers/test_consent_opt_in.py",
        "resourcePolicyTests": ROOT / "src/backend/tests/workers/test_resource_policy.py",
        "p6Evidence30": ROOT / "plan/evidence/phase-06-p6-t08-consent-increase-30-to-50.json",
        "p7EvidenceRevoke": ROOT / "plan/evidence/phase-07-p7-chaos-consent-revoke.json",
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
        "contributionRequiresExplicitOptIn: true",
        "cpuEnforcement:",
        "measurementWindowMs: 5000",
        "controlStopReactionBoundMs: 3000",
        "requiresExplicitOptIn: true",
    ):
        if token not in policy_yaml:
            errors.append(f"policy DSL missing token: {token}")

    backend_test = subprocess.run(
        [
            sys.executable,
            "-m",
            "pytest",
            str(artifacts["backendTests"]),
            str(artifacts["consentOptInTests"]),
            str(artifacts["resourcePolicyTests"]),
            "-q",
        ],
        cwd=ROOT / "src/backend",
        capture_output=True,
        text=True,
    )
    backend_passed = backend_test.returncode == 0
    if not backend_passed:
        errors.append("backend pytest failed for contribution/consent tests")
        errors.append(backend_test.stdout[-1500:])
        errors.append(backend_test.stderr[-1500:])

    evidence = {
        "status": "passed" if not errors else "failed",
        "taskId": "P8-A06",
        "auditId": "A06",
        "acceptanceCase": "T06",
        "architectureVersion": "2.0",
        "sourceSections": ["2", "15", "16.1", "17", "18", "64", "73"],
        "generatedAt": datetime.now(UTC).isoformat(),
        "commitSha": _git_sha(),
        "classification": "IMPLEMENTED_DEV_ONLY",
        "artifacts": {k: str(v.relative_to(ROOT)).replace("\\", "/") for k, v in artifacts.items()},
        "t06Scenario": {
            "title": "No opt-in; 30→50, 50→30, revocation during inference",
            "explicitOptInRequiredForPerformance": backend_passed,
            "cpuWindowBurstStopProfileVersioned": backend_passed,
            "consentTransitionStopBoundMs": 3000,
            "upstreamChaosEvidence": [
                "plan/evidence/phase-06-p6-t08-consent-increase-30-to-50.json",
                "plan/evidence/phase-06-p6-t09-consent-decrease-50-to-30.json",
                "plan/evidence/phase-06-p6-t10-consent-revocation.json",
                "plan/evidence/phase-07-p7-chaos-consent-30-to-50.json",
                "plan/evidence/phase-07-p7-chaos-consent-50-to-30.json",
                "plan/evidence/phase-07-p7-chaos-consent-revoke.json",
            ],
            "integrationHarness": "NOT_RUN",
        },
        "gaps": [
            "T06 live inference revocation/stop-bound integration harness NOT_RUN",
            "Native stop/reaction certification on physical device NOT_RUN",
            "worker_cpu_enforcement_certification_required defaults false until rollout",
        ],
        "errors": errors,
    }

    out_path = ROOT / "plan/evidence/phase-08-p8-a06-contribution-consent-enforcement.json"
    out_path.write_text(json.dumps(evidence, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(evidence, indent=2))
    return 0 if evidence["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
