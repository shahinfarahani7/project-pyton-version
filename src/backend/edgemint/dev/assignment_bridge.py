from __future__ import annotations

import os
from typing import Any

import httpx

_WORKER_REGISTRY = os.environ.get("EDGEMINT_WORKER_REGISTRY_URL", "http://worker-registry:8080").rstrip("/")


def enqueue_assignment_for_worker(*, task_id: str, task_type: str) -> dict[str, Any]:
    """Push a dev assignment to worker-registry (separate container from api-gateway)."""
    url = f"{_WORKER_REGISTRY}/internal/dev/assignments"
    try:
        with httpx.Client(timeout=5.0) as client:
            response = client.post(url, json={"taskId": task_id, "taskType": task_type})
            response.raise_for_status()
            return response.json()
    except (httpx.HTTPError, OSError, RuntimeError):
        pass

    from edgemint.dev.worker_assignments import enqueue_dev_assignment

    return enqueue_dev_assignment(task_id=task_id, task_type=task_type)


def fetch_pending_assignments_from_worker() -> list[dict[str, Any]]:
    """Return assignments still queued on worker-registry (survives api-gateway restart)."""
    url = f"{_WORKER_REGISTRY}/internal/dev/assignments"
    try:
        with httpx.Client(timeout=5.0) as client:
            response = client.get(url)
            response.raise_for_status()
            body = response.json()
            items = body.get("items", body)
            return items if isinstance(items, list) else []
    except (httpx.HTTPError, OSError, RuntimeError):
        pass

    from edgemint.dev.worker_assignments import list_pending_assignments

    return list_pending_assignments()
