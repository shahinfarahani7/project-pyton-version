from __future__ import annotations

from dataclasses import replace

from edgemint.routing.calibration import calibration_factor_to_bps
from edgemint.routing.cost_estimator import EnvelopeTaskCostEstimator, TaskCostEstimatorInputs
from edgemint.routing.exclusive_groups import can_reserve_exclusive_group
from edgemint.routing.runtime_compatibility import is_runtime_compatible
from edgemint.workers.consent_transitions import plan_consent_revocation, plan_contribution_mode_transition
from edgemint.workers.enrollment import WorkerEnrollmentService
from edgemint.workers.resource_policy import default_contribution_mode_id


def test_default_contribution_mode_is_thirty_percent_balanced() -> None:
    assert default_contribution_mode_id() == "balanced"


def test_calibration_factor_bps_changes_prediction_duration() -> None:
    estimator = EnvelopeTaskCostEstimator()
    base_inputs = TaskCostEstimatorInputs(
        taskType="text.summarize",
        inputBytes=12_000,
        estimatedInputTokens=3000,
        pageCount=0,
        imageWidth=0,
        imageHeight=0,
        chunkCountEstimate=3,
        runtimeClass="mediapipe_llm",
        modelVersionId="qwen2.5-0.5b",
        calibrationFactorBps=10_000,
    )
    slower = estimator.estimate(
        replace(base_inputs, calibrationFactorBps=calibration_factor_to_bps(1.5))
    )
    baseline = estimator.estimate(base_inputs)
    assert slower.predictedDurationMs > baseline.predictedDurationMs


def test_certified_device_allows_llm_and_ocr_runtime_pair() -> None:
    assert is_runtime_compatible(
        worker_runtime_classes=["mediapipe_llm", "paddle_ocr"],
        task_runtime_class="paddle_ocr",
        device_tier="T3",
        active_runtime_classes=["mediapipe_llm"],
        concurrency_certified=True,
    )


def test_uncertified_device_blocks_llm_and_ocr_runtime_pair() -> None:
    assert not is_runtime_compatible(
        worker_runtime_classes=["mediapipe_llm", "paddle_ocr"],
        task_runtime_class="paddle_ocr",
        active_runtime_classes=["mediapipe_llm"],
        concurrency_certified=False,
    )


def test_certified_device_allows_ocr_during_llm_exclusive_group() -> None:
    assert can_reserve_exclusive_group(
        requested_group="ocr_inference",
        active_counts={"llm_inference": 1},
        device_certified=True,
    )


def test_fair_thermal_state_reduces_certified_ocr_concurrency() -> None:
    assert can_reserve_exclusive_group(
        requested_group="ocr_inference",
        active_counts={"ocr_inference": 1},
        device_certified=True,
        thermal_state="fair",
    ) is False


def test_consent_increase_applies_to_new_reservations_only() -> None:
    plan = plan_contribution_mode_transition(previous_mode_id="balanced", next_mode_id="performance")
    assert plan.apply_to_new_reservations_only is True
    assert plan.next_percent == 50


def test_consent_revocation_stops_new_work_immediately() -> None:
    plan = plan_consent_revocation(current_mode_id="balanced")
    assert plan.revoke_new_work_immediately is True


def test_enrollment_defaults_contribution_mode_to_balanced() -> None:
    assert WorkerEnrollmentService is not None


def test_calibration_factor_lowers_predicted_latency_score() -> None:
    from edgemint.routing.scoring_features import enrich_candidate_features_bps

    baseline = enrich_candidate_features_bps(
        {
            "featuresBps": {"predictedLatency": 9000},
            "calibrationFactorBps": 10_000,
        }
    )
    slower_device = enrich_candidate_features_bps(
        {
            "featuresBps": {"predictedLatency": 9000},
            "calibrationFactorBps": 15_000,
        }
    )
    assert slower_device["predictedLatency"] < baseline["predictedLatency"]
