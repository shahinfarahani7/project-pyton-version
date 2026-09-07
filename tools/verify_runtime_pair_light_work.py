#!/usr/bin/env python3
"""Verify runtime-pair conflicts and bounded light work for P8-A13 / T13."""

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
        "runtimeCompatibilityDsl": ROOT / "dsl/catalog/runtime-compatibility/production-v1.yaml",
        "exclusiveGroupsDsl": ROOT / "dsl/policies/scheduling/production-exclusive-groups-v1.yaml",
        "runtimeCompatibilityModule": ROOT / "src/backend/edgemint/routing/runtime_compatibility.py",
        "exclusiveGroupsModule": ROOT / "src/backend/edgemint/routing/exclusive_groups.py",
        "workerEnforcer": ROOT / "src/apps/worker/lib/runtime/runtime_exclusive_group_enforcer.dart",
        "backendT13Tests": ROOT / "src/backend/tests/routing/test_runtime_pair_light_work.py",
        "backendAdaptiveTests": ROOT / "src/backend/tests/routing/test_adaptive_execution.py",
        "backendExclusiveTests": ROOT / "src/backend/tests/routing/test_exclusive_group_enforcement.py",
        "workerEnforcerTests": ROOT
        / "src/apps/worker/test/runtime/runtime_exclusive_group_enforcer_test.dart",
        "certificationRunbook": ROOT
        / "docs/08-sre/runbooks/RB-022-adaptive-concurrency-certification.md",
    }
    for label, path in artifacts.items():
        if not path.is_file():
            errors.append(f"missing artifact ({label}): {path.relative_to(ROOT)}")

    compat_yaml = (
        artifacts["runtimeCompatibilityDsl"].read_text(encoding="utf-8")
        if artifacts["runtimeCompatibilityDsl"].is_file()
        else ""
    )
    for token in (
        "llm_and_vlm_exclusive",
        "mediapipe_llm",
        "vlm_runtime",
        "network_io",
    ):
        if token not in compat_yaml:
            errors.append(f"runtime compatibility DSL missing token: {token}")

    groups_yaml = (
        artifacts["exclusiveGroupsDsl"].read_text(encoding="utf-8")
        if artifacts["exclusiveGroupsDsl"].is_file()
        else ""
    )
    for token in (
        "lightWorkGroups:",
        "qwen_plus_vlm_blocked_v1",
        "light_work_during_heavy_inference",
        "certificationRequired: true",
    ):
        if token not in groups_yaml:
            errors.append(f"exclusive groups DSL missing token: {token}")

    enforcer = (
        artifacts["workerEnforcer"].read_text(encoding="utf-8")
        if artifacts["workerEnforcer"].is_file()
        else ""
    )
    for token in (
        "llmOcrConcurrentCertified",
        "withHeavyLlmInference",
        "withOcrInference",
    ):
        if token not in enforcer:
            errors.append(f"worker enforcer missing token: {token}")

    backend_test = subprocess.run(
        [
            sys.executable,
            "-m",
            "pytest",
            str(artifacts["backendT13Tests"]),
            str(artifacts["backendAdaptiveTests"]),
            str(artifacts["backendExclusiveTests"]),
            "-q",
        ],
        cwd=ROOT / "src/backend",
        capture_output=True,
        text=True,
    )
    backend_passed = backend_test.returncode == 0
    if not backend_passed:
        errors.append("backend pytest failed for runtime pair / light work")
        errors.append(backend_test.stdout[-1500:])
        errors.append(backend_test.stderr[-1500:])

    worker_passed = False
    worker_skipped = False
    try:
        worker_test = subprocess.run(
            ["flutter", "test", str(artifacts["workerEnforcerTests"])],
            cwd=ROOT / "src/apps/worker",
            capture_output=True,
            text=True,
        )
        worker_passed = worker_test.returncode == 0
        if not worker_passed:
            errors.append("flutter test failed for runtime exclusive group enforcer")
            if worker_test.stderr.strip():
                errors.append(worker_test.stderr[-1000:])
    except FileNotFoundError:
        worker_skipped = True

    evidence = {
        "status": "passed" if not errors else "failed",
        "taskId": "P8-A13",
        "auditId": "A13",
        "acceptanceCase": "T13",
        "architectureVersion": "2.0",
        "sourceSections": ["29", "30", "31", "32", "35", "64"],
        "generatedAt": datetime.now(UTC).isoformat(),
        "commitSha": _git_sha(),
        "classification": "IMPLEMENTED_DEV_ONLY",
        "artifacts": {
            k: str(v.relative_to(ROOT)).replace("\\", "/") for k, v in artifacts.items()
        },
        "t13Scenario": {
            "title": "Qwen+VLM, OCR pair, certified Qwen+OCR, control-message load",
            "qwenVlmBlocked": backend_passed,
            "certifiedQwenOcrPair": backend_passed,
            "lightWorkDuringHeavy": backend_passed,
            "workerExclusiveEnforcer": (
                worker_passed if not worker_skipped else "SKIPPED_FLUTTER_UNAVAILABLE"
            ),
            "integrationHarness": "NOT_RUN",
        },
        "gaps": [
            "T13 large Upload/JSON/hash control-message load harness NOT_RUN",
            "Physical-device Qwen+VLM conflict certification NOT_RUN",
            "Transfer load responsiveness under total resource caps NOT_RUN",
        ],
        "errors": errors,
    }

    out_path = ROOT / "plan/evidence/phase-08-p8-a13-runtime-pair-light-work.json"
    out_path.write_text(json.dumps(evidence, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(evidence, indent=2))
    return 0 if evidence["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
