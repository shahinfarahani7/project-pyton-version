from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, Field


class PlatformSpec(BaseModel):
    os: Literal["android", "ios", "linux_edge"]
    abi: str = Field(min_length=1)
    apiLevel: int | None = Field(default=None, ge=1)
    pageSizeKb: Literal[4, 16] | None = None


class ResourceVector(BaseModel):
    cpuUnits: int = Field(ge=1)
    memoryBytes: int | None = Field(default=None, ge=0)
    storageBytes: int = Field(ge=0)
    acceleratorUnits: int = Field(ge=0)
    modelSessionUnits: int = Field(ge=0)


class StorageSpec(BaseModel):
    availableBytes: int = Field(ge=0)
    minimumFreeBytes: int = Field(ge=0)
    maxAiStorageBytes: int = Field(ge=0)


class MemorySpec(BaseModel):
    totalRamBytes: int | None = Field(default=None, ge=0)
    availableBytes: int | None = Field(default=None, ge=0)
    safetyReserveBytes: int = Field(ge=0)
    attribution: Literal["measured", "unknown"] = "unknown"
    memoryBudgetBytes: int | None = Field(default=None, ge=0)
    processPssBytes: int | None = Field(default=None, ge=0)


class ThermalSpec(BaseModel):
    state: Literal["nominal", "fair", "serious", "critical"]


class BatterySpec(BaseModel):
    levelBps: int = Field(ge=0, le=10_000)
    charging: bool


class NetworkSpec(BaseModel):
    type: Literal["offline", "cellular", "wifi", "ethernet"]


class DeviceIdentitySpec(BaseModel):
    manufacturer: str | None = Field(default=None, min_length=1, max_length=64)
    model: str | None = Field(default=None, min_length=1, max_length=64)
    name: str | None = Field(default=None, min_length=1, max_length=128)
    cpuCoreCount: int | None = Field(default=None, ge=1)
    totalRamBytes: int | None = Field(default=None, ge=1)

    model_config = {"extra": "forbid"}


class DeviceCapabilityReport(BaseModel):
    """Worker-reported snapshot aligned with dsl/schemas/devicecapability.schema.json spec."""

    device: DeviceIdentitySpec | None = None
    platform: PlatformSpec
    deviceTier: str = Field(pattern=r"^T[1-4]$")
    regionCode: str = Field(min_length=2, max_length=16)
    runtimeAbi: str = Field(min_length=1)
    resourceVector: ResourceVector
    runtimeClasses: list[str] = Field(min_length=1)
    storage: StorageSpec
    memory: MemorySpec
    thermal: ThermalSpec | None = None
    battery: BatterySpec | None = None
    network: NetworkSpec | None = None

    model_config = {"extra": "forbid"}
