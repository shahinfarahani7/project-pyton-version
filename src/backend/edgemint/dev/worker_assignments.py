from __future__ import annotations

import secrets
from datetime import UTC, datetime, timedelta
from typing import Any

from edgemint.dev.dev_public_urls import dev_api_public_base

_WORKER_MODEL_VERSION_ID = "mdv_qwen3_0_6b"

_pending: list[dict[str, Any]] = []
_completed: list[str] = []


def _now() -> datetime:
    return datetime.now(tz=UTC)


def enqueue_dev_assignment(*, task_id: str, task_type: str) -> dict[str, Any]:
    for existing in _pending:
        if existing.get("taskId") == task_id or existing.get("assignmentId") == task_id:
            return existing
    # Dev uses one ID everywhere so portal and worker logs match.
    assignment_id = task_id
    api_base = dev_api_public_base()
    assignment = {
        "assignmentId": assignment_id,
        "attemptId": f"att_{secrets.token_hex(4)}",
        "revisionId": f"rev_{secrets.token_hex(4)}",
        "leaseToken": f"lease_{secrets.token_hex(8)}",
        "fenceToken": 1,
        "leaseExpiresAt": (_now() + timedelta(minutes=30)).isoformat(),
        "taskType": task_type,
        "modelVersionId": _WORKER_MODEL_VERSION_ID,
        "inputManifestUrl": f"{api_base}/v1/dev/worker/tasks/{task_id}/input",
        "outputUploadUrl": f"{api_base}/v1/dev/worker/tasks/{task_id}/output",
        "startDeadlineAt": (_now() + timedelta(minutes=5)).isoformat(),
        "taskId": task_id,
    }
    _pending.append(assignment)
    return assignment


def pop_next_assignment() -> dict[str, Any] | None:
    while _pending:
        assignment = _pending.pop(0)
        if assignment["assignmentId"] not in _completed:
            # Dev tasks may sit in the in-memory queue while a model installs
            # or an emulator sleeps. Deadlines begin at actual delivery.
            delivered_at = _now()
            assignment["leaseExpiresAt"] = (
                delivered_at + timedelta(minutes=30)
            ).isoformat()
            assignment["startDeadlineAt"] = (
                delivered_at + timedelta(minutes=5)
            ).isoformat()
            return assignment
    return None


def command_receipt(operation_id: str) -> dict[str, Any]:
    return {
        "operationId": operation_id,
        "accepted": True,
        "status": "accepted",
        "occurredAt": _now().isoformat(),
    }


def mark_completed(assignment_id: str) -> None:
    if assignment_id not in _completed:
        _completed.append(assignment_id)
    _pending[:] = [
        assignment
        for assignment in _pending
        if assignment["assignmentId"] != assignment_id
    ]


def cancel_dev_assignment(assignment_id: str) -> bool:
    existed = any(
        assignment["assignmentId"] == assignment_id for assignment in _pending
    )
    mark_completed(assignment_id)
    return existed


def list_pending_assignments() -> list[dict[str, Any]]:
    return [assignment for assignment in _pending if assignment["assignmentId"] not in _completed]
