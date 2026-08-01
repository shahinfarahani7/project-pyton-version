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

WORKER_MODEL_VERSION_ID = "mdv_qwen3_0_6b"

PAGE = {"limit": 25, "hasMore": False}

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
) -> dict[str, Any]:
    return {
        "id": task_id,
        "taskType": task_type,
        "lifecycleStatus": lifecycle_status,
        "executionStatus": execution_status,
        "version": version,
        "createdAt": created_at,
        "updatedAt": updated_at or created_at,
    }


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
    return _seeded_tasks(workspace_id) + _created_tasks.get(workspace_id, [])


def dev_tasks(workspace_id: UUID) -> dict[str, Any]:
    return {"items": _tasks_for_workspace(workspace_id), "page": PAGE}


def dev_task(workspace_id: UUID, task_id: str) -> dict[str, Any] | None:
    for task in _tasks_for_workspace(workspace_id):
        if task["id"] == task_id:
            return task
    return None


def create_dev_task(workspace_id: UUID, *, task_type: str) -> dict[str, Any]:
    from edgemint.dev.worker_assignments import enqueue_dev_assignment

    task = _task_row(
        task_id=f"tsk_dev_{secrets.token_hex(4)}",
        task_type=task_type,
        lifecycle_status="queued",
        execution_status="pending",
        version=1,
        created_at=_now_iso(),
    )
    _created_tasks.setdefault(workspace_id, []).append(task)
    enqueue_dev_assignment(task_id=task["id"], task_type=task_type)
    return task


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
