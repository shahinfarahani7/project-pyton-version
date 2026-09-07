from __future__ import annotations

import pytest

from edgemint.workers.errors import WorkerServiceError
from edgemint.workers.execution_cost_feedback import (
    ExecutionCostFeedbackPayload,
    ObservedResourceUsage,
    PredictedResourceUsage,
    compute_execution_cost_variance,
    parse_execution_cost_feedback,
)


def _sample_payload() -> dict[str, object]:
    predicted = PredictedResourceUsage(
        cpuUnits=40,
        peakMemoryBytes=1_610_612_736,
        durationMs=180_000,
        energyClass="medium",
        runtimeClass="mediapipe_llm",
        calibrationFactorBps=10_000,
    )
    observed = ObservedResourceUsage(
        cpuAverageBps=2100,
        peakMemoryBytes=1_835_008_000,
        durationMs=64_000,
        thermalDeltaBps=500,
        throughputPerSec=12.5,
        throughputUnit="tokens",
    )
    variance = compute_execution_cost_variance(predicted=predicted, observed=observed)
    payload = ExecutionCostFeedbackPayload(
        predicted=predicted,
        observed=observed,
        variance=variance,
    )
    return payload.model_dump()


def test_compute_execution_cost_variance_matches_architecture_section_34() -> None:
    predicted = PredictedResourceUsage(
        cpuUnits=40,
        peakMemoryBytes=1_610_612_736,
        durationMs=180_000,
        energyClass="medium",
    )
    observed = ObservedResourceUsage(
        cpuAverageBps=2100,
        peakMemoryBytes=1_835_008_000,
        durationMs=64_000,
        thermalDeltaBps=500,
    )
    variance = compute_execution_cost_variance(predicted=predicted, observed=observed)
    assert variance.durationMs == -116_000
    assert variance.peakMemoryBytes == 224_395_264
    assert variance.durationRatioMilli == 355


def test_parse_execution_cost_feedback_accepts_valid_sample() -> None:
    payload = parse_execution_cost_feedback(_sample_payload())
    assert payload.predicted.energyClass == "medium"
    assert payload.observed.throughputUnit == "tokens"
    assert payload.variance.durationRatioMilli == 355


def test_parse_execution_cost_feedback_rejects_variance_mismatch() -> None:
    raw = _sample_payload()
    raw["variance"] = {
        "durationMs": 0,
        "peakMemoryBytes": 0,
        "durationRatioMilli": 0,
    }
    with pytest.raises(WorkerServiceError) as exc:
        parse_execution_cost_feedback(raw)
    assert exc.value.code == "INPUT_SCHEMA_INVALID"
