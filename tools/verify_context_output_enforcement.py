#!/usr/bin/env python3
"""Verify artifact-bound Context and output enforcement for P8-A10 / T10."""

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
        "contextProfileRegistry": ROOT / "src/backend/edgemint/routing/context_profile_registry.py",
        "contextBudget": ROOT / "src/backend/edgemint/routing/context_budget.py",
        "executionAllocationCap": ROOT / "src/backend/edgemint/routing/execution_allocation.py",
        "workerContextManager": ROOT / "src/apps/worker/lib/inference/llm/context_budget_manager.dart",
        "formattedPromptBuilder": ROOT / "src/apps/worker/lib/inference/llm/formatted_prompt_builder.dart",
        "outputLimitEnforcer": ROOT / "src/apps/worker/lib/inference/llm/output_limit_enforcer.dart",
        "qwenProcessor": ROOT / "src/apps/worker/lib/inference/llm/qwen_task_processor.dart",
        "backendTests": ROOT / "src/backend/tests/routing/test_context_budget.py",
        "workerBoundaryTests": ROOT
        / "src/apps/worker/test/inference/llm/formatted_prompt_boundary_test.dart",
        "legacyContextTests": ROOT
        / "src/apps/worker/test/inference/llm/context_budget_manager_test.dart",
    }
    for label, path in artifacts.items():
        if not path.is_file():
            errors.append(f"missing artifact ({label}): {path.relative_to(ROOT)}")

    profile_yaml = (
        artifacts["contextProfileDsl"].read_text(encoding="utf-8")
        if artifacts["contextProfileDsl"].is_file()
        else ""
    )
    for token in (
        "verifiedArtifactContextLimit: 1280",
        "requiresFormattedPromptCount: true",
        "enforceMaxOutputTokens: true",
    ):
        if token not in profile_yaml:
            errors.append(f"context profile DSL missing token: {token}")

    worker_catalog = (
        ROOT / "src/apps/worker/lib/models/worker_model_catalog.dart"
    ).read_text(encoding="utf-8")
    if "verifiedArtifactContextLimit = 1280" not in worker_catalog:
        errors.append("worker model catalog missing artifact context limit")

    backend_test = subprocess.run(
        [sys.executable, "-m", "pytest", str(artifacts["backendTests"]), "-q"],
        cwd=ROOT / "src/backend",
        capture_output=True,
        text=True,
    )
    backend_passed = backend_test.returncode == 0
    if not backend_passed:
        errors.append("backend pytest failed for context budget tests")
        errors.append(backend_test.stdout[-1500:])
        errors.append(backend_test.stderr[-1500:])

    worker_passed = False
    worker_skipped = False
    for test_path in (
        artifacts["workerBoundaryTests"],
        artifacts["legacyContextTests"],
    ):
        try:
            worker_test = subprocess.run(
                ["flutter", "test", str(test_path)],
                cwd=ROOT / "src/apps/worker",
                capture_output=True,
                text=True,
            )
            if worker_test.returncode != 0:
                errors.append(f"flutter test failed: {test_path.name}")
                if worker_test.stderr.strip():
                    errors.append(worker_test.stderr[-1000:])
                worker_passed = False
                break
            worker_passed = True
        except FileNotFoundError:
            worker_skipped = True
            worker_passed = False
            break

    evidence = {
        "status": "passed" if not errors else "failed",
        "taskId": "P8-A10",
        "auditId": "A10",
        "acceptanceCase": "T10",
        "architectureVersion": "2.0",
        "sourceSections": ["4", "25", "32"],
        "generatedAt": datetime.now(UTC).isoformat(),
        "commitSha": _git_sha(),
        "classification": "IMPLEMENTED_DEV_ONLY",
        "artifacts": {k: str(v.relative_to(ROOT)).replace("\\", "/") for k, v in artifacts.items()},
        "t10Scenario": {
            "title": "Multilingual/JSON near context edge; template and truncation",
            "artifactBoundEffectiveLimit": backend_passed,
            "formattedPromptBoundaryTests": (
                worker_passed if not worker_skipped else "SKIPPED_FLUTTER_UNAVAILABLE"
            ),
            "outputLimitEnforcement": "output_limit_enforcer.dart",
            "integrationHarness": "NOT_RUN",
        },
        "gaps": [
            "T10 native tokenizer exact-count integration harness NOT_RUN",
            "Runtime stop mechanism certification on physical device NOT_RUN",
        ],
        "errors": errors,
    }

    out_path = ROOT / "plan/evidence/phase-08-p8-a10-context-output-enforcement.json"
    out_path.write_text(json.dumps(evidence, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(evidence, indent=2))
    return 0 if evidence["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
