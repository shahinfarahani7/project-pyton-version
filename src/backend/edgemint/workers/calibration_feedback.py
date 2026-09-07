from __future__ import annotations

from dataclasses import dataclass
from datetime import UTC, datetime
from uuid import UUID

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncConnection

from edgemint.workers.calibration import CalibrationMetrics, evaluate_concurrency_certification, load_calibration_metrics
from edgemint.workers.execution_cost_feedback import ExecutionCostFeedbackPayload


@dataclass(frozen=True, slots=True)
class CalibrationUpdateResult:
    previous_metrics: CalibrationMetrics | None
    updated_metrics: CalibrationMetrics
    previous_certified: bool
    updated_certified: bool
    profile_version: int


def adjust_metrics_from_feedback(
    metrics: CalibrationMetrics,
    payload: ExecutionCostFeedbackPayload,
) -> CalibrationMetrics:
    ratio_milli = max(payload.variance.durationRatioMilli, 1)
    adjusted_decode = max(
        10,
        min(500, int(metrics.llmDecodeTokensPerSec * 1000 / ratio_milli)),
    )
    adjusted_ocr_latency = max(
        100,
        min(60_000, int(metrics.ocrPageLatencyMs * ratio_milli / 1000)),
    )
    adjusted_thermal = max(
        metrics.thermalDeltaBps,
        min(10_000, payload.observed.thermalDeltaBps),
    )
    candidate = metrics.model_copy(
        update={
            "llmDecodeTokensPerSec": adjusted_decode,
            "ocrPageLatencyMs": adjusted_ocr_latency,
            "thermalDeltaBps": adjusted_thermal,
        }
    )
    return candidate.model_copy(
        update={"concurrencyCertified": evaluate_concurrency_certification(candidate)}
    )


async def apply_execution_cost_feedback_to_calibration(
    connection: AsyncConnection,
    *,
    worker_device_id: UUID,
    payload: ExecutionCostFeedbackPayload,
    suite_version: str = "adaptive-feedback-v1",
) -> CalibrationUpdateResult:
    previous = await load_calibration_metrics(connection, worker_device_id=worker_device_id)
    baseline = previous or CalibrationMetrics(
        llmWarmupMs=4000,
        llmPrefillTokensPerSec=150,
        llmDecodeTokensPerSec=80,
        llmPeakMemoryBytes=1_610_612_736,
        ocrPageLatencyMs=900,
        ocrPagesPerMinute=60,
        cpuAverageBps=2000,
        thermalDeltaBps=400,
        runtimeStabilityScoreMilli=950,
        concurrencyCertified=False,
    )
    updated = adjust_metrics_from_feedback(baseline, payload)
    row = (
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
                RETURNING profile_version
                """
            ),
            {
                "worker_device_id": worker_device_id,
                "suite_version": suite_version,
                "measured_at_utc": datetime.now(UTC),
                "metrics_json": updated.model_dump_json(),
            },
        )
    ).scalar_one()
    return CalibrationUpdateResult(
        previous_metrics=previous,
        updated_metrics=updated,
        previous_certified=bool(previous.concurrencyCertified if previous else False),
        updated_certified=updated.concurrencyCertified,
        profile_version=int(row),
    )
