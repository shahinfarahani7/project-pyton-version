"""T13 audit scenarios: runtime-pair conflicts and bounded light work (P8-A13 / A13)."""

from __future__ import annotations

from edgemint.routing.exclusive_groups import can_reserve_exclusive_group
from edgemint.routing.runtime_compatibility import is_runtime_compatible


def test_t13_qwen_and_vlm_runtime_pair_blocked() -> None:
    assert not is_runtime_compatible(
        worker_runtime_classes=["mediapipe_llm", "vlm_runtime"],
        task_runtime_class="vlm_runtime",
        device_tier="T4",
        active_runtime_classes=["mediapipe_llm"],
        concurrency_certified=True,
    )


def test_t13_certified_qwen_ocr_pair_allowed() -> None:
    assert is_runtime_compatible(
        worker_runtime_classes=["mediapipe_llm", "paddle_ocr"],
        task_runtime_class="paddle_ocr",
        device_tier="T3",
        active_runtime_classes=["mediapipe_llm"],
        concurrency_certified=True,
    )
    assert can_reserve_exclusive_group(
        requested_group="ocr_inference",
        active_counts={"llm_inference": 1},
        device_certified=True,
    )


def test_t13_uncertified_qwen_ocr_pair_blocked() -> None:
    assert not is_runtime_compatible(
        worker_runtime_classes=["mediapipe_llm", "paddle_ocr"],
        task_runtime_class="paddle_ocr",
        active_runtime_classes=["mediapipe_llm"],
        concurrency_certified=False,
    )
    assert can_reserve_exclusive_group(
        requested_group="ocr_inference",
        active_counts={"llm_inference": 1},
        device_certified=False,
    ) is False


def test_t13_light_network_io_allowed_during_heavy_llm() -> None:
    assert can_reserve_exclusive_group(
        requested_group="network_io",
        active_counts={"llm_inference": 1},
    )


def test_t13_light_system_work_allowed_during_heavy_llm() -> None:
    assert can_reserve_exclusive_group(
        requested_group="system",
        active_counts={"llm_inference": 1},
    )
