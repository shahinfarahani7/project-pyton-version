from __future__ import annotations

import pytest
from pydantic import ValidationError

from edgemint.workers.device_capability import DeviceCapabilityReport
from edgemint.workers.schemas import DeviceRegistrationRequest, HeartbeatRequest


def _reference_capability() -> dict[str, object]:
    return {
        "platform": {"os": "android", "abi": "arm64-v8a", "apiLevel": 34, "pageSizeKb": 16},
        "deviceTier": "T4",
        "regionCode": "US",
        "runtimeAbi": "mediapipe-llm-v1",
        "resourceVector": {
            "cpuUnits": 100,
            "memoryBytes": 12884901888,
            "storageBytes": 21474836480,
            "acceleratorUnits": 0,
            "modelSessionUnits": 2,
        },
        "runtimeClasses": ["mediapipe_llm", "paddle_ocr"],
        "storage": {
            "availableBytes": 21474836480,
            "minimumFreeBytes": 1073741824,
            "maxAiStorageBytes": 5368709120,
        },
        "memory": {
            "totalRamBytes": 12884901888,
            "availableBytes": 8589934592,
            "safetyReserveBytes": 536870912,
        },
        "thermal": {"state": "nominal"},
        "battery": {"levelBps": 7800, "charging": True},
        "network": {"type": "wifi"},
    }


def test_device_capability_report_matches_reference_fixture() -> None:
    report = DeviceCapabilityReport.model_validate(_reference_capability())
    assert report.deviceTier == "T4"
    assert "mediapipe_llm" in report.runtimeClasses


def test_device_capability_report_rejects_invalid_tier() -> None:
    payload = _reference_capability()
    payload["deviceTier"] = "D"
    with pytest.raises(ValidationError):
        DeviceCapabilityReport.model_validate(payload)


def test_registration_request_requires_structured_capabilities() -> None:
    request = DeviceRegistrationRequest.model_validate(
        {
            "installationId": "install-1",
            "platform": "android",
            "appVersion": "5.0.0",
            "capabilities": _reference_capability(),
            "attestation": {"nonce": "abc"},
        }
    )
    assert request.capabilities.runtimeAbi == "mediapipe-llm-v1"


def test_registration_request_rejects_empty_capabilities() -> None:
    with pytest.raises(ValidationError):
        DeviceRegistrationRequest.model_validate(
            {
                "installationId": "install-1",
                "platform": "android",
                "appVersion": "5.0.0",
                "capabilities": {},
                "attestation": {"nonce": "abc"},
            }
        )


def test_heartbeat_accepts_optional_capability_snapshot() -> None:
    from datetime import UTC, datetime

    heartbeat = HeartbeatRequest.model_validate(
        {
            "sequence": 1,
            "observedAt": datetime.now(UTC),
            "batteryBps": 7800,
            "charging": True,
            "thermalState": "nominal",
            "freeRamBytes": 8589934592,
            "freeStorageBytes": 21474836480,
            "network": "wifi",
            "currentLeases": [],
            "installedModels": [],
            "capabilitySnapshot": _reference_capability(),
        }
    )
    assert heartbeat.capabilitySnapshot is not None
    assert heartbeat.capabilitySnapshot.deviceTier == "T4"
