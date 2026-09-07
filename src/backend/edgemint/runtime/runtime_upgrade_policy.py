"""Runtime maintenance and evaluated upgrade/rollback policy (v2 A24 / T24)."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Any, Literal

import yaml
from pydantic import BaseModel, Field

DEFAULT_POLICY_PATH = (
    Path(__file__).resolve().parents[4]
    / "dsl"
    / "policies"
    / "runtime"
    / "runtime-maintenance-upgrade-v1.yaml"
)

EvaluationStatus = Literal["approved", "rejected", "rollback_required"]
DimensionStatus = Literal["pass", "fail", "not_run"]


class RuntimeCandidateSpec(BaseModel):
    runtimeClass: str = Field(min_length=1)
    modelVersionId: str | None = None
    contextLimitTokens: int = Field(default=1280, ge=1)
    nativeBackend: str = Field(default="cpu", min_length=1)
    compatibilityProfileId: str = Field(min_length=1)
    benchmarkEvidencePath: str | None = None
    rollbackVersionId: str | None = None

    model_config = {"extra": "forbid"}


class RuntimeBaselineSpec(BaseModel):
    runtimeClass: str = Field(min_length=1)
    modelVersionId: str | None = None
    contextLimitTokens: int = Field(default=1280, ge=1)
    compatibilityProfileId: str = Field(min_length=1)

    model_config = {"extra": "forbid"}


@dataclass(frozen=True)
class DimensionResult:
    dimension: str
    status: DimensionStatus
    detail: str


@dataclass(frozen=True)
class RuntimeUpgradeEvaluation:
    status: EvaluationStatus
    allowed: bool
    dimensions: tuple[DimensionResult, ...]
    rejection_reason: str | None
    requires_rollback_first: bool


def load_runtime_upgrade_policy(path: Path | None = None) -> dict[str, Any]:
    policy_path = path or DEFAULT_POLICY_PATH
    raw = yaml.safe_load(policy_path.read_text(encoding="utf-8"))
    if not isinstance(raw, dict):
        raise ValueError(f"invalid runtime upgrade policy: {policy_path}")
    return raw


def _evaluate_dimension(
    *,
    dimension: str,
    candidate: RuntimeCandidateSpec,
    baseline: RuntimeBaselineSpec,
    open_sessions: int,
    install_in_progress: bool,
    policy: dict[str, Any],
) -> DimensionResult:
    evaluation = policy.get("upgradeEvaluation") or {}
    if dimension == "artifact_conversion":
        if candidate.modelVersionId and candidate.modelVersionId == baseline.modelVersionId:
            return DimensionResult(dimension, "pass", "same_model_version")
        if not candidate.rollbackVersionId:
            return DimensionResult(dimension, "fail", "rollback_version_required")
        return DimensionResult(dimension, "pass", "candidate_with_rollback")
    if dimension == "lifecycle":
        if install_in_progress and evaluation.get("blockConcurrentInstall", True):
            return DimensionResult(dimension, "fail", "concurrent_install_blocked")
        if open_sessions > 0 and evaluation.get("blockUpgradeDuringOpenSessions", True):
            return DimensionResult(dimension, "fail", "open_inference_sessions")
        return DimensionResult(dimension, "pass", "lifecycle_clear")
    if dimension == "context":
        if candidate.contextLimitTokens > baseline.contextLimitTokens:
            return DimensionResult(dimension, "fail", "context_limit_increased_without_evaluation")
        return DimensionResult(dimension, "pass", "context_within_baseline")
    if dimension == "memory":
        if candidate.nativeBackend not in {"cpu", "gpu"}:
            return DimensionResult(dimension, "fail", "unsupported_backend")
        return DimensionResult(dimension, "pass", "backend_supported")
    if dimension == "quality":
        if not candidate.benchmarkEvidencePath:
            return DimensionResult(dimension, "fail", "benchmark_evidence_missing")
        return DimensionResult(dimension, "pass", "benchmark_evidence_present")
    if dimension == "cancellation":
        if candidate.compatibilityProfileId != baseline.compatibilityProfileId:
            return DimensionResult(dimension, "not_run", "profile_change_requires_device_certification")
        return DimensionResult(dimension, "pass", "profile_unchanged")
    return DimensionResult(dimension, "not_run", "unknown_dimension")


def evaluate_runtime_upgrade(
    *,
    candidate: RuntimeCandidateSpec,
    baseline: RuntimeBaselineSpec,
    open_sessions: int = 0,
    install_in_progress: bool = False,
    policy: dict[str, Any] | None = None,
) -> RuntimeUpgradeEvaluation:
    loaded = policy or load_runtime_upgrade_policy()
    evaluation = loaded.get("upgradeEvaluation") or {}
    dimensions_config = list(evaluation.get("evaluationDimensions") or [])
    results = [
        _evaluate_dimension(
            dimension=str(dimension),
            candidate=candidate,
            baseline=baseline,
            open_sessions=open_sessions,
            install_in_progress=install_in_progress,
            policy=loaded,
        )
        for dimension in dimensions_config
    ]

    failed = [result for result in results if result.status == "fail"]
    if failed:
        reason = failed[0].detail
        requires_rollback = bool(loaded.get("rollbackPolicy", {}).get("rollbackBeforeForwardAdoption", True))
        status: EvaluationStatus = (
            "rollback_required" if reason == "rollback_version_required" else "rejected"
        )
        return RuntimeUpgradeEvaluation(
            status=status,
            allowed=False,
            dimensions=tuple(results),
            rejection_reason=reason,
            requires_rollback_first=requires_rollback,
        )

    if evaluation.get("requireRollbackVersionBeforeAdoption", True) and not candidate.rollbackVersionId:
        return RuntimeUpgradeEvaluation(
            status="rollback_required",
            allowed=False,
            dimensions=tuple(results),
            rejection_reason="rollback_version_required",
            requires_rollback_first=True,
        )

    return RuntimeUpgradeEvaluation(
        status="approved",
        allowed=True,
        dimensions=tuple(results),
        rejection_reason=None,
        requires_rollback_first=False,
    )


def evaluate_rollback_readiness(
    *,
    rollback_version_id: str | None,
    benchmark_evidence_path: str | None,
    policy: dict[str, Any] | None = None,
) -> bool:
    loaded = policy or load_runtime_upgrade_policy()
    evaluation = loaded.get("upgradeEvaluation") or {}
    if evaluation.get("requireRollbackVersionBeforeAdoption", True) and not rollback_version_id:
        return False
    if evaluation.get("requireBenchmarkEvidence", True) and not benchmark_evidence_path:
        return False
    return True
