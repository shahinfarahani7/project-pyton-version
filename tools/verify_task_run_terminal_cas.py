#!/usr/bin/env python3
"""Verify TaskRun terminal CAS artifacts for P8-A01 / T01."""

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
    sql_path = ROOT / "database/sql/025_task_runs_terminal_cas.sql"
    service_path = ROOT / "src/backend/edgemint/tasks/task_run.py"
    assignments_path = ROOT / "src/backend/edgemint/workers/assignments.py"
    admission_path = ROOT / "src/backend/edgemint/tasks/admission.py"
    test_path = ROOT / "src/backend/tests/tasks/test_task_run_terminal_cas.py"

    for path in (sql_path, service_path, assignments_path, admission_path, test_path):
        if not path.is_file():
            errors.append(f"missing artifact: {path.relative_to(ROOT)}")

    if sql_path.is_file():
        sql = sql_path.read_text(encoding="utf-8")
        for token in (
            "CREATE TABLE IF NOT EXISTS public.task_runs",
            "commit_task_run_terminal",
            "terminal_committed_at_utc IS NULL",
            "task_attempts",
            "task_run_id",
        ):
            if token not in sql:
                errors.append(f"SQL missing token: {token}")

    if service_path.is_file():
        source = service_path.read_text(encoding="utf-8")
        for token in ("TaskRunService", "commit_terminal", "create_for_admitted_task"):
            if token not in source:
                errors.append(f"service missing token: {token}")

    test_result = subprocess.run(
        [
            sys.executable,
            "-m",
            "pytest",
            str(test_path),
            "-q",
        ],
        cwd=ROOT / "src/backend",
        capture_output=True,
        text=True,
    )
    tests_passed = test_result.returncode == 0
    if not tests_passed:
        errors.append("pytest failed for test_task_run_terminal_cas.py")
        errors.append(test_result.stdout[-2000:])
        errors.append(test_result.stderr[-2000:])

    evidence = {
        "status": "passed" if not errors else "failed",
        "taskId": "P8-A01",
        "auditId": "A01",
        "acceptanceCase": "T01",
        "architectureVersion": "2.0",
        "sourceSections": ["20", "22", "23", "50", "60"],
        "generatedAt": datetime.now(UTC).isoformat(),
        "commitSha": _git_sha(),
        "classification": "IMPLEMENTED_DEV_ONLY",
        "artifacts": {
            "sql": "database/sql/025_task_runs_terminal_cas.sql",
            "service": "src/backend/edgemint/tasks/task_run.py",
            "admissionWiring": "src/backend/edgemint/tasks/admission.py",
            "assignmentWiring": "src/backend/edgemint/workers/assignments.py",
            "tests": "src/backend/tests/tasks/test_task_run_terminal_cas.py",
        },
        "t01Scenario": {
            "title": "Cancel/Complete race; one terminal commit wins",
            "unitProof": tests_passed,
            "integrationRaceHarness": "NOT_RUN",
            "note": "SQL CAS function + service wiring present; concurrent integration repro deferred.",
        },
        "gaps": [
            "task_attempts.task_run_id backfill/link on attempt creation not yet enforced",
            "VALIDATING stage before SUCCEEDED terminal commit not yet split",
            "T01 concurrent cancel+complete integration harness NOT_RUN",
        ],
        "errors": errors,
    }

    out_path = ROOT / "plan/evidence/phase-08-p8-a01-task-run-terminal-cas.json"
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(evidence, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(evidence, indent=2))
    return 0 if not errors else 1


if __name__ == "__main__":
    raise SystemExit(main())
