from __future__ import annotations

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field


class ModelView(BaseModel):
    id: str
    status: str
    version: int = Field(ge=1)
    updatedAt: datetime


class ReportModelInstallRequest(BaseModel):
    artifactSha256: str = Field(min_length=64, max_length=64)
    status: str = Field(min_length=1)


class OperatorReasonRequest(BaseModel):
    reason: str = Field(min_length=3, max_length=1000)
    ticketId: str = Field(min_length=1)


class StartModelRolloutRequest(BaseModel):
    modelVersionId: str
    targetWorkerTierIds: list[str] = Field(min_length=1)
    initialPercentage: int = Field(ge=0, le=100)
    reason: str = Field(min_length=3)
    ticketId: str = Field(min_length=1)


class CommandReceipt(BaseModel):
    operationId: str
    accepted: bool
    status: str
    occurredAt: datetime
    resourceId: str | None = None
    requestId: str | None = None


class RollbackModelRolloutRequest(BaseModel):
    reason: str = Field(min_length=3, max_length=1000)
    ticketId: str = Field(min_length=1)


class RevokeModelRequest(BaseModel):
    reason: str = Field(min_length=3, max_length=1000)
    ticketId: str = Field(min_length=1)


class ApproveModelRequest(BaseModel):
    reason: str = Field(min_length=3, max_length=1000)
    ticketId: str = Field(min_length=1)


class CreateModelVersionRequest(BaseModel):
    modelPublicId: str
    semanticVersion: str
    artifactUri: str
    artifactSha256: str = Field(min_length=64, max_length=64)
    artifactSizeBytes: int = Field(ge=1)
    signatureUri: str
    licenseSpdx: str
    runtimeAbi: str = "onnxruntime-1.18"
    minimumDeviceTier: Literal["T1", "T2", "T3", "T4"] = "T1"
    peakRamBytes: int = Field(ge=0, default=0)
    minimumFreeStorageBytes: int = Field(ge=0, default=0)
    rollbackVersionPublicId: str | None = None
    benchmarkEvidencePath: str | None = None
    profileName: str | None = None
