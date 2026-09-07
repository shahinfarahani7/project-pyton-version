from __future__ import annotations

from dataclasses import dataclass, field
from datetime import UTC, datetime
from typing import Any
from uuid import UUID

from pydantic import BaseModel, Field
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncConnection

from edgemint.workers.errors import worker_error
from edgemint.workers.schemas import SubmitBenchmarkRequest


class CalibrationMetrics(BaseModel):
    llmWarmupMs: int = Field(ge=0)
    llmPrefillTokensPerSec: int = Field(ge=0)
    llmDecodeTokensPerSec: int = Field(ge=0)
    llmPeakMemoryBytes: int = Field(ge=0)
    ocrPageLatencyMs: int = Field(ge=0)
    ocrPagesPerMinute: int = Field(ge=0)
    cpuAverageBps: int = Field(ge=0, le=10_000)
    thermalDeltaBps: int = Field(ge=0, le=10_000)
    runtimeStabilityScoreMilli: int = Field(ge=0, le=1000)
    concurrencyCertified: bool = False

    model_config = {"extra": "forbid"}


CERTIFICATION_STABILITY_THRESHOLD_MILLI = 900
CERTIFICATION_THERMAL_DELTA_MAX_BPS = 600
CERTIFICATION_MIN_DECODE_TPS = 50


def evaluate_concurrency_certification(metrics: CalibrationMetrics) -> bool:
    return (
        metrics.runtimeStabilityScoreMilli >= CERTIFICATION_STABILITY_THRESHOLD_MILLI
        and metrics.thermalDeltaBps <= CERTIFICATION_THERMAL_DELTA_MAX_BPS
        and metrics.llmDecodeTokensPerSec >= CERTIFICATION_MIN_DECODE_TPS
    )


class WorkerCalibrationProfileView(BaseModel):
    workerId: str
    deviceId: str
    suiteVersion: str
    measuredAt: datetime
    profileVersion: int = Field(ge=1)
    metrics: CalibrationMetrics


_METRIC_ALIASES: dict[str, str] = {
    "llm_warmup_ms": "llmWarmupMs",
    "llm_prefill_tokens_per_sec": "llmPrefillTokensPerSec",
    "llm_decode_tokens_per_sec": "llmDecodeTokensPerSec",
    "tokens_per_second": "llmDecodeTokensPerSec",
    "inference_ops_per_second": "llmDecodeTokensPerSec",
    "llm_peak_memory_bytes": "llmPeakMemoryBytes",
    "ocr_page_latency_ms": "ocrPageLatencyMs",
    "ocr_pages_per_minute": "ocrPagesPerMinute",
    "cpu_average_bps": "cpuAverageBps",
    "thermal_delta_bps": "thermalDeltaBps",
    "runtime_stability_score_milli": "runtimeStabilityScoreMilli",
}


def metrics_from_benchmark(payload: SubmitBenchmarkRequest) -> CalibrationMetrics:
    values: dict[str, int] = {field_name: 0 for field_name in CalibrationMetrics.model_fields}
    for item in payload.results:
        normalized = item.metric.strip().lower().replace("-", "_")
        target = _METRIC_ALIASES.get(normalized)
        if target is None:
            continue
        values[target] = max(values[target], int(item.value))
    return CalibrationMetrics.model_validate(values)


@dataclass(slots=True)
class WorkerCalibrationService:
    async def upsert_from_benchmark(
        self,
        connection: AsyncConnection,
        *,
        worker_device_id: UUID,
        payload: SubmitBenchmarkRequest,
    ) -> CalibrationMetrics:
        metrics = metrics_from_benchmark(payload)
        metrics = metrics.model_copy(
            update={"concurrencyCertified": evaluate_concurrency_certification(metrics)}
        )
        await connection.execute(
            text(
                """
                INSERT INTO public.worker_calibration_profiles(
                    worker_device_id, suite_version, measured_at_utc, metrics_json
                )
                VALUES (
                    :worker_device_id, :suite_version, :measured_at_utc,
                    CAST(:metrics_json AS jsonb)
                )
                ON CONFLICT (worker_device_id) DO UPDATE
                SET suite_version = EXCLUDED.suite_version,
                    measured_at_utc = EXCLUDED.measured_at_utc,
                    metrics_json = EXCLUDED.metrics_json,
                    profile_version = public.worker_calibration_profiles.profile_version + 1,
                    updated_at_utc = CURRENT_TIMESTAMP
                WHERE EXCLUDED.measured_at_utc >= public.worker_calibration_profiles.measured_at_utc
                """
            ),
            {
                "worker_device_id": worker_device_id,
                "suite_version": payload.suiteVersion,
                "measured_at_utc": payload.measuredAt,
                "metrics_json": metrics.model_dump_json(),
            },
        )
        return metrics

    async def get_profile_for_session(
        self,
        connection: AsyncConnection,
        *,
        worker_device_id: UUID,
        worker_public_id: str,
        device_public_id: str,
    ) -> WorkerCalibrationProfileView:
        row = (
            await connection.execute(
                text(
                    """
                    SELECT suite_version, measured_at_utc, metrics_json, profile_version
                    FROM public.worker_calibration_profiles
                    WHERE worker_device_id = :worker_device_id
                    """
                ),
                {"worker_device_id": worker_device_id},
            )
        ).mappings().first()
        if row is None:
            raise worker_error("TENANT_RESOURCE_NOT_FOUND", detail="calibration profile missing")
        metrics = CalibrationMetrics.model_validate(dict(row["metrics_json"]))
        measured_at = row["measured_at_utc"]
        if measured_at.tzinfo is None:
            measured_at = measured_at.replace(tzinfo=UTC)
        return WorkerCalibrationProfileView(
            workerId=worker_public_id,
            deviceId=device_public_id,
            suiteVersion=str(row["suite_version"]),
            measuredAt=measured_at,
            profileVersion=int(row["profile_version"]),
            metrics=metrics,
        )


async def load_calibration_metrics(
    connection: AsyncConnection,
    *,
    worker_device_id: UUID,
) -> CalibrationMetrics | None:
    """Routing-facing read helper for scheduler cost prediction (Phase 6)."""
    row = (
        await connection.execute(
            text(
                """
                SELECT metrics_json
                FROM public.worker_calibration_profiles
                WHERE worker_device_id = :worker_device_id
                """
            ),
            {"worker_device_id": worker_device_id},
        )
    ).mappings().first()
    if row is None:
        return None
    return CalibrationMetrics.model_validate(dict(row["metrics_json"]))
