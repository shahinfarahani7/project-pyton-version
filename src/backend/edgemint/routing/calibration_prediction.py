"""Versioned calibration and prediction (Architecture v2 §13, §33, §34, A20/T20)."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from enum import StrEnum
from pathlib import Path
from typing import Any

import yaml

from edgemint.workers.calibration import CalibrationMetrics
from edgemint.workers.execution_cost_feedback import ExecutionCostFeedbackPayload

DEFAULT_POLICY_PATH = (
    Path(__file__).resolve().parents[4]
    / "dsl"
    / "policies"
    / "calibration"
    / "versioned-prediction-v1.yaml"
)

DEFAULT_CONSERVATIVE_FACTOR_BPS = 15_000
DEFAULT_FACTOR_BPS = 10_000


class PredictionPhase(StrEnum):
    COLD = "cold"
    WARM = "warm"


@dataclass(frozen=True, slots=True)
class CalibrationProfileIdentity:
    suite_version: str
    profile_version: int
    measured_at_utc: datetime
    artifact_id: str | None = None
    runtime_version: str | None = None

    def as_dict(self) -> dict[str, Any]:
        payload: dict[str, Any] = {
            "suiteVersion": self.suite_version,
            "profileVersion": self.profile_version,
            "measuredAtUtc": self.measured_at_utc.isoformat(),
        }
        if self.artifact_id is not None:
            payload["artifactId"] = self.artifact_id
        if self.runtime_version is not None:
            payload["runtimeVersion"] = self.runtime_version
        return payload


@dataclass(frozen=True, slots=True)
class VersionedPredictionRecord:
    estimator_version: str
    calibration_identity: CalibrationProfileIdentity | None
    prediction_phase: PredictionPhase
    calibration_factor_bps: int
    predicted_duration_ms: int
    predicted_peak_memory_bytes: int
    uncertainty_margin_bps: int
    profile_expired: bool
    used_conservative_fallback: bool

    def as_dict(self) -> dict[str, Any]:
        return {
            "estimatorVersion": self.estimator_version,
            "predictionPhase": self.prediction_phase.value,
            "calibrationFactorBps": self.calibration_factor_bps,
            "predictedDurationMs": self.predicted_duration_ms,
            "predictedPeakMemoryBytes": self.predicted_peak_memory_bytes,
            "uncertaintyMarginBps": self.uncertainty_margin_bps,
            "profileExpired": self.profile_expired,
            "usedConservativeFallback": self.used_conservative_fallback,
            "calibrationIdentity": (
                self.calibration_identity.as_dict() if self.calibration_identity else None
            ),
        }


@dataclass(frozen=True, slots=True)
class FrozenExecutionGrant:
    allocation_id: str
    predicted_duration_ms: int
    predicted_peak_memory_bytes: int


def load_versioned_prediction_policy(path: Path | None = None) -> dict[str, Any]:
    policy_path = path or DEFAULT_POLICY_PATH
    raw = yaml.safe_load(policy_path.read_text(encoding="utf-8"))
    if not isinstance(raw, dict):
        raise ValueError(f"invalid versioned prediction policy: {policy_path}")
    return raw


def evaluate_profile_freshness(
    *,
    measured_at: datetime,
    now: datetime,
    max_age_days: int,
) -> bool:
    measured = measured_at if measured_at.tzinfo else measured_at.replace(tzinfo=UTC)
    current = now if now.tzinfo else now.replace(tzinfo=UTC)
    return current - measured <= timedelta(days=max(1, int(max_age_days)))


def profile_matches_runtime_identity(
    *,
    identity: CalibrationProfileIdentity,
    active_artifact_id: str | None,
    active_runtime_version: str | None,
) -> bool:
    if identity.artifact_id and active_artifact_id and identity.artifact_id != active_artifact_id:
        return False
    if (
        identity.runtime_version
        and active_runtime_version
        and identity.runtime_version != active_runtime_version
    ):
        return False
    return True


def resolve_prediction_phase(*, model_resident: bool, warmup_completed: bool) -> PredictionPhase:
    if model_resident and warmup_completed:
        return PredictionPhase.WARM
    return PredictionPhase.COLD


def calibration_factor_from_metrics(metrics: CalibrationMetrics) -> float:
    decode = max(metrics.llmDecodeTokensPerSec, 1)
    stability = max(metrics.runtimeStabilityScoreMilli, 1)
    return min(2.0, max(0.5, (decode / 100.0) * (stability / 1000.0)))


def calibration_factor_to_bps(factor: float) -> int:
    return max(5000, min(20_000, int(factor * 10_000)))


def resolve_calibration_factor_bps(
    *,
    metrics: CalibrationMetrics | None,
    identity: CalibrationProfileIdentity | None,
    measured_at: datetime | None,
    now: datetime,
    policy: dict[str, Any] | None = None,
    active_artifact_id: str | None = None,
    active_runtime_version: str | None = None,
) -> tuple[int, bool, bool]:
    """Return (factor_bps, profile_expired, used_conservative_fallback)."""
    loaded = policy or load_versioned_prediction_policy()
    profile_cfg = loaded.get("calibrationProfile") or {}
    conservative = int(profile_cfg.get("conservativeFallbackFactorBps", DEFAULT_CONSERVATIVE_FACTOR_BPS))
    max_age_days = int(profile_cfg.get("maxAgeDays", 30))

    if metrics is None or identity is None or measured_at is None:
        return conservative, True, True

    fresh = evaluate_profile_freshness(
        measured_at=measured_at,
        now=now,
        max_age_days=max_age_days,
    )
    identity_ok = profile_matches_runtime_identity(
        identity=identity,
        active_artifact_id=active_artifact_id,
        active_runtime_version=active_runtime_version,
    )
    if not fresh or not identity_ok:
        return conservative, not fresh, True

    return calibration_factor_to_bps(calibration_factor_from_metrics(metrics)), False, False


def adjust_duration_for_phase(
    *,
    base_duration_ms: int,
    phase: PredictionPhase,
    warmup_ms: int,
) -> int:
    if phase == PredictionPhase.COLD:
        return max(1, int(base_duration_ms) + max(0, int(warmup_ms)))
    return max(1, int(base_duration_ms))


def assert_comparable_prediction_observation(
    *,
    predicted_phase: PredictionPhase,
    observed_phase: PredictionPhase,
) -> bool:
    return predicted_phase == observed_phase


def build_versioned_prediction(
    *,
    base_duration_ms: int,
    base_peak_memory_bytes: int,
    metrics: CalibrationMetrics | None,
    identity: CalibrationProfileIdentity | None,
    measured_at: datetime | None,
    phase: PredictionPhase,
    now: datetime | None = None,
    policy: dict[str, Any] | None = None,
    active_artifact_id: str | None = None,
    active_runtime_version: str | None = None,
) -> VersionedPredictionRecord:
    loaded = policy or load_versioned_prediction_policy()
    estimator_version = str((loaded.get("estimator") or {}).get("version", "envelope-v1"))
    clock = now or datetime.now(UTC)

    factor_bps, expired, conservative = resolve_calibration_factor_bps(
        metrics=metrics,
        identity=identity,
        measured_at=measured_at,
        now=clock,
        policy=loaded,
        active_artifact_id=active_artifact_id,
        active_runtime_version=active_runtime_version,
    )
    warmup_ms = metrics.llmWarmupMs if metrics is not None else 4000
    duration = adjust_duration_for_phase(
        base_duration_ms=max(1, (base_duration_ms * factor_bps) // DEFAULT_FACTOR_BPS),
        phase=phase,
        warmup_ms=warmup_ms,
    )
    uncertainty = 2000 if conservative else 1000
    if phase == PredictionPhase.COLD:
        uncertainty += 500
    return VersionedPredictionRecord(
        estimator_version=estimator_version,
        calibration_identity=identity,
        prediction_phase=phase,
        calibration_factor_bps=factor_bps,
        predicted_duration_ms=duration,
        predicted_peak_memory_bytes=max(1, int(base_peak_memory_bytes)),
        uncertainty_margin_bps=uncertainty,
        profile_expired=expired,
        used_conservative_fallback=conservative,
    )


def apply_feedback_to_future_predictions_only(
    *,
    frozen_grant: FrozenExecutionGrant,
    feedback: ExecutionCostFeedbackPayload,
    current_factor_bps: int,
    policy: dict[str, Any] | None = None,
) -> tuple[int, FrozenExecutionGrant]:
    """Adjust future calibration factor without retroactively enlarging the frozen grant."""
    loaded = policy or load_versioned_prediction_policy()
    threshold = int((loaded.get("feedback") or {}).get("underestimateThresholdRatioMilli", 1100))

    future_factor = current_factor_bps
    if feedback.variance.durationRatioMilli >= threshold:
        future_factor = min(
            20_000,
            max(current_factor_bps, current_factor_bps * feedback.variance.durationRatioMilli // 1000),
        )

    unchanged = FrozenExecutionGrant(
        allocation_id=frozen_grant.allocation_id,
        predicted_duration_ms=frozen_grant.predicted_duration_ms,
        predicted_peak_memory_bytes=frozen_grant.predicted_peak_memory_bytes,
    )
    return future_factor, unchanged
