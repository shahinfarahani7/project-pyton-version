#!/usr/bin/env python3
"""Verify bounded hierarchical reduce and semantic merge for P8-A11 / T11."""

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
        "executionPlanDsl": ROOT / "dsl/catalog/execution-plans/text-summarize-map-reduce.yaml",
        "reducePolicy": ROOT / "src/backend/edgemint/routing/hierarchical_reduce_policy.py",
        "workerPipeline": ROOT
        / "src/apps/worker/lib/inference/llm/hierarchical_summarize_pipeline.dart",
        "workerBounds": ROOT / "src/apps/worker/lib/inference/llm/hierarchical_reduce_bounds.dart",
        "semanticMerge": ROOT / "src/apps/worker/lib/inference/llm/semantic_merge_validator.dart",
        "failureEvidence": ROOT / "src/apps/worker/lib/runtime/failure_evidence.dart",
        "backendTests": ROOT / "src/backend/tests/routing/test_hierarchical_reduce_bounds.py",
        "workerTests": ROOT
        / "src/apps/worker/test/inference/llm/hierarchical_reduce_bounds_test.dart",
        "legacyPipelineTests": ROOT
        / "src/apps/worker/test/inference/llm/hierarchical_summarize_pipeline_test.dart",
    }
    for label, path in artifacts.items():
        if not path.is_file():
            errors.append(f"missing artifact ({label}): {path.relative_to(ROOT)}")

    plan_yaml = (
        artifacts["executionPlanDsl"].read_text(encoding="utf-8")
        if artifacts["executionPlanDsl"].is_file()
        else ""
    )
    for token in (
        "reduceBounds:",
        "maxReduceDepth:",
        "maxInferenceCalls:",
        "progressRule:",
    ):
        if token not in plan_yaml:
            errors.append(f"execution plan DSL missing token: {token}")

    pipeline = (
        artifacts["workerPipeline"].read_text(encoding="utf-8")
        if artifacts["workerPipeline"].is_file()
        else ""
    )
    for token in (
        "ReduceProgressTracker",
        "SemanticMergeValidator.assertDirectReduceProgress",
        "HierarchicalReduceExhaustedException",
    ):
        if token not in pipeline:
            errors.append(f"pipeline missing token: {token}")

    backend_test = subprocess.run(
        [sys.executable, "-m", "pytest", str(artifacts["backendTests"]), "-q"],
        cwd=ROOT / "src/backend",
        capture_output=True,
        text=True,
    )
    backend_passed = backend_test.returncode == 0
    if not backend_passed:
        errors.append("backend pytest failed for hierarchical reduce bounds")
        errors.append(backend_test.stdout[-1500:])
        errors.append(backend_test.stderr[-1500:])

    worker_passed = False
    worker_skipped = False
    for test_path in (artifacts["workerTests"], artifacts["legacyPipelineTests"]):
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
        "taskId": "P8-A11",
        "auditId": "A11",
        "acceptanceCase": "T11",
        "architectureVersion": "2.0",
        "sourceSections": ["14", "26", "27", "48"],
        "generatedAt": datetime.now(UTC).isoformat(),
        "commitSha": _git_sha(),
        "classification": "IMPLEMENTED_DEV_ONLY",
        "artifacts": {k: str(v.relative_to(ROOT)).replace("\\", "/") for k, v in artifacts.items()},
        "t11Scenario": {
            "title": "Reduce fan-in; very long document; non-shrinking Reduce",
            "boundedDepthAndCalls": backend_passed,
            "nonShrinkingReduceDetected": backend_passed,
            "workerBoundsTests": (
                worker_passed if not worker_skipped else "SKIPPED_FLUTTER_UNAVAILABLE"
            ),
            "integrationHarness": "NOT_RUN",
        },
        "gaps": [
            "T11 very-long-document end-to-end integration harness NOT_RUN",
            "Physical-device reduce fan-in certification NOT_RUN",
        ],
        "errors": errors,
    }

    out_path = ROOT / "plan/evidence/phase-08-p8-a11-hierarchical-reduce-bounds.json"
    out_path.write_text(json.dumps(evidence, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(evidence, indent=2))
    return 0 if evidence["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
