from __future__ import annotations

import asyncio
import json
from collections import defaultdict
from typing import Any
from uuid import UUID

_subscribers: dict[UUID, set[asyncio.Queue[str]]] = defaultdict(set)
_lock = asyncio.Lock()


async def subscribe(workspace_id: UUID) -> asyncio.Queue[str]:
    queue: asyncio.Queue[str] = asyncio.Queue(maxsize=32)
    async with _lock:
        _subscribers[workspace_id].add(queue)
    return queue


async def unsubscribe(workspace_id: UUID, queue: asyncio.Queue[str]) -> None:
    async with _lock:
        _subscribers[workspace_id].discard(queue)
        if not _subscribers[workspace_id]:
            _subscribers.pop(workspace_id, None)


def publish_task_event(
    workspace_id: UUID,
    *,
    event: str,
    task_id: str,
    task: dict[str, Any] | None = None,
) -> None:
    payload = json.dumps({"event": event, "taskId": task_id, "task": task})
    for queue in list(_subscribers.get(workspace_id, ())):
        try:
            queue.put_nowait(payload)
        except asyncio.QueueFull:
            pass
