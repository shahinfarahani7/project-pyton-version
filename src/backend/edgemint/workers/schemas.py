from __future__ import annotations

from datetime import datetime
from typing import Any, Literal

from pydantic import BaseModel, Field

from edgemint.workers.device_capability import DeviceCapabilityReport
from edgemint.workers.heartbeat_telemetry import (
    WorkerCalibrationView,
    WorkerConsentSnapshot,
    WorkerResourceReservationEntry,
    WorkerResourceReservationTotals,
    WorkerResourceReservationsView,
)
from edgemint.workers.identity_native_lifecycle import WorkerIdentityLifecycleView


class CreateChallengeRequest(BaseModel):
    installationId: str = Field(min_length=1, max_length=128)


class CreateChallengeResponse(BaseModel):
    challengeId: str
    nonce: str
    expiresAt: datetime


class DeviceRegistrationRequest(BaseModel):
    installationId: str = Field(min_length=1, max_length=128)
    platform: Literal["android", "ios", "linux_edge"]
    appVersion: str = Field(min_length=1, max_length=32)
    capabilities: DeviceCapabilityReport
    attestation: dict[str, Any]
    publicKey: str | None = None


class RegisterWorkerDeviceResponse(BaseModel):
    workerId: str
    deviceId: str
    accessToken: str
    expiresAt: datetime


class RefreshSessionRequest(BaseModel):
    refreshToken: str = Field(min_length=1)


class RefreshWorkerSessionResponse(BaseModel):
    workerId: str
    deviceId: str
    accessToken: str
    expiresAt: datetime


class BenchmarkMetric(BaseModel):
    metric: str
    value: float
    unit: str


class SubmitBenchmarkRequest(BaseModel):
    suiteVersion: str
    measuredAt: datetime
    results: list[BenchmarkMetric] = Field(min_length=1)
    signature: str = Field(min_length=1)


class HeartbeatRequest(BaseModel):
    sequence: int = Field(ge=1)
    observedAt: datetime
    batteryBps: int = Field(ge=0, le=10_000)
    charging: bool
    thermalState: Literal["nominal", "fair", "serious", "critical"]
    freeRamBytes: int = Field(ge=0)
    freeStorageBytes: int = Field(ge=0)
    network: Literal["offline", "cellular", "wifi", "ethernet"]
    currentLeases: list[str] = Field(default_factory=list)
    installedModels: list[dict[str, str]] = Field(default_factory=list)
    capabilitySnapshot: DeviceCapabilityReport | None = None
    cpuUsageBps: int | None = Field(default=None, ge=0, le=10_000)
    loadedModelIds: list[str] = Field(default_factory=list)
    runtimeSessions: dict[str, int] = Field(default_factory=dict)
    consentSnapshot: WorkerConsentSnapshot | None = None
    calibrationView: WorkerCalibrationView | None = None
    resourceReservationsView: WorkerResourceReservationsView | None = None
    identityLifecycleView: WorkerIdentityLifecycleView | None = None


class WorkerScheduleWindow(BaseModel):
    days: list[Literal["MO", "TU", "WE", "TH", "FR", "SA", "SU"]] = Field(min_length=1)
    startLocal: str
    endLocal: str


class WorkerSchedule(BaseModel):
    mode: Literal["always", "charging_window", "custom"]
    timezone: str = Field(min_length=1)
    windows: list[WorkerScheduleWindow] = Field(default_factory=list)


class WorkerPreferencesView(BaseModel):
    version: int = Field(ge=1)
    availability: Literal["available", "unavailable"]
    networkPolicy: Literal["wifi_only", "unmetered_only", "wifi_or_ethernet", "any_online"]
    chargingPolicy: Literal["required", "preferred", "not_required"]
    minimumBatteryPercent: int = Field(ge=25, le=100)
    contributionModeId: str = Field(min_length=1)
    schedule: WorkerSchedule


class ReplaceWorkerPreferencesRequest(BaseModel):
    expectedVersion: int = Field(ge=1)
    availability: Literal["available", "unavailable"]
    networkPolicy: Literal["wifi_only", "unmetered_only", "wifi_or_ethernet", "any_online"]
    chargingPolicy: Literal["required", "preferred", "not_required"]
    minimumBatteryPercent: int = Field(ge=25, le=100)
    contributionModeId: str = Field(min_length=1)
    schedule: WorkerSchedule
    performanceOptInConfirmed: bool = False


class CommandReceipt(BaseModel):
    operationId: str
    accepted: bool
    status: str
    occurredAt: datetime
    resourceId: str | None = None
    requestId: str | None = None
