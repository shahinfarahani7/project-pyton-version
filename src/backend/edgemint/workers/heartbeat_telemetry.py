from __future__ import annotations

from datetime import datetime
from typing import TYPE_CHECKING, Any

from pydantic import BaseModel, Field

if TYPE_CHECKING:
    from edgemint.workers.schemas import HeartbeatRequest


class WorkerConsentSnapshot(BaseModel):
    grantedConsents: list[str] = Field(default_factory=list)
    contributionModeId: str | None = None

    model_config = {"extra": "forbid"}


class WorkerCalibrationView(BaseModel):
    profileVersion: int = Field(ge=1)
    suiteVersion: str = Field(min_length=1)
    measuredAt: datetime | None = None

    model_config = {"extra": "forbid"}


class WorkerResourceReservationEntry(BaseModel):
    assignmentId: str = Field(min_length=1)
    runtimeClass: str = Field(min_length=1)
    cpuUnits: int = Field(ge=0)
    memoryBytes: int = Field(ge=0)
    storageBytes: int = Field(ge=0)

    model_config = {"extra": "forbid"}


class WorkerResourceReservationTotals(BaseModel):
    cpuUnits: int = Field(ge=0)
    memoryBytes: int = Field(ge=0)
    storageBytes: int = Field(ge=0)

    model_config = {"extra": "forbid"}


class WorkerResourceReservationsView(BaseModel):
    active: list[WorkerResourceReservationEntry] = Field(default_factory=list)
    totals: WorkerResourceReservationTotals

    model_config = {"extra": "forbid"}


class WorkerHeartbeatTelemetry(BaseModel):
    cpuUsageBps: int | None = Field(default=None, ge=0, le=10_000)
    loadedModelIds: list[str] = Field(default_factory=list)
    runtimeSessions: dict[str, int] = Field(default_factory=dict)
    consentSnapshot: WorkerConsentSnapshot | None = None
    calibrationView: WorkerCalibrationView | None = None
    resourceReservationsView: WorkerResourceReservationsView | None = None
    identityLifecycleView: dict[str, Any] | None = None

    model_config = {"extra": "forbid"}


def telemetry_from_heartbeat(payload: HeartbeatRequest) -> WorkerHeartbeatTelemetry | None:
    identity_view = None
    if payload.identityLifecycleView is not None:
        identity_view = payload.identityLifecycleView.model_dump(mode="json")
    telemetry = WorkerHeartbeatTelemetry(
        cpuUsageBps=payload.cpuUsageBps,
        loadedModelIds=list(payload.loadedModelIds),
        runtimeSessions=dict(payload.runtimeSessions),
        consentSnapshot=payload.consentSnapshot,
        calibrationView=payload.calibrationView,
        resourceReservationsView=payload.resourceReservationsView,
        identityLifecycleView=identity_view,
    )
    if telemetry.model_dump(exclude_none=True, exclude_defaults=True):
        return telemetry
    return None


def telemetry_json_from_heartbeat(payload: HeartbeatRequest) -> dict[str, Any] | None:
    telemetry = telemetry_from_heartbeat(payload)
    if telemetry is None:
        return None
    return telemetry.model_dump(mode="json", exclude_none=True)
