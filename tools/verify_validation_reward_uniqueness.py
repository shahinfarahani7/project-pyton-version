#!/usr/bin/env python3
"""Verify validation/reward uniqueness and external-effect dedup for P8-A08 / T08."""

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
        "sqlMigration": ROOT / "database/sql/032_result_candidates_reward_entitlements.sql",
        "resultAcceptance": ROOT / "src/backend/edgemint/results/result_acceptance.py",
        "entitlementKeys": ROOT / "src/backend/edgemint/results/entitlement_keys.py",
        "externalEffects": ROOT / "src/backend/edgemint/results/external_effects.py",
        "assignmentsWiring": ROOT / "src/backend/edgemint/workers/assignments.py",
        "billingReplay": ROOT / "src/backend/edgemint/billing/service.py",
        "backendTests": ROOT / "src/backend/tests/results/test_result_acceptance.py",
        "chaosReward": ROOT / "src/backend/tests/chaos/test_production_proof_scenarios.py",
    }
    for label, path in artifacts.items():
        if not path.is_file():
            errors.append(f"missing artifact ({label}): {path.relative_to(ROOT)}")

    migration = (
        artifacts["sqlMigration"].read_text(encoding="utf-8")
        if artifacts["sqlMigration"].is_file()
        else ""
    )
    for token in (
        "pin_result_candidate",
        "record_result_validation",
        "accept_task_run_with_entitlement",
        "UQ_reward_entitlement_business_key",
        "UQ_external_effect_dedup",
    ):
        if token not in migration:
            errors.append(f"SQL migration missing token: {token}")

    assignments = (
        artifacts["assignmentsWiring"].read_text(encoding="utf-8")
        if artifacts["assignmentsWiring"].is_file()
        else ""
    )
    if "result_acceptance" not in assignments:
        errors.append("assignments.complete missing result_acceptance wiring")

    backend_test = subprocess.run(
        [
            sys.executable,
            "-m",
            "pytest",
            str(artifacts["backendTests"]),
            "-q",
        ],
        cwd=ROOT / "src/backend",
        capture_output=True,
        text=True,
    )
    backend_passed = backend_test.returncode == 0
    if not backend_passed:
        errors.append("backend pytest failed for result acceptance tests")
        errors.append(backend_test.stdout[-1500:])
        errors.append(backend_test.stderr[-1500:])

    chaos_test = subprocess.run(
        [
            sys.executable,
            "-m",
            "pytest",
            str(artifacts["chaosReward"]),
            "-k",
            "reward_exactly_once",
            "-q",
        ],
        cwd=ROOT / "src/backend",
        capture_output=True,
        text=True,
    )
    chaos_passed = chaos_test.returncode == 0
    if not chaos_passed:
        errors.append("P7 chaos reward exactly-once regression failed")
        errors.append(chaos_test.stdout[-1500:])
        errors.append(chaos_test.stderr[-1500:])

    evidence = {
        "status": "passed" if not errors else "failed",
        "taskId": "P8-A08",
        "auditId": "A08",
        "acceptanceCase": "T08",
        "architectureVersion": "2.0",
        "sourceSections": ["22", "23", "48", "50", "51"],
        "generatedAt": datetime.now(UTC).isoformat(),
        "commitSha": _git_sha(),
        "classification": "IMPLEMENTED_DEV_ONLY",
        "artifacts": {k: str(v.relative_to(ROOT)).replace("\\", "/") for k, v in artifacts.items()},
        "t08Scenario": {
            "title": "Validation gate, entitlement uniqueness, external-effect dedup",
            "immutableCandidatePinned": "sql+service",
            "entitlementUniquePerTaskRun": backend_passed,
            "financeIdempotencyReplay": backend_passed,
            "externalEffectDedupSql": "record_external_effect_receipt" in migration,
            "p7RewardRegression": chaos_passed,
            "integrationHarness": "NOT_RUN",
            "crashBoundaryHarness": "NOT_RUN",
        },
        "gaps": [
            "T08 crash between validation, terminal commit, entitlement and payout NOT_RUN",
            "External payout provider reconciliation harness NOT_RUN",
            "Partial-reward component deduplication integration NOT_RUN",
        ],
        "errors": errors,
    }

    out_path = ROOT / "plan/evidence/phase-08-p8-a08-validation-reward-uniqueness.json"
    out_path.write_text(json.dumps(evidence, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(evidence, indent=2))
    return 0 if evidence["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
