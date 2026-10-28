from __future__ import annotations

from datetime import UTC, datetime, timedelta
from typing import Any

from edgemint.operations.worker_device_overview import overview_item_from_row

NOW = datetime(2026, 10, 28, 10, 0, tzinfo=UTC)


def _row(**overrides: Any) -> dict[str, Any]:
    row: dict[str, Any] = {
        "device_public_id": "dev_1",
        "worker_public_id": "wrk_1",
        "worker_status": "active",
        "device_status": "active",
        "platform": "android",
        "device_tier": "T2",
        "app_version": "1.0.0",
        "last_seen_at_utc": NOW,
        "device_capability": None,
        "observed_at_utc": NOW - timedelta(seconds=30),
        "battery_bps": 8_500,
        "charging": True,
        "thermal_state": "nominal",
        "free_ram_bytes": 2_000_000_000,
        "network_type": "wifi",
        "current_leases_json": ["asg_1"],
        "heartbeat_capability": {
            "resourceVector": {"cpuUnits": 8},
            "memory": {"totalRamBytes": 8_000_000_000},
        },
        "telemetry_json": {"cpuUsageBps": 4_200},
    }
    row.update(overrides)
    return row


def test_online_worker_with_lease_is_busy_with_specs() -> None:
    item = overview_item_from_row(_row(), now=NOW)
    assert item["presence"] == "online"
    assert item["activity"] == "busy"
    assert item["currentLeaseCount"] == 1
    assert item["cpu"] == {"capacityUnits": 8, "usageBps": 4_200}
    assert item["ram"] == {"totalBytes": 8_000_000_000, "freeBytes": 2_000_000_000}
    assert item["battery"] == {"levelBps": 8_500, "charging": True}


def test_online_worker_without_lease_is_idle() -> None:
    item = overview_item_from_row(_row(current_leases_json=[]), now=NOW)
    assert item["activity"] == "idle"


def test_stale_heartbeat_is_offline_and_activity_unknown() -> None:
    item = overview_item_from_row(_row(observed_at_utc=NOW - timedelta(minutes=10)), now=NOW)
    assert item["presence"] == "offline"
    assert item["activity"] == "unknown"


def test_device_without_heartbeat_falls_back_to_registered_capability() -> None:
    item = overview_item_from_row(
        _row(
            observed_at_utc=None,
            battery_bps=None,
            charging=None,
            free_ram_bytes=None,
            current_leases_json=None,
            heartbeat_capability=None,
            telemetry_json=None,
            device_capability={"resourceVector": {"cpuUnits": 4}, "memory": {"totalRamBytes": 4_000}},
        ),
        now=NOW,
    )
    assert item["presence"] == "never_seen"
    assert item["activity"] == "unknown"
    assert item["cpu"] == {"capacityUnits": 4, "usageBps": None}
    assert item["ram"] == {"totalBytes": 4_000, "freeBytes": None}
    assert item["battery"] == {"levelBps": None, "charging": None}
