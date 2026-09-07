from __future__ import annotations

from uuid import UUID

from sqlalchemy.ext.asyncio import AsyncConnection

from edgemint.workers.calibration import CalibrationMetrics, load_calibration_metrics
from edgemint.routing.calibration_prediction import (
    CalibrationProfileIdentity,
    PredictionPhase,
    VersionedPredictionRecord,
    build_versioned_prediction,
    calibration_factor_from_metrics,
    calibration_factor_to_bps,
    resolve_calibration_factor_bps,
    resolve_prediction_phase,
)


async def calibration_factor_for_device(
    connection: AsyncConnection,
    *,
    worker_device_id: UUID,
) -> float:
    """Return a bounded multiplier derived from calibration metrics for routing."""
    metrics = await load_calibration_metrics(connection, worker_device_id=worker_device_id)
    if metrics is None:
        return 1.0
    return calibration_factor_from_metrics(metrics)


async def calibration_factor_bps_for_device(
    connection: AsyncConnection,
    *,
    worker_device_id: UUID,
) -> int:
    return calibration_factor_to_bps(
        await calibration_factor_for_device(connection, worker_device_id=worker_device_id)
    )


async def build_versioned_prediction_for_device(
    connection: AsyncConnection,
    *,
    worker_device_id: UUID,
    base_duration_ms: int,
    base_peak_memory_bytes: int,
    model_resident: bool = False,
    warmup_completed: bool = False,
    active_artifact_id: str | None = None,
    active_runtime_version: str | None = None,
) -> VersionedPredictionRecord:
    from sqlalchemy import text

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

    metrics: CalibrationMetrics | None = None
    identity: CalibrationProfileIdentity | None = None
    measured_at = None
    if row is not None:
        metrics = CalibrationMetrics.model_validate(dict(row["metrics_json"]))
        measured_at = row["measured_at_utc"]
        identity = CalibrationProfileIdentity(
            suite_version=str(row["suite_version"]),
            profile_version=int(row["profile_version"]),
            measured_at_utc=measured_at,
            artifact_id=active_artifact_id,
            runtime_version=active_runtime_version,
        )

    phase = resolve_prediction_phase(
        model_resident=model_resident,
        warmup_completed=warmup_completed,
    )
    return build_versioned_prediction(
        base_duration_ms=base_duration_ms,
        base_peak_memory_bytes=base_peak_memory_bytes,
        metrics=metrics,
        identity=identity,
        measured_at=measured_at,
        phase=phase,
        active_artifact_id=active_artifact_id,
        active_runtime_version=active_runtime_version,
    )


async def resolve_calibration_factor_bps_for_device(
    connection: AsyncConnection,
    *,
    worker_device_id: UUID,
    active_artifact_id: str | None = None,
    active_runtime_version: str | None = None,
) -> int:
    from datetime import UTC, datetime
    from sqlalchemy import text

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
        factor_bps, _, _ = resolve_calibration_factor_bps(
            metrics=None,
            identity=None,
            measured_at=None,
            now=datetime.now(UTC),
            active_artifact_id=active_artifact_id,
            active_runtime_version=active_runtime_version,
        )
        return factor_bps

    metrics = CalibrationMetrics.model_validate(dict(row["metrics_json"]))
    identity = CalibrationProfileIdentity(
        suite_version=str(row["suite_version"]),
        profile_version=int(row["profile_version"]),
        measured_at_utc=row["measured_at_utc"],
        artifact_id=active_artifact_id,
        runtime_version=active_runtime_version,
    )
    factor_bps, _, _ = resolve_calibration_factor_bps(
        metrics=metrics,
        identity=identity,
        measured_at=row["measured_at_utc"],
        now=datetime.now(UTC),
        active_artifact_id=active_artifact_id,
        active_runtime_version=active_runtime_version,
    )
    return factor_bps
