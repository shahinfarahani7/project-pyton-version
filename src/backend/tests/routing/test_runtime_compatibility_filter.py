from __future__ import annotations

from edgemint.routing.engine import evaluate_candidate
from edgemint.routing.runtime_compatibility import (
    is_runtime_compatible,
    runtime_incompatibility_reasons,
    task_runtime_class_for_task_type,
)
from edgemint.routing.service import RouterService


def _eligible_candidate(**overrides: object) -> dict[str, object]:
    base: dict[str, object] = {
        "featuresBps": {
            "modelLocality": 10000,
            "trust": 10000,
            "predictedLatency": 10000,
            "batteryCharging": 10000,
            "network": 10000,
            "regionalCompliance": 10000,
            "priceEfficiency": 10000,
            "reliability": 10000,
        },
        "heartbeatAgeSeconds": 1,
        "batteryPercent": 100,
        "thermalState": "nominal",
        "attested": True,
        "consentCurrent": True,
        "modelDigestMatch": True,
        "runtimeAbiMatch": True,
        "regionAllowed": True,
        "networkPolicyAllowed": True,
        "available": True,
    }
    base.update(overrides)
    return base


def test_text_summarize_maps_to_mediapipe_llm_runtime() -> None:
    assert task_runtime_class_for_task_type("text.summarize") == "mediapipe_llm"


def test_worker_without_llm_runtime_is_incompatible_for_summarize_task() -> None:
    reasons = runtime_incompatibility_reasons(
        worker_runtime_classes=["paddle_ocr", "system"],
        task_runtime_class="mediapipe_llm",
        device_tier="T4",
    )
    assert "RUNTIME_INCOMPATIBLE" in reasons
    assert is_runtime_compatible(
        worker_runtime_classes=["paddle_ocr", "system"],
        task_runtime_class="mediapipe_llm",
        device_tier="T4",
    ) is False


def test_evaluate_candidate_marks_incompatible_runtime_ineligible() -> None:
    result = evaluate_candidate(
        _eligible_candidate(
            workerRuntimeClasses=["paddle_ocr"],
            taskRuntimeClass="mediapipe_llm",
            deviceTier="T4",
        )
    )
    assert result["eligible"] is False
    assert "RUNTIME_INCOMPATIBLE" in result["ineligibilityReasons"]


def test_router_service_blocks_incompatible_assignment_pair() -> None:
    service = RouterService()
    assert service.runtime_compatible_for_task(
        worker_runtime_classes=["paddle_ocr", "system"],
        task_type="text.summarize",
        device_tier="T4",
    ) is False
    assert service.runtime_compatible_for_task(
        worker_runtime_classes=["mediapipe_llm", "paddle_ocr", "system"],
        task_type="text.summarize",
        device_tier="T4",
    ) is True


def test_active_llm_blocks_concurrent_ocr_assignment() -> None:
    reasons = runtime_incompatibility_reasons(
        worker_runtime_classes=["mediapipe_llm", "paddle_ocr", "system"],
        task_runtime_class="paddle_ocr",
        device_tier="T4",
        active_runtime_classes=["mediapipe_llm"],
    )
    assert "RUNTIME_CO_RUN_BLOCKED" in reasons


def test_compatible_worker_stays_eligible_in_ranking() -> None:
    service = RouterService()
    ranked = service.rank_workers(
        task_id="tsk_1",
        router_epoch=1,
        candidates=[
            {
                "workerId": "wrk_ok",
                "input": _eligible_candidate(
                    workerRuntimeClasses=["mediapipe_llm", "system"],
                    taskRuntimeClass="mediapipe_llm",
                    deviceTier="T4",
                ),
            },
            {
                "workerId": "wrk_bad",
                "input": _eligible_candidate(
                    workerRuntimeClasses=["paddle_ocr"],
                    taskRuntimeClass="mediapipe_llm",
                    deviceTier="T4",
                ),
            },
        ],
    )
    by_id = {item["workerId"]: item for item in ranked}
    assert by_id["wrk_ok"]["eligible"] is True
    assert by_id["wrk_bad"]["eligible"] is False
