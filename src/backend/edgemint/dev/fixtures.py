from __future__ import annotations

import secrets
from datetime import UTC, datetime
from typing import Any
from uuid import UUID

DEV_ORGANIZATION_ID = UUID("00000000-0000-0000-0000-000000000001")
DEV_PRINCIPAL_ID = UUID("00000000-0000-0000-0000-00000000000a")
DEV_WORKSPACE_PRIMARY = UUID("00000000-0000-0000-0000-00000000000b")
DEV_WORKSPACE_STAGING = UUID("00000000-0000-0000-0000-00000000000c")

DEV_WORKSPACE_IDS = frozenset({DEV_WORKSPACE_PRIMARY, DEV_WORKSPACE_STAGING})

WORKER_MODEL_VERSION_ID = "mdv_qwen2_5_1_5b"

PAGE = {"limit": 25, "hasMore": False}

_PREVIEW_INPUT_CHARS = 2000
_PREVIEW_RESULT_CHARS = 500
_MAX_STORED_TEXT_CHARS = 32_000

_created_tasks: dict[UUID, list[dict[str, Any]]] = {}


def _now_iso() -> str:
    return datetime.now(tz=UTC).isoformat()


def _task_row(
    *,
    task_id: str,
    task_type: str,
    lifecycle_status: str,
    execution_status: str,
    version: int,
    created_at: str,
    updated_at: str | None = None,
    assignment_id: str | None = None,
) -> dict[str, Any]:
    row = {
        "id": task_id,
        "taskType": task_type,
        "lifecycleStatus": lifecycle_status,
        "executionStatus": execution_status,
        "version": version,
        "createdAt": created_at,
        "updatedAt": updated_at or created_at,
    }
    if assignment_id is not None:
        row["assignmentId"] = assignment_id
    return row


def is_dev_principal(principal_id: UUID) -> bool:
    return principal_id == DEV_PRINCIPAL_ID


def dev_principal() -> dict[str, Any]:
    return {
        "id": str(DEV_PRINCIPAL_ID),
        "displayName": "Dev User",
        "email": "dev-user@edgemint.local",
        "subject": "dev-user@edgemint.local",
    }


def dev_workspaces() -> list[dict[str, Any]]:
    return [
        {
            "id": str(DEV_WORKSPACE_PRIMARY),
            "name": "Primary workspace",
            "environment": "production",
            "status": "active",
            "version": 1,
        },
        {
            "id": str(DEV_WORKSPACE_STAGING),
            "name": "Staging workspace",
            "environment": "staging",
            "status": "active",
            "version": 1,
        },
    ]


def _seeded_tasks(workspace_id: UUID) -> list[dict[str, Any]]:
    if workspace_id == DEV_WORKSPACE_PRIMARY:
        return [
            _task_row(
                task_id="tsk_dev_ocr_running",
                task_type="document.ocr",
                lifecycle_status="running",
                execution_status="in_progress",
                version=2,
                created_at="2026-07-27T08:15:00+00:00",
                updated_at="2026-07-28T09:40:00+00:00",
            ),
            _task_row(
                task_id="tsk_dev_nlp_done",
                task_type="text.summarize",
                lifecycle_status="succeeded",
                execution_status="completed",
                version=1,
                created_at="2026-07-25T14:30:00+00:00",
                updated_at="2026-07-26T11:05:00+00:00",
            ),
            _task_row(
                task_id="tsk_dev_vision_queued",
                task_type="image.classify",
                lifecycle_status="queued",
                execution_status="pending",
                version=1,
                created_at="2026-07-28T16:00:00+00:00",
            ),
        ]
    if workspace_id == DEV_WORKSPACE_STAGING:
        return [
            _task_row(
                task_id="tsk_dev_staging_draft",
                task_type="document.ocr",
                lifecycle_status="draft",
                execution_status="not_started",
                version=1,
                created_at="2026-07-24T07:20:00+00:00",
            ),
        ]
    return []


def _tasks_for_workspace(workspace_id: UUID) -> list[dict[str, Any]]:
    tasks = _seeded_tasks(workspace_id) + _created_tasks.get(workspace_id, [])
    known_ids = {task["id"] for task in tasks}
    for assignment in _reconcile_worker_pending_tasks():
        task_id = assignment.get("taskId") or assignment.get("assignmentId")
        if not task_id or task_id in known_ids:
            continue
        tasks.append(
            _task_row(
                task_id=task_id,
                task_type=assignment["taskType"],
                lifecycle_status="queued",
                execution_status="pending",
                version=1,
                created_at=_now_iso(),
                assignment_id=task_id,
            )
        )
        known_ids.add(task_id)
    _sync_pending_tasks_to_worker_queue(_created_tasks.get(workspace_id, []))
    tasks.sort(key=lambda task: task.get("createdAt", ""), reverse=True)
    return tasks


