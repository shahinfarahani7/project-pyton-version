from __future__ import annotations

from dataclasses import dataclass, field
from datetime import UTC, datetime
from typing import Any
from uuid import UUID

from pydantic import BaseModel, Field
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncConnection

from edgemint.workers.errors import worker_error


class PredictedResourceUsage(BaseModel):
    cpuUnits: int = Field(ge=1)
    peakMemoryBytes: int = Field(ge=1)
    durationMs: int = Field(ge=1)
    energyClass: str = Field(pattern=r"^(low|medium|high)$")
    runtimeClass: str | None = None
    calibrationFactorBps: int | None = Field(default=None, ge=5000, le=20_000)

    model_config = {"extra": "forbid"}


class ObservedResourceUsage(BaseModel):
    cpuAverageBps: int = Field(ge=0, le=10_000)
    peakMemoryBytes: int = Field(ge=0)
    durationMs: int = Field(ge=0)
    thermalDeltaBps: int = Field(ge=0, le=10_000)
    throughputPerSec: float | None = Field(default=None, ge=0)
    throughputUnit: str | None = Field(default=None, pattern=r"^(tokens|pages|inferences)$")

    model_config = {"extra": "forbid"}


class ExecutionCostVariance(BaseModel):
    durationMs: int
    peakMemoryBytes: int
    durationRatioMilli: int = Field(ge=0)

    model_config = {"extra": "forbid"}


class ExecutionCostFeedbackPayload(BaseModel):
    predicted: PredictedResourceUsage
    observed: ObservedResourceUsage
    variance: ExecutionCostVariance

    model_config = {"extra": "forbid"}


def compute_execution_cost_variance(
    *,
    predicted: PredictedResourceUsage,
    observed: ObservedResourceUsage,
) -> ExecutionCostVariance:
    duration_ratio_milli = (
        (observed.durationMs * 1000) // predicted.durationMs if predicted.durationMs > 0 else 0
    )
    return ExecutionCostVariance(
        durationMs=observed.durationMs - predicted.durationMs,
        peakMemoryBytes=observed.peakMemoryBytes - predicted.peakMemoryBytes,
        durationRatioMilli=duration_ratio_milli,
    )


def parse_execution_cost_feedback(raw: Any) -> ExecutionCostFeedbackPayload:
    if not isinstance(raw, dict):
        raise worker_error("INPUT_SCHEMA_INVALID", detail="costFeedback must be an object")
    payload = ExecutionCostFeedbackPayload.model_validate(raw)
    expected = compute_execution_cost_variance(
        predicted=payload.predicted,
        observed=payload.observed,
    )
    if payload.variance != expected:
        raise worker_error("INPUT_SCHEMA_INVALID", detail="costFeedback variance mismatch")
    return payload


@dataclass(slots=True)
class ExecutionCostFeedbackService:
    async def persist_for_assignment(
        self,
        connection: AsyncConnection,
        *,
        workspace_id: UUID,
        assignment_id: UUID,
        task_attempt_id: UUID,
        worker_device_id: UUID,
        fence_token: int,
        task_type: str,
        payload: ExecutionCostFeedbackPayload,
        observed_at: datetime | None = None,
    ) -> None:
        observed_at_utc = observed_at or datetime.now(UTC)
        await connection.execute(
            text(
                """
                INSERT INTO public.worker_execution_cost_feedback(
                    workspace_id, assignment_id, task_attempt_id, worker_device_id,
                    fence_token, task_type, observed_at_utc,
                    predicted_json, observed_json, variance_json
                )
                VALUES (
                    :workspace_id, :assignment_id, :task_attempt_id, :worker_device_id,
                    :fence_token, :task_type, :observed_at_utc,
                    CAST(:predicted_json AS jsonb),
                    CAST(:observed_json AS jsonb),
                    CAST(:variance_json AS jsonb)
                )
                ON CONFLICT (assignment_id, fence_token) DO NOTHING
                """
            ),
            {
                "workspace_id": workspace_id,
                "assignment_id": assignment_id,
                "task_attempt_id": task_attempt_id,
                "worker_device_id": worker_device_id,
                "fence_token": fence_token,
                "task_type": task_type,
                "observed_at_utc": observed_at_utc,
                "predicted_json": payload.predicted.model_dump_json(),
                "observed_json": payload.observed.model_dump_json(),
                "variance_json": payload.variance.model_dump_json(),
            },
        )
