from __future__ import annotations

import json
from dataclasses import dataclass
from typing import Any
from uuid import UUID

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncConnection

from edgemint.routing.cost_estimator import EnvelopeTaskCostEstimator, TaskCostEstimatorInputs
from edgemint.routing.envelope_registry import ResourceEnvelopeSpec, envelope_for_task_type
from edgemint.routing.context_budget import cap_max_output_tokens
from edgemint.routing.context_profile_registry import default_qwen_context_profile
from edgemint.routing.execution_plan_resolver import ExecutionPlan, resolve_execution_plan
from edgemint.routing.resource_reservations import ResourceReservationVector

ESTIMATOR_VERSION = "envelope-v1"
POLICY_VERSION = "production-resource-policy-v1"
COMPATIBILITY_PROFILE_REF = "RuntimeCompatibilityProfile/production-v1@1.0.0"

_INFERENCE_RUNTIME_CLASSES = frozenset(
    {"mediapipe_llm", "paddle_ocr", "image_classifier", "segmentation_runtime"}
)


@dataclass(frozen=True, slots=True)
class InputHints:
    input_bytes: int
    estimated_input_tokens: int
    page_count: int
    image_width: int
    image_height: int
    chunk_count_estimate: int
    runtime_class: str
    model_version_id: str


@dataclass(frozen=True, slots=True)
class StagePeak:
    sequence: int
    name: str
    operation: str
    runtime_class: str
    cpu_units: int
    memory_bytes: int
    estimated_duration_ms: int
    exclusive_group: str | None

    def as_dict(self) -> dict[str, Any]:
        return {
            "sequence": self.sequence,
            "name": self.name,
            "operation": self.operation,
            "runtimeClass": self.runtime_class,
            "cpuUnits": self.cpu_units,
            "memoryBytes": self.memory_bytes,
            "estimatedDurationMs": self.estimated_duration_ms,
            "exclusiveGroup": self.exclusive_group,
        }


@dataclass(frozen=True, slots=True)
class ExecutionAllocationSpec:
    resource_envelope_name: str
    resource_envelope_version: str
    execution_plan_name: str
    execution_plan_version: str
    policy_version: str
    estimator_version: str
    cpu_units: int
    memory_bytes: int
    storage_bytes: int
    accelerator_units: int
    model_session_units: int
    exclusive_group: str
    estimated_duration_ms: int
    predicted_stage_count: int
    stage_peaks: tuple[StagePeak, ...]
    compatibility_profile_ref: str
    max_output_tokens: int
    max_inference_calls: int
    deadline_ms: int

    def reservation_vector(self) -> ResourceReservationVector:
        return ResourceReservationVector(
            cpu_units=self.cpu_units,
            memory_bytes=self.memory_bytes,
            storage_bytes=self.storage_bytes,
            accelerator_units=self.accelerator_units,
            model_session_units=self.model_session_units,
            exclusive_group=self.exclusive_group,
        )

    def stage_peaks_json(self) -> str:
        return json.dumps([stage.as_dict() for stage in self.stage_peaks], separators=(",", ":"))


def input_hints_from_task_input(
    *,
    inline_text: str | None,
    input_payload: dict[str, Any],
) -> InputHints:
    image = input_payload.get("image") if isinstance(input_payload.get("image"), dict) else {}
    inline = inline_text or str(input_payload.get("inlineText") or input_payload.get("text") or "")
    token_estimate = int(
        input_payload.get("estimatedInputTokens")
        or input_payload.get("tokenEstimate")
        or max(len(inline), 1)
    )
    return InputHints(
        input_bytes=int(input_payload.get("inputBytes") or input_payload.get("bytes") or len(inline.encode("utf-8"))),
        estimated_input_tokens=token_estimate,
        page_count=int(input_payload.get("pageCount") or input_payload.get("pages") or 1),
        image_width=int(image.get("width") or 0),
        image_height=int(image.get("height") or 0),
        chunk_count_estimate=int(input_payload.get("chunkCountEstimate") or 1),
        runtime_class=str(input_payload.get("runtimeClass") or ""),
        model_version_id=str(input_payload.get("modelVersionId") or ""),
    )


