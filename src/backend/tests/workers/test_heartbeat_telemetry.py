from __future__ import annotations

from datetime import UTC, datetime

from edgemint.workers.heartbeat_telemetry import (
    WorkerCalibrationView,
    WorkerConsentSnapshot,
    WorkerHeartbeatTelemetry,
    WorkerResourceReservationEntry,
    WorkerResourceReservationTotals,
    WorkerResourceReservationsView,
    telemetry_from_heartbeat,
    telemetry_json_from_heartbeat,
)
from edgemint.workers.schemas import HeartbeatRequest


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


def test_heartbeat_accepts_section39_telemetry_fields() -> None:
    heartbeat = HeartbeatRequest.model_validate(
        {
            "sequence": 2,
            "observedAt": datetime.now(UTC),
            "batteryBps": 7800,
            "charging": True,
            "thermalState": "nominal",
            "freeRamBytes": 3221225472,
            "freeStorageBytes": 21474836480,
            "network": "wifi",
            "currentLeases": ["asg-1"],
            "installedModels": [
                {"modelVersionId": "mdv_qwen2_5_0_5b", "artifactSha256": "abc123"},
            ],
            "capabilitySnapshot": _reference_capability(),
            "cpuUsageBps": 2100,
            "loadedModelIds": ["mdv_qwen2_5_0_5b"],
            "runtimeSessions": {"mediapipe_llm": 1, "paddle_ocr": 0},
            "consentSnapshot": {
                "grantedConsents": ["terms", "privacy", "resource_use", "reward_disclosure"],
                "contributionModeId": "balanced",
            },
            "calibrationView": {
                "profileVersion": 1,
                "suiteVersion": "android-arm64-t4-baseline-v1",
                "measuredAt": "2026-09-01T10:00:00Z",
            },
            "resourceReservationsView": {
                "active": [
                    {
                        "assignmentId": "asg-1",
                        "runtimeClass": "mediapipe_llm",
                        "cpuUnits": 40,
                        "memoryBytes": 1610612736,
                        "storageBytes": 0,
                    }
                ],
                "totals": {
                    "cpuUnits": 40,
                    "memoryBytes": 1610612736,
                    "storageBytes": 0,
                },
            },
        }
    )

    telemetry = telemetry_from_heartbeat(heartbeat)
    assert telemetry is not None
    assert telemetry.cpuUsageBps == 2100
    assert telemetry.loadedModelIds == ["mdv_qwen2_5_0_5b"]
    assert telemetry.runtimeSessions["mediapipe_llm"] == 1
    assert telemetry.consentSnapshot is not None
    assert telemetry.consentSnapshot.contributionModeId == "balanced"
    assert telemetry.calibrationView is not None
    assert telemetry.calibrationView.profileVersion == 1
    assert telemetry.resourceReservationsView is not None
    assert telemetry.resourceReservationsView.totals.cpuUnits == 40


def test_telemetry_json_omits_empty_extensions() -> None:
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
        }
    )
    assert telemetry_json_from_heartbeat(heartbeat) is None


def test_worker_heartbeat_telemetry_model_round_trip() -> None:
    payload = WorkerHeartbeatTelemetry(
        cpuUsageBps=1500,
        loadedModelIds=["mdv_qwen2_5_0_5b"],
        runtimeSessions={"paddle_ocr": 1},
        consentSnapshot=WorkerConsentSnapshot(
            grantedConsents=["terms"],
            contributionModeId="performance",
        ),
        calibrationView=WorkerCalibrationView(
            profileVersion=2,
            suiteVersion="suite-v2",
            measuredAt=datetime(2026, 9, 1, 10, tzinfo=UTC),
        ),
        resourceReservationsView=WorkerResourceReservationsView(
            active=[
                WorkerResourceReservationEntry(
                    assignmentId="asg-9",
                    runtimeClass="paddle_ocr",
                    cpuUnits=25,
                    memoryBytes=536870912,
                    storageBytes=0,
                )
            ],
            totals=WorkerResourceReservationTotals(
                cpuUnits=25,
                memoryBytes=536870912,
                storageBytes=0,
            ),
        ),
    )
    dumped = payload.model_dump(mode="json", exclude_none=True)
    restored = WorkerHeartbeatTelemetry.model_validate(dumped)
    assert restored.cpuUsageBps == 1500
    assert restored.resourceReservationsView is not None
    assert restored.resourceReservationsView.active[0].assignmentId == "asg-9"


def test_heartbeat_accepts_identity_lifecycle_view_from_worker() -> None:
    heartbeat = HeartbeatRequest.model_validate(
        {
            "sequence": 3,
            "observedAt": datetime.now(UTC),
            "batteryBps": 7800,
            "charging": True,
            "thermalState": "nominal",
            "freeRamBytes": 8589934592,
            "freeStorageBytes": 21474836480,
            "network": "wifi",
            "identityLifecycleView": {
                "eventSequence": 2,
                "bootstrapInFlight": False,
                "runtimeGeneration": 1,
                "nativeHandlesInvalidated": False,
                "idleChurnDetected": False,
                "nativeHandleCounters": {
                    "modelCreate": 1,
                    "modelClose": 0,
                    "sessionCreate": 1,
                    "sessionClose": 1,
                    "identityClear": 0,
                },
                "recentMutations": [
                    {
                        "sequence": 1,
                        "kind": "verifyActive",
                        "caller": "WorkerModelInstaller.verifyActive",
                        "before": {"hasActiveModel": False},
                        "after": {"hasActiveModel": True},
                        "observedAt": "2026-09-06T10:00:00Z",
                    }
                ],
            },
        }
    )

    telemetry = telemetry_from_heartbeat(heartbeat)
    assert telemetry is not None
    assert telemetry.identityLifecycleView is not None
    assert telemetry.identityLifecycleView["recentMutations"][0]["before"] == {"hasActiveModel": False}
