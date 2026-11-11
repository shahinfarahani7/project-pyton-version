from __future__ import annotations

from datetime import UTC, datetime, timedelta
from typing import Any

from edgemint.operations.worker_device_overview import (
    device_type_label,
    overview_item_from_row,
    worker_has_current_app,
)

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
        "observed_at_utc": NOW - timedelta(seconds=4),
        "received_at_utc": NOW - timedelta(seconds=4),
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


def test_current_app_matches_published_build_code_before_name() -> None:
    assert worker_has_current_app(
        app_version="5.0.0",
        app_version_code=40200,
        release_name="5.0.1",
        release_code=40200,
    )
    assert not worker_has_current_app(
        app_version="5.0.1",
        app_version_code=40100,
        release_name="5.0.1",
        release_code=40200,
    )
    assert worker_has_current_app(
        app_version="5.0.1",
        app_version_code=None,
        release_name="5.0.1",
        release_code=None,
    )
    assert not worker_has_current_app(
        app_version="5.0.0",
        app_version_code=None,
        release_name="5.0.1",
        release_code=40200,
    )


def test_overview_reads_installed_build_from_heartbeat_telemetry() -> None:
    item = overview_item_from_row(
        _row(telemetry_json={"cpuUsageBps": 4_200, "appVersionCode": 40200}),
        now=NOW,
    )
    assert item["appVersion"] == "1.0.0"
    assert item["appVersionCode"] == 40200


def test_online_worker_with_lease_is_busy_with_specs() -> None:
    item = overview_item_from_row(_row(), now=NOW)
    assert item["presence"] == "online"
    assert item["activity"] == "busy"
    assert item["currentLeaseCount"] == 1
    assert item["cpu"] == {"capacityUnits": 8, "cores": None, "usageBps": 4_200}
    assert item["ram"] == {"totalBytes": 8_000_000_000, "freeBytes": 2_000_000_000}
    assert item["battery"] == {"levelBps": 8_500, "charging": True}
    assert item["device"] == {"name": None, "manufacturer": None, "model": None}


def test_reported_device_identity_and_hardware_are_exposed() -> None:
    capability = {
        "device": {
            "manufacturer": "samsung",
            "model": "SM-S928B",
            "name": "Galaxy S24 Ultra",
            "cpuCoreCount": 8,
            "totalRamBytes": 12_000_000_000,
        },
        "resourceVector": {"cpuUnits": 100},
        "memory": {"totalRamBytes": 8_589_934_592},
    }
    item = overview_item_from_row(_row(heartbeat_capability=capability), now=NOW)
    assert item["device"] == {
        "name": "Galaxy S24 Ultra",
        "manufacturer": "samsung",
        "model": "SM-S928B",
    }
    assert item["cpu"]["cores"] == 8
    assert item["ram"]["totalBytes"] == 12_000_000_000


def test_device_type_label_uses_model_not_nickname() -> None:
    assert device_type_label(
        {"device": {"manufacturer": "samsung", "model": "SM-S928B", "name": "Amirmahdi"}}
    ) == "Samsung SM-S928B"
    assert device_type_label({"device": {"manufacturer": "samsung", "name": "Galaxy S24"}}) == (
        "Samsung Galaxy S24"
    )
    assert device_type_label({"memory": {}}) is None


def test_device_name_falls_back_to_manufacturer_and_model() -> None:
    capability = {"device": {"manufacturer": "samsung", "model": "SM-S928B"}}
    item = overview_item_from_row(_row(heartbeat_capability=capability), now=NOW)
    assert item["device"]["name"] == "Samsung SM-S928B"

    capability = {"device": {"manufacturer": "Google", "model": "Google Pixel 8"}}
    item = overview_item_from_row(_row(heartbeat_capability=capability), now=NOW)
    assert item["device"]["name"] == "Google Pixel 8"


def test_online_worker_without_lease_is_idle() -> None:
    item = overview_item_from_row(_row(current_leases_json=[]), now=NOW)
    assert item["activity"] == "idle"


def test_stale_heartbeat_is_offline_and_activity_unknown() -> None:
    stale = NOW - timedelta(minutes=10)
    item = overview_item_from_row(
        _row(observed_at_utc=stale, received_at_utc=stale),
        now=NOW,
    )
    assert item["presence"] == "offline"
    assert item["activity"] == "unknown"


def test_future_client_clock_does_not_keep_a_silent_phone_online() -> None:
    item = overview_item_from_row(
        _row(
            observed_at_utc=NOW + timedelta(hours=2),
            received_at_utc=NOW - timedelta(seconds=45),
        ),
        now=NOW,
    )
    assert item["presence"] == "offline"
    assert item["activity"] == "unknown"


def test_heartbeat_received_within_the_live_window_stays_online() -> None:
    item = overview_item_from_row(
        _row(received_at_utc=NOW - timedelta(seconds=5)),
        now=NOW,
    )
    assert item["presence"] == "online"


def test_device_without_heartbeat_falls_back_to_registered_capability() -> None:
    item = overview_item_from_row(
        _row(
            observed_at_utc=None,
            received_at_utc=None,
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
    assert item["cpu"] == {"capacityUnits": 4, "cores": None, "usageBps": None}
    assert item["ram"] == {"totalBytes": 4_000, "freeBytes": None}
    assert item["battery"] == {"levelBps": None, "charging": None}