def _sync_pending_tasks_to_worker_queue(tasks: list[dict[str, Any]]) -> None:
    from edgemint.dev.assignment_bridge import (
        enqueue_assignment_for_worker,
        fetch_pending_assignments_from_worker,
    )

    try:
        pending_ids = {
            assignment.get("taskId") or assignment.get("assignmentId")
            for assignment in fetch_pending_assignments_from_worker()
        }
    except Exception:
        return

    for task in tasks:
        if task.get("executionStatus") != "pending":
            continue
        if task.get("lifecycleStatus") not in {"queued", "running"}:
            continue
        task_id = task.get("id")
        task_type = task.get("taskType")
        if not task_id or not task_type or task_id in pending_ids:
            continue
        enqueue_assignment_for_worker(task_id=task_id, task_type=task_type)
        pending_ids.add(task_id)


def sync_all_pending_tasks_to_worker() -> None:
    from edgemint.dev import worker_assignments, worker_task_inputs
    from edgemint.dev.assignment_bridge import (
        clear_exclusive_device_pin_on_worker_registry,
        fetch_pending_assignments_from_worker,
    )

    worker_assignments.clear_runtime_exclusive_device_pin()
    clear_exclusive_device_pin_on_worker_registry()

    for workspace_id in DEV_WORKSPACE_IDS:
        _sync_pending_tasks_to_worker_queue(_created_tasks.get(workspace_id, []))

    for assignment in fetch_pending_assignments_from_worker():
        task_id = assignment.get("taskId") or assignment.get("assignmentId")
        task_type = assignment.get("taskType")
        if task_id and task_type:
            worker_task_inputs.ensure_registered(task_id=task_id, task_type=task_type)


def _reconcile_worker_pending_tasks() -> list[dict[str, Any]]:
    from edgemint.dev.assignment_bridge import fetch_pending_assignments_from_worker

    try:
        return fetch_pending_assignments_from_worker()
    except Exception:
        return []


def dev_tasks(workspace_id: UUID) -> dict[str, Any]:
    return {"items": _tasks_for_workspace(workspace_id), "page": PAGE}


def dev_task(workspace_id: UUID, task_id: str) -> dict[str, Any] | None:
    for task in _tasks_for_workspace(workspace_id):
        if task["id"] == task_id:
            return task
    return None


def find_task_workspace(task_id: str) -> UUID | None:
    for workspace_id, tasks in _created_tasks.items():
        if any(task["id"] == task_id for task in tasks):
            return workspace_id
    for workspace_id in DEV_WORKSPACE_IDS:
        if any(task["id"] == task_id for task in _seeded_tasks(workspace_id)):
            return workspace_id
    return None


def _notify_task_event(workspace_id: UUID, task_id: str, event: str) -> None:
    from edgemint.dev import task_events, task_type_catalog

    task = dev_task(workspace_id, task_id)
    if task is None:
        return
    task_events.publish_task_event(
        workspace_id,
        event=event,
        task_id=task_id,
        task=task_type_catalog.enrich_task_row(dict(task)),
    )


def create_dev_task(
    workspace_id: UUID,
    *,
    task_type: str,
    input_text: str | None = None,
    instructions: str | None = None,
    file_name: str | None = None,
    file_mime: str | None = None,
    file_bytes: bytes | None = None,
    summarize_options: dict[str, Any] | None = None,
) -> dict[str, Any]:
    from edgemint.dev.assignment_bridge import enqueue_assignment_for_worker

    task = _task_row(
        task_id=f"tsk_dev_{secrets.token_hex(4)}",
        task_type=task_type,
        lifecycle_status="queued",
        execution_status="pending",
        version=1,
        created_at=_now_iso(),
    )
    if input_text or instructions or file_bytes:
        task["inputLabel"] = file_name or (
            "Pasted text" if input_text and not file_bytes else "Customer upload"
        )
        if input_text and input_text.strip():
            full_input = input_text.strip()[:_MAX_STORED_TEXT_CHARS]
            task["inputText"] = full_input
            task["inputPreview"] = full_input[:_PREVIEW_INPUT_CHARS]
        if instructions and instructions.strip():
            task["instructions"] = instructions.strip()[:_MAX_STORED_TEXT_CHARS]
        task["inputSource"] = {
            "input_text": input_text,
            "instructions": instructions,
            "file_name": file_name,
            "file_mime": file_mime,
            "file_bytes": file_bytes,
        }
    _created_tasks.setdefault(workspace_id, []).append(task)
    from edgemint.dev import worker_task_inputs

    worker_task_inputs.register_task(
        task_id=task["id"],
        task_type=task_type,
        input_text=input_text,
        instructions=instructions,
        file_name=file_name,
        file_mime=file_mime,
        file_bytes=file_bytes,
        summarize_options=summarize_options,
    )
    enqueue_assignment_for_worker(task_id=task["id"], task_type=task_type)
    task["assignmentId"] = task["id"]
    task.pop("inputSource", None)
    _notify_task_event(workspace_id, task["id"], "task.created")
    return task


