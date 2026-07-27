from __future__ import annotations

from datetime import datetime
from typing import Any, Literal
from uuid import UUID

from pydantic import BaseModel, Field


class TaskConfiguration(BaseModel):
    outputFormat: str | None = None
    verificationLevel: str = "standard"
    priority: str = "standard"
    regionPolicy: str = "any_allowed"
    retentionDays: int = 0
    language: list[str] | None = None
    parameters: dict[str, Any] = Field(default_factory=dict)


class TaskInput(BaseModel):
    fileId: str | None = None
    contentType: str | None = None
    inlineText: str | None = None


class CreateTaskRequest(BaseModel):
    workspaceId: UUID
    taskType: Literal["document-ocr", "document-extract", "audio-transcribe"]
    input: TaskInput
    configuration: TaskConfiguration
    metadata: dict[str, str] = Field(default_factory=dict)
    webhookEndpointId: str | None = None
    quoteId: str | None = None


class CreateRevisionRequest(BaseModel):
    changeReason: str = Field(min_length=3, max_length=1000)
    input: TaskInput
    configuration: TaskConfiguration


class TaskResponse(BaseModel):
    id: str
    workspaceId: str
    taskType: str
    currentRevisionId: str
    createdAt: datetime
    version: int = Field(ge=1)
    lifecycleStatus: str
    executionStatus: str
    billingStatus: str
