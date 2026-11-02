"""In-process per-API-key usage counters for the dev portal (lost on restart)."""

from __future__ import annotations

from collections import deque
from dataclasses import dataclass, field
from datetime import UTC, datetime, timedelta
from threading import Lock
from typing import Any
from uuid import UUID

_MAX_EVENTS = 200_000
_RANGES: dict[str, tuple[timedelta, timedelta]] = {
    "day": (timedelta(days=1), timedelta(hours=1)),
    "week": (timedelta(days=7), timedelta(days=1)),
    "month": (timedelta(days=30), timedelta(days=1)),
    "6m": (timedelta(days=182), timedelta(days=7)),
}


@dataclass(frozen=True, slots=True)
class UsageEvent:
    key_id: str
    workspace_id: UUID
    at: datetime
    kind: str
    ok: bool
    client_ip: str | None


@dataclass
class ApiKeyUsage:
    _events: deque[UsageEvent] = field(default_factory=lambda: deque(maxlen=_MAX_EVENTS))
    _lock: Lock = field(default_factory=Lock)

    def record(
        self,
        key_id: str,
        workspace_id: UUID,
        *,
        kind: str,
        ok: bool,
        client_ip: str | None,
        at: datetime | None = None,
    ) -> None:
        event = UsageEvent(key_id, workspace_id, at or datetime.now(UTC), kind, ok, client_ip)
        with self._lock:
            self._events.append(event)

    def summary(self, workspace_id: UUID, range_name: str, *, now: datetime | None = None) -> dict[str, Any]:
        if range_name not in _RANGES:
            raise ValueError("USAGE_RANGE_INVALID")
        span, step = _RANGES[range_name]
        end = now or datetime.now(UTC)
        start = end - span
        bucket_count = int(span / step)
        buckets = [start + step * index for index in range(bucket_count)]
        with self._lock:
            events = [event for event in self._events if event.workspace_id == workspace_id]
        keys: dict[str, dict[str, Any]] = {}
        for event in events:
            item = keys.setdefault(
                event.key_id,
                {
                    "keyId": event.key_id,
                    "totalRequests": 0,
                    "totalTasks": 0,
                    "rangeRequests": 0,
                    "rangeTasks": 0,
                    "rangeErrors": 0,
                    "lastUsedAt": None,
                    "lastIp": None,
                    "series": [0] * bucket_count,
                },
            )
            item["totalRequests"] += 1
            if event.kind == "task" and event.ok:
                item["totalTasks"] += 1
            if item["lastUsedAt"] is None or event.at.isoformat() > item["lastUsedAt"]:
                item["lastUsedAt"] = event.at.isoformat()
                item["lastIp"] = event.client_ip
            if start <= event.at < end:
                item["rangeRequests"] += 1
                if event.kind == "task" and event.ok:
                    item["rangeTasks"] += 1
                if not event.ok:
                    item["rangeErrors"] += 1
                item["series"][min(int((event.at - start) / step), bucket_count - 1)] += 1
        return {
            "range": range_name,
            "buckets": [bucket.isoformat() for bucket in buckets],
            "items": list(keys.values()),
        }

    def forget_workspace(self, workspace_id: UUID) -> None:
        with self._lock:
            kept = [event for event in self._events if event.workspace_id != workspace_id]
            self._events.clear()
            self._events.extend(kept)


usage = ApiKeyUsage()