def dev_task_by_id(task_id: str) -> dict[str, Any] | None:
    workspace_id = find_task_workspace(task_id)
    if workspace_id is None:
        return None
    return dev_task(workspace_id, task_id)


def reject_dev_task_output(
    task_id: str,
    *,
    reason_code: str,
    reason_detail: str,
) -> bool:
    """Persist terminal failure when worker output is rejected.

    Returns False when the task already succeeded (accepted result must not be downgraded).
    """
    task = dev_task_by_id(task_id)
    if task is None:
        return False
    if task["lifecycleStatus"] == "succeeded":
        return False
    if task["lifecycleStatus"] in {"failed", "cancelled", "expired"}:
        return True
    update_dev_task_execution(
        task_id,
        lifecycle_status="failed",
        execution_status="failed",
        failure_reason_code=reason_code,
        failure_reason=reason_detail,
    )
    return True


def cancel_dev_task(workspace_id: UUID, task_id: str) -> dict[str, Any] | None:
    from edgemint.dev.assignment_bridge import cancel_assignment_for_worker

    task = next(
        (
            item
            for item in _created_tasks.get(workspace_id, [])
            if item["id"] == task_id
        ),
        None,
    )
    if task is None:
        return None
    if task["lifecycleStatus"] in {"succeeded", "failed", "cancelled", "expired"}:
        return task

    task["lifecycleStatus"] = "cancelled"
    task["executionStatus"] = "cancelled"
    task["updatedAt"] = _now_iso()
    task["version"] = int(task.get("version", 0)) + 1
    cancel_assignment_for_worker(assignment_id=task_id)
    _notify_task_event(workspace_id, task_id, "task.cancelled")
    return task


def update_dev_task_execution(
    task_id: str,
    *,
    lifecycle_status: str,
    execution_status: str,
    result_preview: str | None = None,
    result_text: str | None = None,
    result_artifact_url: str | None = None,
    result_mime_type: str | None = None,
    failure_reason_code: str | None = None,
    failure_reason: str | None = None,
    model_transcript: str | None = None,
) -> bool:
    updated = False
    workspace_id: UUID | None = None
    for ws_id, tasks in _created_tasks.items():
        for task in tasks:
            if task["id"] == task_id:
                workspace_id = ws_id
                task["lifecycleStatus"] = lifecycle_status
                task["executionStatus"] = execution_status
                task["updatedAt"] = _now_iso()
                if result_text is not None:
                    stored = result_text[:_MAX_STORED_TEXT_CHARS]
                    task["resultText"] = stored
                    task["resultPreview"] = stored[:_PREVIEW_RESULT_CHARS]
                elif result_preview is not None:
                    stored = result_preview[:_MAX_STORED_TEXT_CHARS]
                    task["resultText"] = stored
                    task["resultPreview"] = stored[:_PREVIEW_RESULT_CHARS]
                if model_transcript is not None:
                    task["modelTranscript"] = model_transcript[:_MAX_STORED_TEXT_CHARS]
                if result_artifact_url is not None:
                    task["resultArtifactUrl"] = result_artifact_url
                if result_mime_type is not None:
                    task["resultMimeType"] = result_mime_type
                if failure_reason_code is not None:
                    task["failureReasonCode"] = failure_reason_code
                if failure_reason is not None:
                    task["failureReason"] = failure_reason[:500]
                updated = True
    for ws_id in (DEV_WORKSPACE_PRIMARY, DEV_WORKSPACE_STAGING):
        for task in _seeded_tasks(ws_id):
            if task["id"] == task_id:
                workspace_id = ws_id
                task["lifecycleStatus"] = lifecycle_status
                task["executionStatus"] = execution_status
                task["updatedAt"] = _now_iso()
                if result_text is not None:
                    stored = result_text[:_MAX_STORED_TEXT_CHARS]
                    task["resultText"] = stored
                    task["resultPreview"] = stored[:_PREVIEW_RESULT_CHARS]
                elif result_preview is not None:
                    stored = result_preview[:_MAX_STORED_TEXT_CHARS]
                    task["resultText"] = stored
                    task["resultPreview"] = stored[:_PREVIEW_RESULT_CHARS]
                if model_transcript is not None:
                    task["modelTranscript"] = model_transcript[:_MAX_STORED_TEXT_CHARS]
                if result_artifact_url is not None:
                    task["resultArtifactUrl"] = result_artifact_url
                if result_mime_type is not None:
                    task["resultMimeType"] = result_mime_type
                if failure_reason_code is not None:
                    task["failureReasonCode"] = failure_reason_code
                if failure_reason is not None:
                    task["failureReason"] = failure_reason[:500]
                updated = True
    if updated and workspace_id is not None:
        _notify_task_event(workspace_id, task_id, "task.updated")
    return updated


