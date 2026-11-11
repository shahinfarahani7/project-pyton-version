from __future__ import annotations

from collections.abc import Mapping
from datetime import UTC, datetime, timedelta
from typing import Any

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncConnection

# Live workers report every 5s. 30s still covers one beat from the previous
# 20s assignment loop, then a silent phone is offline. Receipt time is the
# server clock, so a future phone clock cannot keep the row online.
HEARTBEAT_STALE_AFTER = timedelta(seconds=30)

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
        hb.received_at_utc,
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


def _text_or_none(value: Any) -> str | None:
    return value.strip() or None if isinstance(value, str) else None


def _pretty_manufacturer(manufacturer: str) -> str:
    return f"{manufacturer[:1].upper()}{manufacturer[1:]}"


def _device_identity(device: Mapping[str, Any]) -> dict[str, Any]:
    manufacturer = _text_or_none(device.get("manufacturer"))
    model = _text_or_none(device.get("model"))
    name = _text_or_none(device.get("name"))
    if name is None and model is not None:
        if manufacturer and not model.lower().startswith(manufacturer.lower()):
            name = f"{_pretty_manufacturer(manufacturer)} {model}"
        else:
            name = model
    return {"name": name, "manufacturer": manufacturer, "model": model}


def device_type_label(capability: Mapping[str, Any] | None) -> str | None:
    """Hardware type such as 'Samsung SM-S928B'. A settings nickname is only a fallback."""
    if not isinstance(capability, Mapping):
        return None
    device = capability.get("device")
    if not isinstance(device, Mapping):
        return None
    manufacturer = _text_or_none(device.get("manufacturer"))
    model = _text_or_none(device.get("model"))
    reported_name = _text_or_none(device.get("name"))
    product = model or reported_name
    if product is None:
        return None
    if manufacturer and not product.casefold().startswith(manufacturer.casefold()):
        return f"{_pretty_manufacturer(manufacturer)} {product}"
    return product


def _as_utc(value: datetime) -> datetime:
    if value.tzinfo is None:
        return value.replace(tzinfo=UTC)
    return value.astimezone(UTC)


def _last_contact(row: Mapping[str, Any]) -> datetime | None:
    """Server receipt time wins. Client observedAt is only a fallback."""
    received = row.get("received_at_utc")
    if isinstance(received, datetime):
        return _as_utc(received)
    observed = row.get("observed_at_utc")
    if isinstance(observed, datetime):
        return _as_utc(observed)
    return None


def worker_has_current_app(
    *,
    app_version: str | None,
    app_version_code: int | None,
    release_name: str | None,
    release_code: int | None,
) -> bool:
    """A worker is updated when the installed build matches the published release."""
    if type(app_version_code) is int and type(release_code) is int:
        return app_version_code >= release_code
    installed = app_version.strip() if isinstance(app_version, str) else ""
    published = release_name.strip() if isinstance(release_name, str) else ""
    return bool(installed) and installed == published


def overview_item_from_row(row: Mapping[str, Any], *, now: datetime) -> dict[str, Any]:
    capability = row.get("heartbeat_capability") or row.get("device_capability") or {}
    resource_vector = capability.get("resourceVector") or {}
    memory = capability.get("memory") or {}
    device = capability.get("device") or {}
    telemetry = row.get("telemetry_json") or {}
    leases = row.get("current_leases_json") or []
    current = _as_utc(now)
    last_contact = _last_contact(row)

    if last_contact is None:
        presence = "never_seen"
    elif current - last_contact > HEARTBEAT_STALE_AFTER:
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
        "appVersionCode": _int_or_none(telemetry.get("appVersionCode")),
        "device": _device_identity(device),
        "presence": presence,
        "activity": activity,
        "currentLeaseCount": len(leases),
        "lastHeartbeatAt": last_contact.isoformat() if last_contact else None,
        "cpu": {
            "capacityUnits": _int_or_none(resource_vector.get("cpuUnits")),
            "cores": _int_or_none(device.get("cpuCoreCount")),
            "usageBps": _int_or_none(telemetry.get("cpuUsageBps")),
        },
        "ram": {
            "totalBytes": _int_or_none(device.get("totalRamBytes"))
            or _int_or_none(memory.get("totalRamBytes")),
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
