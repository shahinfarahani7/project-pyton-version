from __future__ import annotations

from edgemint.runtime.runtime_upgrade_policy import (
    RuntimeBaselineSpec,
    RuntimeCandidateSpec,
    evaluate_rollback_readiness,
    evaluate_runtime_upgrade,
)


def _candidate(**overrides: object) -> RuntimeCandidateSpec:
    base = {
        "runtimeClass": "mediapipe_llm",
        "modelVersionId": "mdv_next",
        "contextLimitTokens": 1280,
        "nativeBackend": "cpu",
        "compatibilityProfileId": "production-runtime-compatibility-v1",
        "benchmarkEvidencePath": "evidence/benchmarks/qwen-v2.json",
        "rollbackVersionId": "mdv_current",
    }
    base.update(overrides)
    return RuntimeCandidateSpec.model_validate(base)


def _baseline() -> RuntimeBaselineSpec:
    return RuntimeBaselineSpec(
        runtimeClass="mediapipe_llm",
        modelVersionId="mdv_current",
        contextLimitTokens=1280,
        compatibilityProfileId="production-runtime-compatibility-v1",
    )


def test_runtime_upgrade_approved_with_rollback_and_benchmark() -> None:
    result = evaluate_runtime_upgrade(candidate=_candidate(), baseline=_baseline())
    assert result.allowed is True
    assert result.status == "approved"


def test_runtime_upgrade_rejects_missing_rollback() -> None:
    result = evaluate_runtime_upgrade(
        candidate=_candidate(rollbackVersionId=None),
        baseline=_baseline(),
    )
    assert result.allowed is False
    assert result.status == "rollback_required"


def test_runtime_upgrade_rejects_open_sessions() -> None:
    result = evaluate_runtime_upgrade(
        candidate=_candidate(),
        baseline=_baseline(),
        open_sessions=1,
    )
    assert result.allowed is False
    assert result.rejection_reason == "open_inference_sessions"


def test_runtime_upgrade_rejects_context_increase() -> None:
    result = evaluate_runtime_upgrade(
        candidate=_candidate(contextLimitTokens=2048),
        baseline=_baseline(),
    )
    assert result.allowed is False
    assert result.rejection_reason == "context_limit_increased_without_evaluation"


def test_runtime_upgrade_rejects_missing_benchmark() -> None:
    result = evaluate_runtime_upgrade(
        candidate=_candidate(benchmarkEvidencePath=None),
        baseline=_baseline(),
    )
    assert result.allowed is False
    assert result.rejection_reason == "benchmark_evidence_missing"


def test_rollback_readiness_requires_evidence() -> None:
    assert evaluate_rollback_readiness(
        rollback_version_id="mdv_current",
        benchmark_evidence_path="evidence/benchmarks/qwen-v2.json",
    )
    assert not evaluate_rollback_readiness(
        rollback_version_id=None,
        benchmark_evidence_path="evidence/benchmarks/qwen-v2.json",
    )
