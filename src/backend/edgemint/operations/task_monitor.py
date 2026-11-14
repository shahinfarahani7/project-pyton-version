from __future__ import annotations

import os
from collections import Counter
from collections.abc import Mapping, Sequence
from typing import Any

import httpx
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncConnection

from edgemint.operations.worker_device_overview import device_type_label

_API_GATEWAY = os.environ.get("EDGEMINT_API_GATEWAY_URL", "http://api-gateway:8080").rstrip("/")
_WORKER_REGISTRY = os.environ.get("EDGEMINT_WORKER_REGISTRY_URL", "http://worker-registry:8080").rstrip("/")

_DEVICES_SQL = text(
    """
    SELECT d.public_id AS device_public_id, w.public_id AS worker_public_id,
           d.platform, d.device_tier,
           d.capability_snapshot_json AS device_capability,
           hb.capability_snapshot_json AS heartbeat_capability
    FROM public.worker_devices d
    JOIN public.workers w ON w.id = d.worker_id
    LEFT JOIN LATERAL (
        SELECT h.capability_snapshot_json
        FROM public.worker_heartbeats h
        WHERE h.worker_device_id = d.id
        ORDER BY h.sequence_number DESC
        LIMIT 1
    ) hb ON TRUE
    WHERE d.public_id = ANY(:device_ids)
    """
)


class TaskMonitorUnavailable(Exception):
    def __init__(self, source: str) -> None:
        super().__init__(source)
        self.source = source


class TaskNotFound(Exception):
    def __init__(self, task_id: str) -> None:
        super().__init__(task_id)
        self.task_id = task_id


def sold_task_atomic(tasks: Sequence[Mapping[str, Any]]) -> int:
    """FibonAI atomic units customers paid on tasks that finished and were kept."""
    total = 0
    for task in tasks:
        if task.get("fibonaiSettlement") != "spent":
            continue
        charge = task.get("fibonaiChargeAtomic")
        if type(charge) is not int or charge < 0:
            continue
        total += charge
    return total


def tokens_given_atomic(task: Mapping[str, Any], credited: int = 0) -> int:
    """FibonAI atomic units paid for one task.

    A recorded worker credit wins. A succeeded task still shows its worker
    reward when that credit row has not been stored.
    """
    if type(credited) is int and credited > 0:
        return credited
    status = str(task.get("lifecycleStatus") or "").lower()
    settled = task.get("fibonaiSettlement") == "spent"
    finished = status in {"succeeded", "completed", "done"} or settled
    reward = task.get("fibonaiWorkerRewardAtomic")
    if finished and type(reward) is int and reward > 0:
        return reward
    if type(credited) is int and credited >= 0:
        return credited
    return 0


def with_tokens_given(monitor: dict[str, Any], credits: Mapping[str, int]) -> dict[str, Any]:
    """Attach the FibonAI atomic units paid for each task."""
    for item in monitor["items"]:
        paid = credits.get(str(item["id"]), 0)
        item["tokensGivenAtomic"] = tokens_given_atomic(item, paid if type(paid) is int else 0)
    return monitor


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
                    "deviceName": device.get("deviceName"),
                }
            )
        item = {
            **task,
            "inWorkerQueue": task_id in queued_ids,
            "devices": assigned,
        }
        item["tokensGivenAtomic"] = tokens_given_atomic(item)
        items.append(item)
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
            "pinnedDeviceName": devices.get(state.get("exclusiveDeviceId"), {}).get("deviceName"),
            "soldAtomic": sold_task_atomic(items),
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


async def cancel_monitored_task(task_id: str) -> dict[str, Any]:
    """Ask api-gateway to cancel the dev task. Assignment state lives in that process."""
    url = f"{_API_GATEWAY}/internal/dev/tasks/{task_id}:cancel"
    try:
        async with httpx.AsyncClient(timeout=5.0) as client:
            response = await client.post(url)
    except httpx.HTTPError as exc:
        raise TaskMonitorUnavailable("api-gateway") from exc
    if response.status_code == 404:
        raise TaskNotFound(task_id)
    if response.status_code >= 400:
        raise TaskMonitorUnavailable("api-gateway")
    try:
        body = response.json()
    except ValueError as exc:
        raise TaskMonitorUnavailable("api-gateway") from exc
    if not isinstance(body, dict):
        raise TaskMonitorUnavailable("api-gateway")
    return body


async def fetch_dev_sources() -> tuple[list[dict[str, Any]], dict[str, Any]]:
    async with httpx.AsyncClient(timeout=5.0) as client:
        tasks = await _get_json(client, f"{_API_GATEWAY}/internal/dev/tasks", "api-gateway")
        state = await _get_json(client, f"{_WORKER_REGISTRY}/internal/dev/assignments", "worker-registry")
    return list(tasks.get("items") or []), state


def _capability(value: Any) -> Mapping[str, Any] | None:
    return value if isinstance(value, Mapping) else None


def device_record_from_row(row: Mapping[str, Any]) -> dict[str, Any]:
    heartbeat = _capability(row.get("heartbeat_capability"))
    registered = _capability(row.get("device_capability"))
    return {
        "workerId": row["worker_public_id"],
        "platform": row["platform"],
        "deviceTier": row["device_tier"],
        "deviceName": device_type_label(heartbeat) or device_type_label(registered),
    }


def device_ids_in(state: Mapping[str, Any]) -> list[str]:
    deliveries: Mapping[str, list[dict[str, Any]]] = state.get("deliveries") or {}
    ids = {d["deviceId"] for items in deliveries.values() for d in items}
    pinned = state.get("exclusiveDeviceId")
    if pinned:
        ids.add(pinned)
    return sorted(ids)


async def load_devices(connection: AsyncConnection, device_ids: list[str]) -> dict[str, dict[str, Any]]:
    if not device_ids:
        return {}
    result = await connection.execute(_DEVICES_SQL, {"device_ids": device_ids})
    return {row["device_public_id"]: device_record_from_row(row) for row in result.mappings()}
