from __future__ import annotations

from edgemint.workers.calibration import CalibrationMetrics, evaluate_concurrency_certification
from edgemint.workers.calibration_feedback import adjust_metrics_from_feedback
from edgemint.workers.execution_cost_feedback import (
    ExecutionCostVariance,
    ObservedResourceUsage,
    PredictedResourceUsage,
    ExecutionCostFeedbackPayload,
)


def _feedback(*, ratio_milli: int, thermal_delta_bps: int = 500) -> ExecutionCostFeedbackPayload:
    predicted = PredictedResourceUsage(
        cpuUnits=40,
        peakMemoryBytes=800_000_000,
        durationMs=1000,
        energyClass="medium",
        runtimeClass="mediapipe_llm",
        calibrationFactorBps=10_000,
    )
    observed = ObservedResourceUsage(
        cpuAverageBps=2200,
        peakMemoryBytes=820_000_000,
        durationMs=(1000 * ratio_milli) // 1000,
        thermalDeltaBps=thermal_delta_bps,
    )
    variance = ExecutionCostVariance(
        durationMs=observed.durationMs - predicted.durationMs,
        peakMemoryBytes=observed.peakMemoryBytes - predicted.peakMemoryBytes,
        durationRatioMilli=ratio_milli,
    )
    return ExecutionCostFeedbackPayload(predicted=predicted, observed=observed, variance=variance)


def test_calibration_feedback_adjusts_decode_speed_when_slower_than_predicted() -> None:
    baseline = CalibrationMetrics(
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
    updated = adjust_metrics_from_feedback(baseline, _feedback(ratio_milli=1500))
    assert updated.llmDecodeTokensPerSec < baseline.llmDecodeTokensPerSec
    assert updated.ocrPageLatencyMs > baseline.ocrPageLatencyMs


def test_high_stability_profile_can_become_concurrency_certified() -> None:
    metrics = CalibrationMetrics(
        llmWarmupMs=4000,
        llmPrefillTokensPerSec=150,
        llmDecodeTokensPerSec=95,
        llmPeakMemoryBytes=1_610_612_736,
        ocrPageLatencyMs=850,
        ocrPagesPerMinute=70,
        cpuAverageBps=2100,
        thermalDeltaBps=400,
        runtimeStabilityScoreMilli=980,
    )
    assert evaluate_concurrency_certification(metrics) is True
