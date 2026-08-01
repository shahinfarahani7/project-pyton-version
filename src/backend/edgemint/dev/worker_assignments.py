from __future__ import annotations

import secrets
from datetime import UTC, datetime, timedelta
from typing import Any

from edgemint.dev.fixtures import WORKER_MODEL_VERSION_ID

_pending: list[dict[str, Any]] = []
_completed: list[str] = []


def _now() -> datetime:
    return datetime.now(tz=UTC)


def enqueue_dev_assignment(*, task_id: str, task_type: str) -> dict[str, Any]:
    assignment_id = f"asg_dev_{secrets.token_hex(4)}"
    assignment = {
        "assignmentId": assignment_id,
        "attemptId": f"att_{secrets.token_hex(4)}",
        "revisionId": f"rev_{secrets.token_hex(4)}",
        "leaseToken": f"lease_{secrets.token_hex(8)}",
        "fenceToken": 1,
        "leaseExpiresAt": (_now() + timedelta(minutes=30)).isoformat(),
        "taskType": task_type,
        "modelVersionId": WORKER_MODEL_VERSION_ID,
        "inputManifestUrl": f"http://127.0.0.1:8080/v1/dev/worker/tasks/{task_id}/input",
        "outputUploadUrl": f"http://127.0.0.1:8080/v1/dev/worker/tasks/{task_id}/output",
        "startDeadlineAt": (_now() + timedelta(minutes=5)).isoformat(),
        "taskId": task_id,
    }
    _pending.append(assignment)
    return assignment


def seed_dev_assignments() -> None:
    if _pending:
        return
    enqueue_dev_assignment(task_id="tsk_dev_vision_queued", task_type="image.classify")


def pop_next_assignment() -> dict[str, Any] | None:
    seed_dev_assignments()
    while _pending:
        assignment = _pending.pop(0)
        if assignment["assignmentId"] not in _completed:
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
    _completed.append(assignment_id)
