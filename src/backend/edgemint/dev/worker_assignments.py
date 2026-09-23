from __future__ import annotations

import os
import secrets
from datetime import UTC, datetime, timedelta
from typing import Any

from edgemint.dev.dev_public_urls import dev_api_public_base

_WORKER_MODEL_VERSION_ID = "mdv_qwen2_5_1_5b"

_pending: list[dict[str, Any]] = []
_completed: list[str] = []
_exclusive_device_public_id: str | None = (
    os.environ.get("EDGEMINT_DEV_PIN_DEVICE_ID") or None
)


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


def preferred_device_public_id() -> str | None:
    return _exclusive_device_public_id


def register_exclusive_device(device_public_id: str) -> None:
    global _exclusive_device_public_id
    env_pin = os.environ.get("EDGEMINT_DEV_PIN_DEVICE_ID")
    if env_pin:
        return
    if _exclusive_device_public_id is None:
        _exclusive_device_public_id = device_public_id


def clear_runtime_exclusive_device_pin() -> None:
    """Drop the first-claim dev pin so sync/reconcile can deliver to a new emulator."""
    global _exclusive_device_public_id
    if os.environ.get("EDGEMINT_DEV_PIN_DEVICE_ID"):
        return
    _exclusive_device_public_id = None


def _assignment_allowed_for_device(device_public_id: str | None) -> bool:
    pin = os.environ.get("EDGEMINT_DEV_PIN_DEVICE_ID") or _exclusive_device_public_id
    if pin is None:
        return True
    return device_public_id == pin


def claim_next_assignment(
    *,
    device_public_id: str | None = None,
    claim_exclusive: bool = False,
) -> dict[str, Any] | None:
    if claim_exclusive and device_public_id:
        register_exclusive_device(device_public_id)
    if not _assignment_allowed_for_device(device_public_id):
        return None
    return pop_next_assignment()


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


def dev_assignment_state() -> dict[str, Any]:
    return {
        "exclusiveDeviceId": preferred_device_public_id(),
        "items": list_pending_assignments(),
    }
