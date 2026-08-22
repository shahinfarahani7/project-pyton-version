from __future__ import annotations

import base64

from typing import Any

from pydantic import BaseModel, Field

from edgemint.building_blocks.settings import get_settings
from edgemint.dev import worker_task_inputs
from fastapi import APIRouter, HTTPException

router = APIRouter()


class DevWorkerOutputRequest(BaseModel):
    resultText: str = Field(min_length=1)
    metrics: dict[str, Any] = Field(default_factory=dict)
    resultFileBase64: str | None = None
    resultFileName: str | None = None
    resultMimeType: str | None = None


class DevEnsureTaskInputRequest(BaseModel):
    taskType: str = Field(min_length=1)


def _dev_enabled() -> bool:
    return get_settings().environment in {"development", "test"}


@router.get("/v1/dev/worker/tasks/{task_id}/input")
async def worker_task_input(task_id: str, taskType: str | None = None) -> dict:
    if not _dev_enabled():
        raise HTTPException(503, "DEV_WORKER_API_DISABLED")
    if taskType:
        worker_task_inputs.ensure_registered(task_id=task_id, task_type=taskType)
    manifest = worker_task_inputs.input_manifest(task_id)
    if manifest is None:
        raise HTTPException(404, "TASK_INPUT_NOT_FOUND")
    return manifest


@router.get("/v1/dev/worker/tasks/{task_id}/input/content")
async def worker_task_input_content(task_id: str):
    if not _dev_enabled():
        raise HTTPException(503, "DEV_WORKER_API_DISABLED")
    blob = worker_task_inputs.input_content(task_id)
    if blob is None:
        raise HTTPException(404, "TASK_INPUT_CONTENT_NOT_FOUND")
    return worker_task_inputs.content_response(blob)


@router.get("/v1/dev/worker/tasks/{task_id}/result/content")
async def worker_task_result_content(task_id: str):
    if not _dev_enabled():
        raise HTTPException(503, "DEV_WORKER_API_DISABLED")
    blob = worker_task_inputs.result_content(task_id)
    if blob is None:
        raise HTTPException(404, "TASK_RESULT_CONTENT_NOT_FOUND")
    return worker_task_inputs.content_response(blob)


@router.post("/v1/dev/worker/tasks/{task_id}/output", status_code=201)
async def worker_task_output(task_id: str, payload: DevWorkerOutputRequest) -> dict:
    if not _dev_enabled():
        raise HTTPException(503, "DEV_WORKER_API_DISABLED")
    if worker_task_inputs.input_manifest(task_id) is None:
        raise HTTPException(404, "TASK_INPUT_NOT_FOUND")
    result_file_bytes = None
    if payload.resultFileBase64:
        try:
            result_file_bytes = base64.b64decode(payload.resultFileBase64)
        except ValueError as exc:
            raise HTTPException(422, "RESULT_FILE_INVALID_BASE64") from exc
    worker_task_inputs.record_output(
        task_id=task_id,
        result_text=payload.resultText,
        metrics=payload.metrics,
        result_file_bytes=result_file_bytes,
        result_file_name=payload.resultFileName,
        result_mime_type=payload.resultMimeType,
    )
    return {"taskId": task_id, "status": "accepted", "hasResultFile": bool(result_file_bytes)}


@router.post("/internal/dev/tasks/{task_id}/ensure-input", status_code=204)
async def ensure_worker_task_input(task_id: str, payload: DevEnsureTaskInputRequest) -> None:
    if not _dev_enabled():
        raise HTTPException(503, "DEV_WORKER_API_DISABLED")
    worker_task_inputs.ensure_registered(task_id=task_id, task_type=payload.taskType)


@router.post("/internal/dev/sync-worker-queue")
async def sync_worker_queue() -> dict[str, str]:
    if not _dev_enabled():
        raise HTTPException(503, "DEV_WORKER_API_DISABLED")
    from edgemint.dev import fixtures

    fixtures.sync_all_pending_tasks_to_worker()
    return {"status": "synced"}
