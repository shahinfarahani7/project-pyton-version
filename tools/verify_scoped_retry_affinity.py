#!/usr/bin/env python3
"""Verify scoped retries, affinity, and TaskRun budget for P8-A14 / T14."""

from __future__ import annotations

import json
import subprocess
import sys
from datetime import UTC, datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FORBIDDEN = (
    "LocalTaskSelector",
    "LocalRetryOrchestrator",
    "LocalReassignmentManager",
    "LocalCloudFallbackDecision",
)


def _git_sha() -> str:
    try:
        return (
            subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True)
            .strip()
        )
    except Exception:
        return "unknown"


def _forbidden_scheduler_audit() -> dict[str, object]:
    worker_lib = ROOT / "src/apps/worker/lib"
    lib_matches: list[str] = []
    for path in worker_lib.rglob("*.dart"):
        text = path.read_text(encoding="utf-8")
        for component in FORBIDDEN:
            if component in text:
                lib_matches.append(f"{path.relative_to(ROOT)}:{component}")
    return {"libMatches": lib_matches, "passed": len(lib_matches) == 0}


def main() -> int:
    errors: list[str] = []
    artifacts = {
        "routingPolicyDsl": ROOT / "dsl/policies/routing/smart-router-v2.yaml",
        "retryMatrixDsl": ROOT / "dsl/policies/retry/task-retry-matrix-v1.yaml",
        "sqlMigration": ROOT / "database/sql/035_task_run_budgets.sql",
        "retryClassifier": ROOT / "src/backend/edgemint/routing/retry_classifier.py",
        "taskRunBudget": ROOT / "src/backend/edgemint/routing/task_run_budget.py",
        "artifactAffinity": ROOT / "src/backend/edgemint/routing/artifact_affinity.py",
        "failureAffinity": ROOT / "src/backend/edgemint/routing/failure_affinity.py",
        "cloudFallback": ROOT / "src/backend/edgemint/routing/cloud_fallback.py",
        "schedulerWiring": ROOT / "src/backend/edgemint/routing/service.py",
        "backendT14Tests": ROOT / "src/backend/tests/routing/test_scoped_retry_affinity.py",
        "retryClassifierTests": ROOT / "src/backend/tests/routing/test_retry_classifier.py",
        "failureAffinityTests": ROOT / "src/backend/tests/routing/test_failure_affinity.py",
    }
    for label, path in artifacts.items():
        if not path.is_file():
            errors.append(f"missing artifact ({label}): {path.relative_to(ROOT)}")

    policy_yaml = (
        artifacts["routingPolicyDsl"].read_text(encoding="utf-8")
        if artifacts["routingPolicyDsl"].is_file()
        else ""
    )
    for token in ("taskRunBudget:", "maxTotalAssignments:", "countersResetOnNewAttempt: false"):
        if token not in policy_yaml:
            errors.append(f"routing policy missing token: {token}")

    sql = (
        artifacts["sqlMigration"].read_text(encoding="utf-8")
        if artifacts["sqlMigration"].is_file()
        else ""
    )
    if "reserve_task_run_budget" not in sql:
        errors.append("SQL migration missing reserve_task_run_budget")

    service = (
        artifacts["schedulerWiring"].read_text(encoding="utf-8")
        if artifacts["schedulerWiring"].is_file()
        else ""
    )
    if "combine_assignment_budget_checks" not in service:
        errors.append("scheduler missing TaskRun budget wiring")

    cloud = (
        artifacts["cloudFallback"].read_text(encoding="utf-8")
        if artifacts["cloudFallback"].is_file()
        else ""
    )
    if "task_run_cloud_budget_exhausted" not in cloud:
        errors.append("cloud fallback missing TaskRun budget gate")

    forbidden = _forbidden_scheduler_audit()
    if not forbidden["passed"]:
        errors.append(f"forbidden scheduler components found: {forbidden['libMatches']}")

    backend_test = subprocess.run(
        [
            sys.executable,
            "-m",
            "pytest",
            str(artifacts["backendT14Tests"]),
            str(artifacts["retryClassifierTests"]),
            str(artifacts["failureAffinityTests"]),
            "-q",
        ],
        cwd=ROOT / "src/backend",
        capture_output=True,
        text=True,
    )
    backend_passed = backend_test.returncode == 0
    if not backend_passed:
        errors.append("backend pytest failed for scoped retry / affinity")
        errors.append(backend_test.stdout[-1500:])
        errors.append(backend_test.stderr[-1500:])

    evidence = {
        "status": "passed" if not errors else "failed",
        "taskId": "P8-A14",
        "auditId": "A14",
        "acceptanceCase": "T14",
        "architectureVersion": "2.0",
        "sourceSections": ["9", "41", "42", "43", "44", "45", "52", "73"],
        "generatedAt": datetime.now(UTC).isoformat(),
        "commitSha": _git_sha(),
        "classification": "IMPLEMENTED_DEV_ONLY",
        "artifacts": {
            k: str(v.relative_to(ROOT)).replace("\\", "/") for k, v in artifacts.items()
        },
        "t14Scenario": {
            "title": "Permanent error, corrupt artifact, thermal repeat, no Worker, exhausted Attempt",
            "permanentInputNoRetry": backend_passed,
            "artifactPoolBlock": backend_passed,
            "failureAffinityCooldown": backend_passed,
            "taskRunBudgetNotReset": "countersResetOnNewAttempt: false" in policy_yaml,
            "cloudFallbackBudgetGate": "task_run_cloud_budget_exhausted" in cloud,
            "forbiddenSchedulerAbsentInLib": forbidden["passed"],
            "integrationHarness": "NOT_RUN",
        },
        "gaps": [
            "T14 exhausted Attempt then new Attempt end-to-end harness NOT_RUN",
            "No eligible Worker saturation scenario NOT_RUN",
            "Physical-device thermal repeat certification NOT_RUN",
        ],
        "errors": errors,
    }

    out_path = ROOT / "plan/evidence/phase-08-p8-a14-scoped-retry-affinity.json"
    out_path.write_text(json.dumps(evidence, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(evidence, indent=2))
    return 0 if evidence["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