def dev_webhooks(workspace_id: UUID) -> dict[str, Any]:
    if workspace_id == DEV_WORKSPACE_PRIMARY:
        items = [
            {"id": "wh_dev_primary_tasks", "status": "active", "version": 1},
            {"id": "wh_dev_primary_billing", "status": "paused", "version": 2},
        ]
    elif workspace_id == DEV_WORKSPACE_STAGING:
        items = [{"id": "wh_dev_staging", "status": "active", "version": 1}]
    else:
        items = []
    return {"items": items, "page": PAGE}


def dev_api_keys(workspace_id: UUID) -> dict[str, Any]:
    if workspace_id == DEV_WORKSPACE_PRIMARY:
        items = [
            {"id": "key_dev_primary_live", "status": "active", "version": 3},
            {"id": "key_dev_primary_ro", "status": "active", "version": 1},
        ]
    elif workspace_id == DEV_WORKSPACE_STAGING:
        items = [{"id": "key_dev_staging", "status": "active", "version": 1}]
    else:
        items = []
    return {"items": items, "page": PAGE}


def dev_usage(workspace_id: UUID) -> dict[str, Any]:
    if workspace_id == DEV_WORKSPACE_PRIMARY:
        return {
            "status": "ready",
            "period": "2026-07",
            "taskCount": 1284,
            "computeMicroEur": 45200000,
        }
    if workspace_id == DEV_WORKSPACE_STAGING:
        return {
            "status": "ready",
            "period": "2026-07",
            "taskCount": 42,
            "computeMicroEur": 890000,
        }
    return {"status": "empty", "period": "2026-07", "taskCount": 0, "computeMicroEur": 0}


def dev_credit_balance(workspace_id: UUID) -> dict[str, Any]:
    if workspace_id == DEV_WORKSPACE_PRIMARY:
        return {"status": "ready", "availableMicroEur": 250000000, "reservedMicroEur": 12500000}
    if workspace_id == DEV_WORKSPACE_STAGING:
        return {"status": "ready", "availableMicroEur": 50000000, "reservedMicroEur": 0}
    return {"status": "empty", "availableMicroEur": 0, "reservedMicroEur": 0}


def dev_invoices(workspace_id: UUID) -> dict[str, Any]:
    if workspace_id == DEV_WORKSPACE_PRIMARY:
        items = [
            {"id": "inv_dev_open_001", "status": "open", "amountDueMicroEur": 125000000},
            {"id": "inv_dev_paid_002", "status": "paid", "amountDueMicroEur": 89000000},
        ]
    elif workspace_id == DEV_WORKSPACE_STAGING:
        items = [{"id": "inv_dev_staging_draft", "status": "draft", "amountDueMicroEur": 42000000}]
    else:
        items = []
    return {"items": items, "page": PAGE}


def dev_disputes(workspace_id: UUID) -> dict[str, Any]:
    if workspace_id == DEV_WORKSPACE_PRIMARY:
        items = [
            {"id": "dsp_dev_quality_open", "status": "open"},
            {"id": "dsp_dev_billing_closed", "status": "resolved"},
        ]
    elif workspace_id == DEV_WORKSPACE_STAGING:
        items = [{"id": "dsp_dev_staging_sla", "status": "open"}]
    else:
        items = []
    return {"items": items, "page": PAGE}
