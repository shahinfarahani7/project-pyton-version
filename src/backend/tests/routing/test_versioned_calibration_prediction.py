"""T20 audit scenarios: versioned calibration/prediction (P8-A20 / A20)."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta

from edgemint.routing.calibration_prediction import (
    CalibrationProfileIdentity,
    FrozenExecutionGrant,
    PredictionPhase,
    apply_feedback_to_future_predictions_only,
    assert_comparable_prediction_observation,
    build_versioned_prediction,
    evaluate_profile_freshness,
    profile_matches_runtime_identity,
    resolve_calibration_factor_bps,
    resolve_prediction_phase,
)
from edgemint.routing.service import RouterService
from edgemint.workers.calibration import CalibrationMetrics
from edgemint.workers.execution_cost_feedback import (
    ExecutionCostFeedbackPayload,
    ExecutionCostVariance,
    ObservedResourceUsage,
    PredictedResourceUsage,
)


def _metrics() -> CalibrationMetrics:
    return CalibrationMetrics(
        llmWarmupMs=4000,
        llmPrefillTokensPerSec=150,
        llmDecodeTokensPerSec=100,
        llmPeakMemoryBytes=1_610_612_736,
        ocrPageLatencyMs=900,
        ocrPagesPerMinute=60,
        cpuAverageBps=2000,
        thermalDeltaBps=400,
        runtimeStabilityScoreMilli=980,
    )


def _identity(*, measured_at: datetime) -> CalibrationProfileIdentity:
    return CalibrationProfileIdentity(
        suite_version="2026-q3-v1",
        profile_version=3,
        measured_at_utc=measured_at,
        artifact_id="qwen2.5-0.5b-ekv1280",
        runtime_version="mediapipe-llm-v1",
    )


def test_t20_cold_prediction_includes_warmup_warm_excludes_it() -> None:
    now = datetime(2026, 9, 6, tzinfo=UTC)
    measured = now - timedelta(days=1)
    metrics = _metrics()
    identity = _identity(measured_at=measured)

    cold = build_versioned_prediction(
        base_duration_ms=10_000,
        base_peak_memory_bytes=800_000_000,
        metrics=metrics,
        identity=identity,
        measured_at=measured,
        phase=PredictionPhase.COLD,
        now=now,
    )
    warm = build_versioned_prediction(
        base_duration_ms=10_000,
        base_peak_memory_bytes=800_000_000,
        metrics=metrics,
        identity=identity,
        measured_at=measured,
        phase=PredictionPhase.WARM,
        now=now,
    )
    assert cold.predicted_duration_ms > warm.predicted_duration_ms
    assert cold.prediction_phase == PredictionPhase.COLD
    assert warm.prediction_phase == PredictionPhase.WARM


def test_t20_cold_and_warm_observations_are_not_cross_compared() -> None:
    assert assert_comparable_prediction_observation(
        predicted_phase=PredictionPhase.COLD,
        observed_phase=PredictionPhase.WARM,
    ) is False
    assert assert_comparable_prediction_observation(
        predicted_phase=PredictionPhase.WARM,
        observed_phase=PredictionPhase.WARM,
    ) is True


def test_t20_aged_profile_uses_conservative_fallback() -> None:
    now = datetime(2026, 9, 6, tzinfo=UTC)
    measured = now - timedelta(days=45)
    identity = _identity(measured_at=measured)
    assert evaluate_profile_freshness(measured_at=measured, now=now, max_age_days=30) is False

    factor_bps, expired, conservative = resolve_calibration_factor_bps(
        metrics=_metrics(),
        identity=identity,
        measured_at=measured,
        now=now,
    )
    assert expired is True
    assert conservative is True
    assert factor_bps == 15_000


def test_t20_changed_artifact_invalidates_profile_identity() -> None:
    identity = _identity(measured_at=datetime(2026, 9, 1, tzinfo=UTC))
    assert profile_matches_runtime_identity(
        identity=identity,
        active_artifact_id="qwen2.5-0.5b-ekv1280",
        active_runtime_version="mediapipe-llm-v1",
    )
    assert profile_matches_runtime_identity(
        identity=identity,
        active_artifact_id="qwen2.5-0.5b-ekv2048",
        active_runtime_version="mediapipe-llm-v1",
    ) is False


def test_t20_underestimated_peak_updates_future_factor_not_frozen_grant() -> None:
    frozen = FrozenExecutionGrant(
        allocation_id="alloc_1",
        predicted_duration_ms=1000,
        predicted_peak_memory_bytes=800_000_000,
    )
    feedback = ExecutionCostFeedbackPayload(
        predicted=PredictedResourceUsage(
            cpuUnits=40,
            peakMemoryBytes=800_000_000,
            durationMs=1000,
            energyClass="medium",
        ),
        observed=ObservedResourceUsage(
            cpuAverageBps=2200,
            peakMemoryBytes=1_200_000_000,
            durationMs=1800,
            thermalDeltaBps=500,
        ),
        variance=ExecutionCostVariance(
            durationMs=800,
            peakMemoryBytes=400_000_000,
            durationRatioMilli=1800,
        ),
    )
    future_factor, unchanged = apply_feedback_to_future_predictions_only(
        frozen_grant=frozen,
        feedback=feedback,
        current_factor_bps=10_000,
    )
    assert future_factor > 10_000
    assert unchanged.predicted_duration_ms == 1000
    assert unchanged.predicted_peak_memory_bytes == 800_000_000


def test_t20_router_exposes_versioned_prediction_record() -> None:
    router = RouterService()
    record = router.build_versioned_prediction_record(
        base_duration_ms=12_000,
        base_peak_memory_bytes=900_000_000,
        model_resident=True,
        warmup_completed=True,
    )
    assert record["predictionPhase"] == PredictionPhase.WARM.value
    assert record["estimatorVersion"] == "envelope-v1"
    assert resolve_prediction_phase(model_resident=False, warmup_completed=False) == PredictionPhase.COLD
