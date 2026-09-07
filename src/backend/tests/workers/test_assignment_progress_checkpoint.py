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
from edgemint.workers.transport_recovery import TransportRecordResult, SubmissionClassification


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
        "fence_token": fence,
        "lease_token_hash": hash_session_token("lease-token"),
        "lease_expires_at_utc": datetime.now(UTC) + timedelta(minutes=2),
    }


@pytest.mark.asyncio
async def test_progress_emits_task_progress_cloud_event_with_fence() -> None:
    row = _running_row(fence=11)
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
    ), patch(
        "edgemint.workers.transport_recovery.TransportRecoveryService.record",
        AsyncMock(
            return_value=TransportRecordResult(
                classification=SubmissionClassification.TRANSPORT_FRESH,
                aggregate_sequence=11 * 1_000_000_000 + 2_000_000 + 3,
                is_new=True,
            )
        ),
    ):
        receipt = await AssignmentCommandService().progress(
            connection,
            access_token="token",
            assignment_id=str(uuid4()),
            lease_token="lease-token",
            fence_token=11,
            sequence=3,
            stage="llm-map",
            progress_bps=4000,
            metrics={"stageIndex": 1},
        )

    assert receipt["operation"] == "progressAssignment"
    assert receipt["sequence"] == 3
    assert len(captured) == 1
    event = captured[0]
    assert event.event_type == "task_progress"
    assert event.aggregate_sequence == 11 * 1_000_000_000 + 2_000_000 + 3
    assert event.cloud_event["type"] == "io.edgemint.task.progress.v1"
    assert event.cloud_event["data"]["fenceToken"] == 11
    assert event.cloud_event["data"]["stage"] == "llm-map"
    assert event.cloud_event["data"]["progressBps"] == 4000


@pytest.mark.asyncio
async def test_checkpoint_emits_task_checkpoint_saved_cloud_event_with_fence() -> None:
    row = _running_row(fence=5)
    row["task_type"] = "text.summarize"
    connection = AsyncMock()
    connection.execute.return_value = _MappingResult(row)
    session = SimpleNamespace(device_id=uuid4())
    captured: list[OutboxEvent] = []

    async def _capture(_connection: object, event: OutboxEvent) -> None:
        captured.append(event)

    digest = "a" * 64
    with patch(
        "edgemint.workers.assignments.resolve_worker_session",
        AsyncMock(return_value=session),
    ), patch(
        "edgemint.workers.assignments.enqueue_outbox_event",
        side_effect=_capture,
    ), patch(
        "edgemint.workers.transport_recovery.TransportRecoveryService.record",
        AsyncMock(
            return_value=TransportRecordResult(
                classification=SubmissionClassification.TRANSPORT_FRESH,
                aggregate_sequence=5 * 1_000_000_000 + 3_000_000 + 2,
                is_new=True,
            )
        ),
    ), patch(
        "edgemint.workers.assignments.CheckpointResumeService.publish_manifest",
        AsyncMock(return_value=uuid4()),
    ):
        receipt = await AssignmentCommandService().checkpoint(
            connection,
            access_token="token",
            assignment_id=str(uuid4()),
            lease_token="lease-token",
            fence_token=5,
            sequence=2,
            model_version_id="mdv-qwen",
            input_sha256=digest,
            checkpoint_sha256=digest,
            encrypted_blob_ref="runtime/chunk_checkpoints/asg/0",
            chunk_index=0,
        )

    assert receipt["operation"] == "checkpointAssignment"
    event = captured[0]
    assert event.event_type == "task_checkpoint_saved"
    assert event.aggregate_sequence == 5 * 1_000_000_000 + 3_000_000 + 2
    assert event.cloud_event["type"] == "io.edgemint.task.checkpoint.saved.v1"
    assert event.cloud_event["data"]["chunkIndex"] == 0


@pytest.mark.asyncio
async def test_progress_rejects_stale_fence_before_outbox_write() -> None:
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
            await AssignmentCommandService().progress(
                connection,
                access_token="token",
                assignment_id=str(uuid4()),
                lease_token="lease-token",
                fence_token=7,
                sequence=1,
                stage="llm-map",
                progress_bps=1000,
            )
        assert exc.value.code == "ASSIGNMENT_STALE_FENCE"
        enqueue.assert_not_called()


@pytest.mark.asyncio
async def test_progress_sequence_ordering_documentation_bands() -> None:
    fence = 4
    assert fence * 1_000_000_000 + 2_000_000 + 1 < fence * 1_000_000_000 + 3_000_000 + 1
    assert fence * 1_000_000_000 + 3_000_000 + 9 < fence * 1_000_000_000 + 900_000_000
