from __future__ import annotations

from unittest.mock import AsyncMock
from uuid import uuid4

import pytest

from edgemint.tasks.errors import TaskServiceError
from edgemint.tasks.task_run import (
    NON_TERMINAL_STATUSES,
    TERMINAL_STATUSES,
    TaskRunService,
    TaskRunStatus,
    compute_input_digest,
)


class _ScalarResult:
    def __init__(self, value: object) -> None:
        self._value = value

    def scalar_one(self) -> object:
        return self._value


class _ScalarsResult:
    def __init__(self, values: list[object]) -> None:
        self._values = values

    def scalars(self) -> _ScalarsResult:
        return self

    def all(self) -> list[object]:
        return self._values


def test_task_run_status_partition_covers_all_values() -> None:
    assert TERMINAL_STATUSES | NON_TERMINAL_STATUSES == set(TaskRunStatus)
    assert TERMINAL_STATUSES.isdisjoint(NON_TERMINAL_STATUSES)


def test_compute_input_digest_is_stable_and_file_aware() -> None:
    digest_a = compute_input_digest(
        inline_text="hello",
        parameters_json='{"configuration":{"priority":"standard"},"metadata":{}}',
        input_file_id=None,
    )
    digest_b = compute_input_digest(
        inline_text="hello",
        parameters_json='{"configuration":{"priority":"standard"},"metadata":{}}',
        input_file_id=None,
    )
    digest_c = compute_input_digest(
        inline_text="world",
        parameters_json='{"configuration":{"priority":"standard"},"metadata":{}}',
        input_file_id=None,
    )
    assert digest_a == digest_b
    assert digest_a != digest_c
    assert len(digest_a) == 64


@pytest.mark.asyncio
async def test_commit_terminal_rejects_non_terminal_status() -> None:
    service = TaskRunService()
    with pytest.raises(TaskServiceError) as exc_info:
        await service.commit_terminal(
            AsyncMock(),
            task_run_id=uuid4(),
            terminal_status=TaskRunStatus.EXECUTING,
            terminal_outcome="invalid",
        )
    assert exc_info.value.code == "INPUT_SCHEMA_INVALID"


@pytest.mark.asyncio
async def test_commit_terminal_returns_committed_flag() -> None:
    service = TaskRunService()
    connection = AsyncMock()
    task_run_id = uuid4()
    connection.execute = AsyncMock(return_value=_ScalarResult(True))

    commit = await service.commit_terminal(
        connection,
        task_run_id=task_run_id,
        terminal_status=TaskRunStatus.SUCCEEDED,
        terminal_outcome="assignment_complete",
    )

    assert commit.committed is True
    assert commit.task_run_id == task_run_id
    assert commit.terminal_status is TaskRunStatus.SUCCEEDED


@pytest.mark.asyncio
async def test_commit_terminal_second_call_reports_not_committed() -> None:
    service = TaskRunService()
    connection = AsyncMock()
    task_run_id = uuid4()
    connection.execute = AsyncMock(return_value=_ScalarResult(False))

    commit = await service.commit_terminal(
        connection,
        task_run_id=task_run_id,
        terminal_status=TaskRunStatus.CANCELLED,
        terminal_outcome="client_cancel",
    )

    assert commit.committed is False


@pytest.mark.asyncio
async def test_cancel_open_runs_for_task_commits_each_nonterminal_run() -> None:
    service = TaskRunService()
    connection = AsyncMock()
    run_a = uuid4()
    run_b = uuid4()
    connection.execute = AsyncMock(
        side_effect=[
            _ScalarsResult([run_a, run_b]),
            _ScalarResult(True),
            _ScalarResult(True),
        ]
    )

    commits = await service.cancel_open_runs_for_task(
        connection,
        workspace_id=uuid4(),
        task_id=uuid4(),
    )

    assert len(commits) == 2
    assert all(commit.committed for commit in commits)
    assert commits[0].terminal_status is TaskRunStatus.CANCELLED
