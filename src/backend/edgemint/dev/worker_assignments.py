from __future__ import annotations

import os
import secrets
from datetime import UTC, datetime, timedelta
from typing import Any

from edgemint.dev.dev_public_urls import dev_api_public_base

_WORKER_MODEL_VERSION_ID = "mdv_gemma_4_e4b_it"

_pending: list[dict[str, Any]] = []
_completed: list[str] = []
# Workers that have actually received a task, and which of them failed it.
_delivered_devices: dict[str, set[str]] = {}
_in_flight_devices: dict[str, set[str]] = {}
_failed_devices: dict[str, dict[str, str]] = {}
# Assignments the portal cancelled, including ones a worker already claimed.
_cancelled_ids: set[str] = set()
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
    assignment = pop_next_assignment()
    if assignment is None:
        return None
    task_id = str(assignment.get("taskId") or assignment["assignmentId"])
    note_task_delivery(task_id, device_public_id)
    return assignment


def note_task_delivery(task_id: str, device_id: str | None) -> None:
    """Remember a worker that received this task, until it reports a result."""
    recipient = (device_id or "").strip() or "unattributed"
    _delivered_devices.setdefault(task_id, set()).add(recipient)
    _in_flight_devices.setdefault(task_id, set()).add(recipient)


def record_worker_failure(
    *,
    task_id: str,
    device_id: str | None,
    error_code: str,
) -> bool:
    """Record one worker failure.

    Returns True only when every worker that received the task has failed and
    none of those deliveries are still running. A later worker that has not
    been given the task does not keep it queued.
    """
    delivered = _delivered_devices.setdefault(task_id, set())
    in_flight = _in_flight_devices.setdefault(task_id, set())
    resolved = (device_id or "").strip()
    if resolved and resolved not in delivered and len(in_flight) == 1:
        resolved = next(iter(in_flight))
    elif not resolved:
        resolved = next(iter(in_flight)) if len(in_flight) == 1 else "unattributed"
    delivered.add(resolved)
    in_flight.discard(resolved)
    _failed_devices.setdefault(task_id, {})[resolved] = error_code
    mark_completed(task_id)
    failed_ids = set(_failed_devices.get(task_id, {}))
    return bool(delivered) and delivered <= failed_ids and not in_flight


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
    ) or assignment_id in _in_flight_devices
    _cancelled_ids.add(assignment_id)
    _in_flight_devices.pop(assignment_id, None)
    mark_completed(assignment_id)
    return existed


def is_assignment_cancelled(assignment_id: str) -> bool:
    return assignment_id in _cancelled_ids


def list_pending_assignments() -> list[dict[str, Any]]:
    return [assignment for assignment in _pending if assignment["assignmentId"] not in _completed]


def dev_assignment_state() -> dict[str, Any]:
    return {
        "exclusiveDeviceId": preferred_device_public_id(),
        "items": list_pending_assignments(),
    }
