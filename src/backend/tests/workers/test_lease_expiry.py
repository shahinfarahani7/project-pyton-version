from datetime import UTC, datetime, timedelta

from edgemint.workers.lease_expiry import plan_lease_expiry
from edgemint.workers.schemas import HeartbeatRequest


def test_elapsed_running_lease_is_released_and_terminal_rows_stay() -> None:
    now = datetime(2026, 11, 15, tzinfo=UTC)
    assert (
        plan_lease_expiry(
            assignment_status="running",
            lease_expires_at=now - timedelta(seconds=1),
            now=now,
        )
        == "expire_and_release"
    )
    assert (
        plan_lease_expiry(
            assignment_status="leased",
            lease_expires_at=now - timedelta(minutes=5),
            now=now,
        )
        == "expire_and_release"
    )
    for status in ("completed", "failed", "expired", "revoked", "stale", "cancelled"):
        assert (
            plan_lease_expiry(
                assignment_status=status,
                lease_expires_at=now - timedelta(minutes=5),
                now=now,
            )
            == "leave"
        )
    assert (
        plan_lease_expiry(
            assignment_status="running",
            lease_expires_at=now + timedelta(minutes=1),
            now=now,
        )
        == "leave"
    )


def test_heartbeat_accepts_measured_ram_and_unknown_ram() -> None:
    measured = HeartbeatRequest.model_validate(
        {
            "sequence": 1,
            "observedAt": "2026-11-15T08:00:00Z",
            "batteryBps": 5000,
            "charging": False,
            "thermalState": "nominal",
            "freeRamBytes": 900 * 1024 * 1024,
            "freeStorageBytes": 1000,
            "network": "wifi",
            "memoryAttribution": "measured",
            "totalRamBytes": 3700 * 1024 * 1024,
        }
    )
    assert measured.freeRamBytes == 900 * 1024 * 1024
    assert measured.memoryAttribution == "measured"

    unknown = HeartbeatRequest.model_validate(
        {
            "sequence": 2,
            "observedAt": "2026-11-15T08:00:00Z",
            "batteryBps": 5000,
            "charging": False,
            "thermalState": "nominal",
            "freeStorageBytes": 1000,
            "network": "wifi",
            "memoryAttribution": "unknown",
        }
    )
    assert unknown.freeRamBytes is None
    assert unknown.memoryAttribution == "unknown"
