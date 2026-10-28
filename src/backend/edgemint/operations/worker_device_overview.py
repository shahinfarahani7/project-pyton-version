from __future__ import annotations

from collections.abc import Mapping
from datetime import UTC, datetime, timedelta
from typing import Any

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncConnection

HEARTBEAT_STALE_AFTER = timedelta(minutes=2)

# Busy state is derived from the worker-reported lease list because public.assignments is
# workspace-scoped (FORCE ROW LEVEL SECURITY) and this operator view is cross-workspace.
_OVERVIEW_SQL = text(
    """
    SELECT
        d.public_id AS device_public_id,
        w.public_id AS worker_public_id,
        w.status AS worker_status,
        d.status AS device_status,
        d.platform,
        d.device_tier,
        d.app_version,
        d.last_seen_at_utc,
        d.capability_snapshot_json AS device_capability,
        hb.observed_at_utc,
        hb.battery_bps,
        hb.charging,
        hb.thermal_state,
        hb.free_ram_bytes,
        hb.network_type,
        hb.current_leases_json,
        hb.capability_snapshot_json AS heartbeat_capability,
        hb.telemetry_json
    FROM public.worker_devices d
    JOIN public.workers w ON w.id = d.worker_id
    LEFT JOIN LATERAL (
        SELECT *
        FROM public.worker_heartbeats h
        WHERE h.worker_device_id = d.id
        ORDER BY h.sequence_number DESC
        LIMIT 1
    ) hb ON TRUE
    ORDER BY d.last_seen_at_utc DESC NULLS LAST, d.public_id
    """
)


def _int_or_none(value: Any) -> int | None:
    return value if isinstance(value, int) and not isinstance(value, bool) else None


def overview_item_from_row(row: Mapping[str, Any], *, now: datetime) -> dict[str, Any]:
    capability = row.get("heartbeat_capability") or row.get("device_capability") or {}
    resource_vector = capability.get("resourceVector") or {}
    memory = capability.get("memory") or {}
    telemetry = row.get("telemetry_json") or {}
    leases = row.get("current_leases_json") or []
    observed_at: datetime | None = row.get("observed_at_utc")

    if observed_at is None:
        presence = "never_seen"
    elif now - observed_at > HEARTBEAT_STALE_AFTER:
        presence = "offline"
    else:
        presence = "online"

    if presence != "online":
        activity = "unknown"
    else:
        activity = "busy" if leases else "idle"

    return {
        "id": row["device_public_id"],
        "workerId": row["worker_public_id"],
        "status": row["device_status"],
        "workerStatus": row["worker_status"],
        "platform": row["platform"],
        "deviceTier": row["device_tier"],
        "appVersion": row["app_version"],
        "presence": presence,
        "activity": activity,
        "currentLeaseCount": len(leases),
        "lastHeartbeatAt": observed_at.isoformat() if observed_at else None,
        "cpu": {
            "capacityUnits": _int_or_none(resource_vector.get("cpuUnits")),
            "usageBps": _int_or_none(telemetry.get("cpuUsageBps")),
        },
        "ram": {
            "totalBytes": _int_or_none(memory.get("totalRamBytes")),
            "freeBytes": _int_or_none(row.get("free_ram_bytes")),
        },
        "battery": {
            "levelBps": _int_or_none(row.get("battery_bps")),
            "charging": row.get("charging"),
        },
        "thermalState": row.get("thermal_state"),
        "network": row.get("network_type"),
    }


async def list_worker_device_overview(
    connection: AsyncConnection, *, now: datetime | None = None
) -> list[dict[str, Any]]:
    current = now or datetime.now(UTC)
    result = await connection.execute(_OVERVIEW_SQL)
    return [overview_item_from_row(dict(row), now=current) for row in result.mappings()]
