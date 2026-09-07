from __future__ import annotations

from edgemint.routing.envelope_registry import envelope_for_task_type
from edgemint.routing.execution_allocation import (
    derive_execution_allocation,
    input_hints_from_task_input,
)
from edgemint.routing.execution_plan_resolver import resolve_execution_plan


def test_static_envelope_is_independent_of_input_size() -> None:
    envelope = envelope_for_task_type("text.summarize")
    assert envelope is not None
    short = derive_execution_allocation(
        task_type="text.summarize",
        hints=input_hints_from_task_input(
            inline_text="x" * 300,
            input_payload={"estimatedInputTokens": 300},
        ),
    )
    long = derive_execution_allocation(
        task_type="text.summarize",
        hints=input_hints_from_task_input(
            inline_text="x" * 30_000,
            input_payload={"estimatedInputTokens": 30_000},
        ),
    )
    assert short is not None and long is not None
    assert short.resource_envelope_name == envelope.name
    assert long.resource_envelope_name == envelope.name
    assert short.resource_envelope_version == envelope.version
    assert long.resource_envelope_version == envelope.version
    assert envelope.cpu_units == 40
    assert envelope.memory_reservation_bytes == 1_610_612_736


def test_execution_allocation_scales_with_input_and_plan() -> None:
    short = derive_execution_allocation(
        task_type="text.summarize",
        hints=input_hints_from_task_input(
            inline_text="short",
            input_payload={"estimatedInputTokens": 300},
        ),
    )
    long = derive_execution_allocation(
        task_type="text.summarize",
        hints=input_hints_from_task_input(
            inline_text="long",
            input_payload={"estimatedInputTokens": 30_000},
        ),
    )
    assert short is not None and long is not None
    assert short.execution_plan_name == "text-summarize-direct"
    assert long.execution_plan_name == "text-summarize-map-reduce"
    assert long.memory_bytes > short.memory_bytes
    assert long.cpu_units > short.cpu_units
    assert long.estimated_duration_ms > short.estimated_duration_ms
    assert long.predicted_stage_count > short.predicted_stage_count
    assert len(long.stage_peaks) > len(short.stage_peaks)


def test_stage_peaks_increase_with_long_context_plan() -> None:
    long = derive_execution_allocation(
        task_type="text.summarize",
        hints=input_hints_from_task_input(
            inline_text="long",
            input_payload={"estimatedInputTokens": 30_000},
        ),
    )
    assert long is not None
    inference_peaks = [
        stage
        for stage in long.stage_peaks
        if stage.runtime_class == "mediapipe_llm"
    ]
    assert len(inference_peaks) >= 2
    assert sum(stage.memory_bytes for stage in inference_peaks) > 0
    plan = resolve_execution_plan(
        task_type="text.summarize",
        estimated_input_tokens=30_000,
    )
    assert long.execution_plan_name == plan.plan_name


def test_allocation_reservation_vector_uses_scaled_units_not_envelope_static() -> None:
    short = derive_execution_allocation(
        task_type="text.summarize",
        hints=input_hints_from_task_input(
            inline_text="short",
            input_payload={"estimatedInputTokens": 300},
        ),
    )
    envelope = envelope_for_task_type("text.summarize")
    assert short is not None and envelope is not None
    vector = short.reservation_vector()
    assert vector.cpu_units >= envelope.cpu_units
    assert vector.memory_bytes >= envelope.memory_reservation_bytes
    assert vector.exclusive_group == envelope.exclusive_group
