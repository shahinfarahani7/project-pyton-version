from __future__ import annotations

from datetime import UTC, datetime
from unittest.mock import AsyncMock
from uuid import uuid4

import pytest

from edgemint.workers.calibration import (
    CalibrationMetrics,
    WorkerCalibrationService,
    metrics_from_benchmark,
)
from edgemint.workers.schemas import BenchmarkMetric, SubmitBenchmarkRequest


def _benchmark_payload() -> SubmitBenchmarkRequest:
    return SubmitBenchmarkRequest(
        suiteVersion="2026-q3-v1",
        measuredAt=datetime(2026, 9, 1, 10, 0, tzinfo=UTC),
        results=[
            BenchmarkMetric(metric="llm_warmup_ms", value=4200, unit="ms"),
            BenchmarkMetric(metric="tokens_per_second", value=95, unit="tps"),
            BenchmarkMetric(metric="ocr_page_latency_ms", value=850, unit="ms"),
            BenchmarkMetric(metric="runtime_stability_score_milli", value=980, unit="milli"),
        ],
        signature="signed",
    )


def test_metrics_from_benchmark_maps_legacy_and_canonical_metrics() -> None:
    metrics = metrics_from_benchmark(_benchmark_payload())
    assert metrics.llmWarmupMs == 4200
    assert metrics.llmDecodeTokensPerSec == 95
    assert metrics.ocrPageLatencyMs == 850
    assert metrics.runtimeStabilityScoreMilli == 980


@pytest.mark.asyncio
async def test_upsert_from_benchmark_writes_profile() -> None:
    service = WorkerCalibrationService()
    connection = AsyncMock()
    device_id = uuid4()
    payload = _benchmark_payload()

    metrics = await service.upsert_from_benchmark(
        connection,
        worker_device_id=device_id,
        payload=payload,
    )

    assert isinstance(metrics, CalibrationMetrics)
    connection.execute.assert_awaited_once()
    sql = str(connection.execute.await_args.args[0])
    assert "worker_calibration_profiles" in sql


@pytest.mark.asyncio
async def test_get_profile_for_session_returns_view() -> None:
    service = WorkerCalibrationService()
    connection = AsyncMock()
    device_id = uuid4()
    metrics = metrics_from_benchmark(_benchmark_payload())

    class _Result:
        def mappings(self) -> _Result:
            return self

        def first(self) -> dict[str, object]:
            return {
                "suite_version": "2026-q3-v1",
                "measured_at_utc": datetime(2026, 9, 1, 10, 0, tzinfo=UTC),
                "metrics_json": metrics.model_dump(mode="json"),
                "profile_version": 2,
            }

    connection.execute.return_value = _Result()

    view = await service.get_profile_for_session(
        connection,
        worker_device_id=device_id,
        worker_public_id="wrk_test",
        device_public_id="dev_test",
    )

    assert view.workerId == "wrk_test"
    assert view.profileVersion == 2
    assert view.metrics.llmWarmupMs == 4200
