from __future__ import annotations

from datetime import UTC, datetime, timedelta
from types import SimpleNamespace
from unittest.mock import AsyncMock, patch
from uuid import uuid4

import pytest

from edgemint.building_blocks.eventing.transactional_outbox import OutboxEvent
from edgemint.security.tokens import hash_session_token
from edgemint.workers.assignments import AssignmentCommandService
from edgemint.workers.errors import WorkerServiceError
from edgemint.workers.failure_codes import (
    CLOSED_WORKER_FAILURE_CODES,
    default_retryable_for_code,
    validate_worker_failure_submission,
)


class _MappingResult:
    def __init__(self, row: dict[str, object] | None) -> None:
        self._row = row

    def mappings(self) -> _MappingResult:
        return self

    def first(self) -> dict[str, object] | None:
        return self._row


def _running_row(*, fence: int = 7) -> dict[str, object]:
    return {
        "status": "running",
        "workspace_id": uuid4(),
        "task_attempt_id": uuid4(),
        "task_id": uuid4(),
        "task_public_id": "task_01TEST",
        "task_run_id": uuid4(),
        "fence_token": fence,
        "lease_token_hash": hash_session_token("lease-token"),
        "lease_expires_at_utc": datetime.now(UTC) + timedelta(minutes=2),
        "failure_reason_code": None,
    }


def test_closed_failure_code_matrix_covers_architecture_sections() -> None:
    assert "THERMAL_BLOCK" in CLOSED_WORKER_FAILURE_CODES
    assert "RUNTIME_OUT_OF_MEMORY" in CLOSED_WORKER_FAILURE_CODES
    assert "RUNTIME_CRASH" in CLOSED_WORKER_FAILURE_CODES
    assert "TASK_CANCELLED" in CLOSED_WORKER_FAILURE_CODES
    assert default_retryable_for_code("THERMAL_BLOCK") is True
    assert default_retryable_for_code("TASK_CANCELLED") is False


def test_validate_worker_failure_submission_rejects_open_codes() -> None:
    with pytest.raises(WorkerServiceError) as exc:
        validate_worker_failure_submission(error_code="INTERNAL_ERROR", retryable=True)
    assert exc.value.code == "INPUT_SCHEMA_INVALID"


def test_validate_worker_failure_submission_rejects_retryable_mismatch() -> None:
    with pytest.raises(WorkerServiceError) as exc:
        validate_worker_failure_submission(error_code="TASK_CANCELLED", retryable=True)
    assert exc.value.code == "INPUT_SCHEMA_INVALID"


@pytest.mark.asyncio
async def test_fail_emits_task_failed_cloud_event_with_closed_code() -> None:
    row = _running_row(fence=9)
    connection = AsyncMock()
    connection.execute.return_value = _MappingResult(row)
    session = SimpleNamespace(device_id=uuid4())
    captured: list[OutboxEvent] = []

    async def _capture(_connection: object, event: OutboxEvent) -> None:
        captured.append(event)

    with patch(
        "edgemint.workers.assignments.resolve_worker_session",
        AsyncMock(return_value=session),
    ), patch(
        "edgemint.workers.assignments.enqueue_outbox_event",
        side_effect=_capture,
    ):
        service = AssignmentCommandService()
        service.settings.worker_resource_reservations_enabled = False
        receipt = await service.fail(
            connection,
            access_token="token",
            assignment_id=str(uuid4()),
            lease_token="lease-token",
            fence_token=9,
            error_code="RUNTIME_OUT_OF_MEMORY",
            retryable=True,
            diagnostics={"metrics": {"executionTimeMs": 64000}},
        )

    assert receipt["operation"] == "failAssignment"
    assert receipt["errorCode"] == "RUNTIME_OUT_OF_MEMORY"
    assert len(captured) == 1
    event = captured[0]
    assert event.event_type == "task.failed"
    assert event.aggregate_sequence == 9 * 1_000_000_000 + 800_000_000
    assert event.cloud_event["type"] == "io.edgemint.task.failed.v1"
    assert event.cloud_event["data"]["failureCode"] == "RUNTIME_OUT_OF_MEMORY"
    assert event.cloud_event["data"]["reasonCode"] == "RUNTIME_OUT_OF_MEMORY"


@pytest.mark.asyncio
async def test_fail_accepts_leased_assignment_for_pre_execution_rejection() -> None:
    row = _running_row(fence=6)
    row["status"] = "leased"
    connection = AsyncMock()
    connection.execute.return_value = _MappingResult(row)
    session = SimpleNamespace(device_id=uuid4())

    with patch(
        "edgemint.workers.assignments.resolve_worker_session",
        AsyncMock(return_value=session),
    ), patch(
        "edgemint.workers.assignments.enqueue_outbox_event",
        AsyncMock(),
    ):
        service = AssignmentCommandService()
        service.settings.worker_resource_reservations_enabled = False
        receipt = await service.fail(
            connection,
            access_token="token",
            assignment_id=str(uuid4()),
            lease_token="lease-token",
            fence_token=6,
            error_code="CONSENT_MISMATCH",
            retryable=False,
        )

    assert receipt["operation"] == "failAssignment"
    assert receipt["errorCode"] == "CONSENT_MISMATCH"


@pytest.mark.asyncio
async def test_fail_rejects_stale_fence_before_outbox_write() -> None:
    row = _running_row(fence=8)
    connection = AsyncMock()
    connection.execute.return_value = _MappingResult(row)
    session = SimpleNamespace(device_id=uuid4())

    with patch(
        "edgemint.workers.assignments.resolve_worker_session",
        AsyncMock(return_value=session),
    ), patch(
        "edgemint.workers.assignments.enqueue_outbox_event",
        AsyncMock(),
    ) as enqueue:
        with pytest.raises(WorkerServiceError) as exc:
            await AssignmentCommandService().fail(
                connection,
                access_token="token",
                assignment_id=str(uuid4()),
                lease_token="lease-token",
                fence_token=7,
                error_code="THERMAL_BLOCK",
                retryable=True,
            )
        assert exc.value.code == "ASSIGNMENT_STALE_FENCE"
        enqueue.assert_not_called()
