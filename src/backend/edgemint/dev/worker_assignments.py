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
_delivered_at: dict[str, dict[str, str]] = {}
# Assignments the portal cancelled, including ones a worker already claimed.
_cancelled_ids: set[str] = set()
_exclusive_device_public_id: str | None = (
    os.environ.get("EDGEMINT_DEV_PIN_DEVICE_ID") or None
)
# Phones that asked for work recently. A task is offered to one of them at random.
_seen_devices: dict[str, datetime] = {}
_reserved_device: dict[str, str] = {}
_ONLINE_FOR = timedelta(seconds=90)


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


def clear_online_devices() -> None:
    _seen_devices.clear()
    _reserved_device.clear()


def note_online_device(device_public_id: str | None) -> None:
    device_id = (device_public_id or "").strip()
    if device_id:
        _seen_devices[device_id] = _now()


def online_device_ids() -> list[str]:
    cutoff = _now() - _ONLINE_FOR
    expired = [device_id for device_id, seen in _seen_devices.items() if seen < cutoff]
    for device_id in expired:
        del _seen_devices[device_id]
    return sorted(_seen_devices)


def choose_online_device(device_ids: list[str], requesting: str) -> str:
    """Pick one online phone. Tests replace this to keep the choice fixed."""
    del requesting
    return secrets.choice(device_ids)


def _peek_pending() -> dict[str, Any] | None:
    for assignment in _pending:
        if assignment["assignmentId"] not in _completed:
            return assignment
    return None


def claim_next_assignment(
    *,
    device_public_id: str | None = None,
    claim_exclusive: bool = False,
) -> dict[str, Any] | None:
    """Give the next task to one online phone, chosen at random.

    ``claim_exclusive`` no longer pins every later task to the first phone.
    An explicit ``EDGEMINT_DEV_PIN_DEVICE_ID`` still limits delivery to that phone.
    """
    del claim_exclusive
    if not _assignment_allowed_for_device(device_public_id):
        return None
    note_online_device(device_public_id)
    pending = _peek_pending()
    if pending is None:
        return None
    task_id = str(pending.get("taskId") or pending["assignmentId"])
    if device_public_id:
        online = online_device_ids()
        reserved = _reserved_device.get(task_id)
        if reserved not in online:
            reserved = choose_online_device(online, device_public_id)
            _reserved_device[task_id] = reserved
        if device_public_id != reserved:
            return None
    assignment = pop_next_assignment()
    if assignment is None:
        return None
    _reserved_device.pop(task_id, None)
    note_task_delivery(task_id, device_public_id)
    return assignment


def note_task_delivery(task_id: str, device_id: str | None) -> None:
    """Remember a worker that received this task, until it reports a result."""
    recipient = (device_id or "").strip() or "unattributed"
    _delivered_devices.setdefault(task_id, set()).add(recipient)
    _in_flight_devices.setdefault(task_id, set()).add(recipient)
    _delivered_at.setdefault(task_id, {})[recipient] = _now().isoformat()


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
    _reserved_device.pop(assignment_id, None)
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


def task_ids_with_open_dev_assignments() -> frozenset[str]:
    """Task IDs that must not be re-enqueued by portal sync (queued, in-flight, or awaiting result)."""
    open_ids: set[str] = set()
    for assignment in _pending:
        if assignment["assignmentId"] in _completed:
            continue
        task_id = assignment.get("taskId") or assignment.get("assignmentId")
        if task_id:
            open_ids.add(str(task_id))
    for task_id in _in_flight_devices:
        if task_id not in _completed:
            open_ids.add(str(task_id))
    for task_id in _delivered_devices:
        if task_id not in _completed and task_id not in _cancelled_ids:
            open_ids.add(str(task_id))
    return frozenset(open_ids)


def _delivery_state(task_id: str, device_id: str) -> str:
    if device_id in _failed_devices.get(task_id, {}):
        return "failed"
    if task_id in _cancelled_ids:
        return "cancelled"
    if device_id in _in_flight_devices.get(task_id, set()):
        return "running"
    if task_id in _completed:
        return "completed"
    return "delivered"


def delivery_ledger() -> dict[str, list[dict[str, Any]]]:
    """Per task, every device that received it and how that delivery ended."""
    ledger: dict[str, list[dict[str, Any]]] = {}
    for task_id, devices in _delivered_devices.items():
        failures = _failed_devices.get(task_id, {})
        times = _delivered_at.get(task_id, {})
        ledger[task_id] = [
            {
                "deviceId": device_id,
                "state": _delivery_state(task_id, device_id),
                "errorCode": failures.get(device_id),
                "deliveredAt": times.get(device_id),
            }
            for device_id in sorted(devices)
        ]
    return ledger


def dev_assignment_state() -> dict[str, Any]:
    return {
        "exclusiveDeviceId": preferred_device_public_id(),
        "items": list_pending_assignments(),
        "activeTaskIds": sorted(task_ids_with_open_dev_assignments()),
        "deliveries": delivery_ledger(),
    }
