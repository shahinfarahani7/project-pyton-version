from __future__ import annotations

import os
from collections import Counter
from collections.abc import Mapping, Sequence
from typing import Any

import httpx
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncConnection

_API_GATEWAY = os.environ.get("EDGEMINT_API_GATEWAY_URL", "http://api-gateway:8080").rstrip("/")
_WORKER_REGISTRY = os.environ.get("EDGEMINT_WORKER_REGISTRY_URL", "http://worker-registry:8080").rstrip("/")

_DEVICES_SQL = text(
    """
    SELECT d.public_id AS device_public_id, w.public_id AS worker_public_id,
           d.platform, d.device_tier
    FROM public.worker_devices d
    JOIN public.workers w ON w.id = d.worker_id
    WHERE d.public_id = ANY(:device_ids)
    """
)


class TaskMonitorUnavailable(Exception):
    def __init__(self, source: str) -> None:
        super().__init__(source)
        self.source = source


def build_task_monitor(
    tasks: Sequence[Mapping[str, Any]],
    state: Mapping[str, Any],
    devices: Mapping[str, Mapping[str, Any]],
) -> dict[str, Any]:
    deliveries: Mapping[str, list[dict[str, Any]]] = state.get("deliveries") or {}
    queued_ids = {
        str(item.get("taskId") or item.get("assignmentId")) for item in state.get("items") or []
    }
    items: list[dict[str, Any]] = []
    for task in tasks:
        task_id = str(task["id"])
        assigned = []
        for delivery in deliveries.get(task_id, []):
            device = devices.get(delivery["deviceId"], {})
            assigned.append(
                {
                    **delivery,
                    "workerId": device.get("workerId"),
                    "platform": device.get("platform"),
                    "deviceTier": device.get("deviceTier"),
                }
            )
        items.append(
            {
                **task,
                "inWorkerQueue": task_id in queued_ids,
                "devices": assigned,
            }
        )
    items.sort(key=lambda item: str(item.get("createdAt") or ""), reverse=True)
    status_counts = Counter(str(item.get("lifecycleStatus") or "unknown") for item in items)
    return {
        "items": items,
        "summary": {
            "total": len(items),
            "byStatus": dict(status_counts),
            "queueDepth": len(queued_ids),
            "running": sum(
                1 for item in items if any(d["state"] == "running" for d in item["devices"])
            ),
            "failedDeliveries": sum(
                1 for item in items for d in item["devices"] if d["state"] == "failed"
            ),
            "pinnedDeviceId": state.get("exclusiveDeviceId"),
        },
    }


async def _get_json(client: httpx.AsyncClient, url: str, source: str) -> dict[str, Any]:
    try:
        response = await client.get(url)
        response.raise_for_status()
        body = response.json()
    except (httpx.HTTPError, ValueError) as exc:
        raise TaskMonitorUnavailable(source) from exc
    if not isinstance(body, dict):
        raise TaskMonitorUnavailable(source)
    return body


async def fetch_dev_sources() -> tuple[list[dict[str, Any]], dict[str, Any]]:
    async with httpx.AsyncClient(timeout=5.0) as client:
        tasks = await _get_json(client, f"{_API_GATEWAY}/internal/dev/tasks", "api-gateway")
        state = await _get_json(client, f"{_WORKER_REGISTRY}/internal/dev/assignments", "worker-registry")
    return list(tasks.get("items") or []), state


def device_ids_in(state: Mapping[str, Any]) -> list[str]:
    deliveries: Mapping[str, list[dict[str, Any]]] = state.get("deliveries") or {}
    return sorted({d["deviceId"] for items in deliveries.values() for d in items})


async def load_devices(connection: AsyncConnection, device_ids: list[str]) -> dict[str, dict[str, Any]]:
    if not device_ids:
        return {}
    result = await connection.execute(_DEVICES_SQL, {"device_ids": device_ids})
    return {
        row["device_public_id"]: {
            "workerId": row["worker_public_id"],
            "platform": row["platform"],
            "deviceTier": row["device_tier"],
        }
        for row in result.mappings()
    }
