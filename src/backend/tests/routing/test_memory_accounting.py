from __future__ import annotations

import pytest

from edgemint.routing.memory_accounting import (
    FIXED_RUNTIME_BASE_MEMORY_BYTES,
    MemoryAttributionStatus,
    MemoryCommitmentKind,
    accounted_memory_bytes,
    base_runtime_commitment,
    dedupe_resident_commitments,
    evaluate_memory_admission,
    resident_commitment_for_model,
    task_peak_commitment_for_assignment,
)


def test_resident_models_are_counted_once_when_shared() -> None:
    model = "mdv_qwen2_5_0_5b"
    commitments = [
        base_runtime_commitment(),
        resident_commitment_for_model(model, memory_bytes=800_000_000),
        resident_commitment_for_model(model, memory_bytes=800_000_000),
        task_peak_commitment_for_assignment(
            assignment_id="asg_1",
            task_type="text.summarize",
        ),
    ]
    deduped = dedupe_resident_commitments(commitments)
    resident_count = sum(1 for item in deduped if item.kind == MemoryCommitmentKind.RESIDENT)
    assert resident_count == 1
    assert accounted_memory_bytes(commitments) == (
        FIXED_RUNTIME_BASE_MEMORY_BYTES + 800_000_000 + 1_610_612_736
    )


def test_warm_resident_survives_task_peak_release_in_accounting() -> None:
    model = "mdv_qwen2_5_0_5b"
    resident = resident_commitment_for_model(model, memory_bytes=700_000_000)
    after_task = [
        base_runtime_commitment(),
        resident,
    ]
    with_task = [
        *after_task,
        task_peak_commitment_for_assignment(assignment_id="asg_done", task_type="text.summarize"),
    ]
    assert accounted_memory_bytes(with_task) > accounted_memory_bytes(after_task)
    assert accounted_memory_bytes(after_task) == FIXED_RUNTIME_BASE_MEMORY_BYTES + 700_000_000


def test_uncertain_attribution_blocks_admission() -> None:
    result = evaluate_memory_admission(
        effective_memory_limit_bytes=4_000_000_000,
        commitments=[base_runtime_commitment()],
        requested=task_peak_commitment_for_assignment(
            assignment_id="asg_2",
            task_type="text.summarize",
        ),
        attribution_status=MemoryAttributionStatus.UNCERTAIN,
    )
    assert result.allowed is False
    assert result.reasons == ("CAPACITY_UNCERTAIN",)


def test_memory_budget_exceeded_when_base_plus_task_exceed_limit() -> None:
    result = evaluate_memory_admission(
        effective_memory_limit_bytes=1_000_000_000,
        commitments=[base_runtime_commitment()],
        requested=task_peak_commitment_for_assignment(
            assignment_id="asg_3",
            task_type="text.summarize",
        ),
        attribution_status=MemoryAttributionStatus.KNOWN,
    )
    assert result.allowed is False
    assert result.reasons == ("MEMORY_BUDGET_EXCEEDED",)
