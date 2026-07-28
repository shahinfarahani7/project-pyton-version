from __future__ import annotations

import secrets
from typing import Any
from uuid import UUID

DEV_ORGANIZATION_ID = UUID("00000000-0000-0000-0000-000000000001")
DEV_PRINCIPAL_ID = UUID("00000000-0000-0000-0000-00000000000a")
DEV_WORKSPACE_PRIMARY = UUID("00000000-0000-0000-0000-00000000000b")
DEV_WORKSPACE_STAGING = UUID("00000000-0000-0000-0000-00000000000c")

DEV_WORKSPACE_IDS = frozenset({DEV_WORKSPACE_PRIMARY, DEV_WORKSPACE_STAGING})

PAGE = {"limit": 25, "hasMore": False}

_created_tasks: dict[UUID, list[dict[str, Any]]] = {}


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
            {
                "id": "tsk_dev_ocr_running",
                "taskType": "document.ocr",
                "lifecycleStatus": "running",
                "executionStatus": "in_progress",
                "version": 2,
            },
            {
                "id": "tsk_dev_nlp_done",
                "taskType": "text.summarize",
                "lifecycleStatus": "succeeded",
                "executionStatus": "completed",
                "version": 1,
            },
            {
                "id": "tsk_dev_vision_queued",
                "taskType": "image.classify",
                "lifecycleStatus": "queued",
                "executionStatus": "pending",
                "version": 1,
            },
        ]
    if workspace_id == DEV_WORKSPACE_STAGING:
        return [
            {
                "id": "tsk_dev_staging_draft",
                "taskType": "document.ocr",
                "lifecycleStatus": "draft",
                "executionStatus": "not_started",
                "version": 1,
            },
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
    task = {
        "id": f"tsk_dev_{secrets.token_hex(4)}",
        "taskType": task_type,
        "lifecycleStatus": "draft",
        "executionStatus": "not_started",
        "version": 1,
    }
    _created_tasks.setdefault(workspace_id, []).append(task)
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
