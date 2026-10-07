from __future__ import annotations

import base64
import json

from typing import Any

from pydantic import BaseModel, Field

from edgemint.building_blocks.settings import get_settings
from edgemint.dev import fixtures
from edgemint.dev import worker_task_inputs

try:
    from edgemint.results.text_summarize_constraints import (
        summarize_constraints_from_manifest,
        validate_summarize_data,
    )
    from edgemint.results.validator import extract_task_result_payload
except ImportError:

    def summarize_constraints_from_manifest(_manifest: dict[str, Any]) -> None:
        return None

    def validate_summarize_data(_data: dict[str, Any], *, constraints: Any = None) -> None:
        return None

    def extract_task_result_payload(envelope: dict[str, Any]) -> dict[str, Any]:
        return envelope

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


class DevTaskFailureRequest(BaseModel):
    errorCode: str = Field(min_length=1, max_length=64)
    detail: str | None = Field(default=None, max_length=500)


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
    manifest = worker_task_inputs.input_manifest(task_id)
    if manifest is None:
        raise HTTPException(404, "TASK_INPUT_NOT_FOUND")
    structured_raw = payload.metrics.get("structuredResultJson")
    if isinstance(structured_raw, str) and structured_raw.strip():
        try:
            envelope = json.loads(structured_raw)
        except json.JSONDecodeError as exc:
            raise HTTPException(422, "STRUCTURED_RESULT_INVALID_JSON") from exc
        if not isinstance(envelope, dict):
            raise HTTPException(422, "STRUCTURED_RESULT_INVALID_JSON")
        task_type = str(manifest.get("taskType", ""))
        if task_type == "text.summarize":
            extracted = extract_task_result_payload(envelope)
            data = extracted.get("data")
            if not isinstance(data, dict):
                raise HTTPException(422, "SUMMARIZE_RESULT_INVALID_SHAPE")
            constraints = summarize_constraints_from_manifest(manifest)
            from edgemint.results.text_summarize_constraints import normalize_summarize_data

            outcome = validate_summarize_data(normalize_summarize_data(data), constraints)
            if not outcome.passed:
                detail = outcome.blocking_violations[0]
                rejection = {
                    "code": "SUMMARIZE_OUTPUT_REJECTED",
                    "detail": detail,
                    "violations": list(outcome.blocking_violations),
                }
                existing = fixtures.dev_task_by_id(task_id)
                if existing is not None and existing.get("lifecycleStatus") == "succeeded":
                    raise HTTPException(422, rejection)
                fixtures.reject_dev_task_output(
                    task_id,
                    reason_code="SUMMARIZE_OUTPUT_REJECTED",
                    reason_detail=detail,
                )
                raise HTTPException(422, rejection)
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


@router.post("/internal/dev/tasks/{task_id}/fail", status_code=204)
async def report_worker_task_failure(task_id: str, payload: DevTaskFailureRequest) -> None:
    """Mark a portal task failed after every worker that received it has errored."""
    if not _dev_enabled():
        raise HTTPException(503, "DEV_WORKER_API_DISABLED")
    detail = (payload.detail or payload.errorCode).strip()
    updated = fixtures.reject_dev_task_output(
        task_id,
        reason_code=payload.errorCode,
        reason_detail=detail,
    )
    if updated:
        return
    if fixtures.dev_task_by_id(task_id) is None:
        raise HTTPException(404, "TASK_NOT_FOUND")


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