def _load_factor(envelope: ResourceEnvelopeSpec, hints: InputHints) -> int:
    page_factor = max(1, hints.page_count or 1)
    token_factor = max(1, (max(hints.estimated_input_tokens, 1) + 999) // 1000)
    byte_factor = max(1, (max(hints.input_bytes, 1) + (512 * 1024) - 1) // (512 * 1024))

    if envelope.runtime_class == "mediapipe_llm":
        return max(token_factor, byte_factor)
    if envelope.runtime_class == "paddle_ocr":
        return page_factor
    if envelope.runtime_class in {"image_classifier", "segmentation_runtime"}:
        pixel_factor = max(
            1,
            ((hints.image_width or 1024) * (hints.image_height or 1024)) // (1024 * 1024),
        )
        return max(1, pixel_factor)
    return max(page_factor, token_factor, byte_factor)


def _scaled_totals(envelope: ResourceEnvelopeSpec, load_factor: int) -> tuple[int, int, int]:
    duration = envelope.estimated_duration_ms * load_factor
    memory = envelope.memory_reservation_bytes + (load_factor - 1) * (envelope.memory_reservation_bytes // 4)
    cpu = envelope.cpu_units + (load_factor - 1) * max(1, envelope.cpu_units // 5)
    return duration, memory, cpu


def _stage_peaks(
    *,
    envelope: ResourceEnvelopeSpec,
    plan: ExecutionPlan,
    load_factor: int,
    total_cpu: int,
    total_memory: int,
) -> tuple[StagePeak, ...]:
    inference_stages = [stage for stage in plan.stages if stage.runtime_class in _INFERENCE_RUNTIME_CLASSES]
    inference_duration = sum(stage.estimated_duration_ms for stage in inference_stages) or 1
    peaks: list[StagePeak] = []
    for stage in plan.stages:
        if stage.runtime_class in _INFERENCE_RUNTIME_CLASSES:
            share_numerator = stage.estimated_duration_ms
            share_denominator = inference_duration
            stage_cpu = max(1, (total_cpu * share_numerator) // share_denominator)
            stage_memory = max(0, (total_memory * share_numerator) // share_denominator)
            duration_ms = stage.estimated_duration_ms * max(1, load_factor if envelope.runtime_class == "mediapipe_llm" else 1)
        else:
            stage_cpu = 1
            stage_memory = 0
            duration_ms = stage.estimated_duration_ms
        peaks.append(
            StagePeak(
                sequence=stage.sequence,
                name=stage.name,
                operation=stage.operation,
                runtime_class=stage.runtime_class,
                cpu_units=stage_cpu,
                memory_bytes=stage_memory,
                estimated_duration_ms=duration_ms,
                exclusive_group=stage.exclusive_group,
            )
        )
    return tuple(peaks)


def derive_execution_allocation(
    *,
    task_type: str,
    hints: InputHints,
    calibration_factor_bps: int = 10_000,
) -> ExecutionAllocationSpec | None:
    envelope = envelope_for_task_type(task_type)
    if envelope is None:
        return None

    plan = resolve_execution_plan(
        task_type=task_type,
        estimated_input_tokens=hints.estimated_input_tokens,
        page_count=hints.page_count,
    )
    load_factor = _load_factor(envelope, hints)
    duration, memory, cpu = _scaled_totals(envelope, load_factor)

    cost_inputs = TaskCostEstimatorInputs(
        taskType=task_type,
        inputBytes=hints.input_bytes,
        estimatedInputTokens=hints.estimated_input_tokens,
        pageCount=hints.page_count,
        imageWidth=hints.image_width,
        imageHeight=hints.image_height,
        chunkCountEstimate=max(hints.chunk_count_estimate, len(plan.stages)),
        runtimeClass=hints.runtime_class or envelope.runtime_class,
        modelVersionId=hints.model_version_id,
        executionPlanId=plan.plan_name,
        calibrationFactorBps=calibration_factor_bps,
    )
    estimate = EnvelopeTaskCostEstimator().estimate(cost_inputs)
    stage_peaks = _stage_peaks(
        envelope=envelope,
        plan=plan,
        load_factor=load_factor,
        total_cpu=estimate.predictedCpuUnits,
        total_memory=estimate.predictedPeakMemoryBytes,
    )
    max_inference_calls = max(
        1,
        sum(1 for stage in plan.stages if stage.runtime_class in _INFERENCE_RUNTIME_CLASSES),
    )
    return ExecutionAllocationSpec(
        resource_envelope_name=envelope.name,
        resource_envelope_version=envelope.version,
        execution_plan_name=plan.plan_name,
        execution_plan_version=plan.plan_version,
        policy_version=POLICY_VERSION,
        estimator_version=ESTIMATOR_VERSION,
        cpu_units=estimate.predictedCpuUnits,
        memory_bytes=estimate.predictedPeakMemoryBytes,
        storage_bytes=envelope.storage_reservation_bytes,
        accelerator_units=envelope.accelerator_units,
        model_session_units=envelope.model_session_units,
        exclusive_group=envelope.exclusive_group,
        estimated_duration_ms=estimate.predictedDurationMs,
        predicted_stage_count=len(plan.stages),
        stage_peaks=stage_peaks,
        compatibility_profile_ref=COMPATIBILITY_PROFILE_REF,
        max_output_tokens=cap_max_output_tokens(
            max(512, min(32_768, hints.estimated_input_tokens // 4 or 512)),
            profile=default_qwen_context_profile(),
        ),
        max_inference_calls=max_inference_calls,
        deadline_ms=max(estimate.predictedDurationMs * 2, 60_000),
    )


class ExecutionAllocationService:
    async def create_for_task_run(
        self,
        connection: AsyncConnection,
        *,
        workspace_id: UUID,
        task_run_id: UUID,
        task_revision_id: UUID,
        input_digest: str,
        task_type: str,
        hints: InputHints,
    ) -> UUID | None:
        spec = derive_execution_allocation(task_type=task_type, hints=hints)
        if spec is None:
            return None
        allocation_id = (
            await connection.execute(
                text(
                    """
                    INSERT INTO public.task_execution_allocations(
                        workspace_id, task_run_id, task_revision_id, input_digest,
                        resource_envelope_name, resource_envelope_version,
                        execution_plan_name, execution_plan_version,
                        policy_version, estimator_version,
                        cpu_units, memory_bytes, storage_bytes, accelerator_units,
                        model_session_units, exclusive_group, estimated_duration_ms,
                        predicted_stage_count, stage_peaks_json, compatibility_profile_ref,
                        max_output_tokens, max_inference_calls, deadline_ms
                    )
                    VALUES (
                        :workspace_id, :task_run_id, :task_revision_id, :input_digest,
                        :resource_envelope_name, :resource_envelope_version,
                        :execution_plan_name, :execution_plan_version,
                        :policy_version, :estimator_version,
                        :cpu_units, :memory_bytes, :storage_bytes, :accelerator_units,
                        :model_session_units, :exclusive_group, :estimated_duration_ms,
                        :predicted_stage_count, CAST(:stage_peaks_json AS jsonb),
                        :compatibility_profile_ref,
                        :max_output_tokens, :max_inference_calls, :deadline_ms
                    )
                    RETURNING id
                    """
                ),
                {
                    "workspace_id": workspace_id,
                    "task_run_id": task_run_id,
                    "task_revision_id": task_revision_id,
                    "input_digest": input_digest,
                    "resource_envelope_name": spec.resource_envelope_name,
                    "resource_envelope_version": spec.resource_envelope_version,
                    "execution_plan_name": spec.execution_plan_name,
                    "execution_plan_version": spec.execution_plan_version,
                    "policy_version": spec.policy_version,
                    "estimator_version": spec.estimator_version,
                    "cpu_units": spec.cpu_units,
                    "memory_bytes": spec.memory_bytes,
                    "storage_bytes": spec.storage_bytes,
                    "accelerator_units": spec.accelerator_units,
                    "model_session_units": spec.model_session_units,
                    "exclusive_group": spec.exclusive_group,
                    "estimated_duration_ms": spec.estimated_duration_ms,
                    "predicted_stage_count": spec.predicted_stage_count,
                    "stage_peaks_json": spec.stage_peaks_json(),
                    "compatibility_profile_ref": spec.compatibility_profile_ref,
                    "max_output_tokens": spec.max_output_tokens,
                    "max_inference_calls": spec.max_inference_calls,
                    "deadline_ms": spec.deadline_ms,
                },
            )
        ).scalar_one()
        return UUID(str(allocation_id))

    async def load_vector_for_attempt(
        self,
        connection: AsyncConnection,
        *,
        task_attempt_id: UUID,
    ) -> ResourceReservationVector | None:
        row = (
            await connection.execute(
                text(
                    """
                    SELECT allocation.cpu_units,
                           allocation.memory_bytes,
                           allocation.storage_bytes,
                           allocation.accelerator_units,
                           allocation.model_session_units,
                           allocation.exclusive_group,
                           allocation.id
                    FROM public.task_attempts AS attempt
                    JOIN public.task_execution_allocations AS allocation
                      ON allocation.task_run_id = attempt.task_run_id
                    WHERE attempt.id = :task_attempt_id
                    """
                ),
                {"task_attempt_id": task_attempt_id},
            )
        ).mappings().first()
        if row is None:
            return None
        return ResourceReservationVector(
            cpu_units=int(row["cpu_units"]),
            memory_bytes=int(row["memory_bytes"]),
            storage_bytes=int(row["storage_bytes"]),
            accelerator_units=int(row["accelerator_units"]),
            model_session_units=int(row["model_session_units"]),
            exclusive_group=str(row["exclusive_group"] or ""),
        )

    async def load_allocation_id_for_attempt(
        self,
        connection: AsyncConnection,
        *,
        task_attempt_id: UUID,
    ) -> UUID | None:
        value = (
            await connection.execute(
                text(
                    """
                    SELECT allocation.id
                    FROM public.task_attempts AS attempt
                    JOIN public.task_execution_allocations AS allocation
                      ON allocation.task_run_id = attempt.task_run_id
                    WHERE attempt.id = :task_attempt_id
                    """
                ),
                {"task_attempt_id": task_attempt_id},
            )
        ).scalar_one_or_none()
        return UUID(str(value)) if value is not None else None
