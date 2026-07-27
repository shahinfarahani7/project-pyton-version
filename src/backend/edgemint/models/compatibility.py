from __future__ import annotations

from dataclasses import dataclass

from edgemint.models.errors import model_error

TIER_ORDER = {"T1": 1, "T2": 2, "T3": 3, "T4": 4, "A": 1, "B": 2, "C": 3, "D": 4}


@dataclass(frozen=True, slots=True)
class DeviceResourceSnapshot:
    device_tier: str
    runtime_abi: str
    free_ram_bytes: int
    free_storage_bytes: int


@dataclass(frozen=True, slots=True)
class ModelResourceEnvelope:
    minimum_device_tier: str
    runtime_abi: str
    peak_ram_bytes: int
    minimum_free_storage_bytes: int


def assert_device_compatible(device: DeviceResourceSnapshot, envelope: ModelResourceEnvelope) -> None:
    device_rank = TIER_ORDER.get(device.device_tier.upper(), 0)
    required_rank = TIER_ORDER.get(envelope.minimum_device_tier.upper(), 99)
    if device_rank < required_rank:
        raise model_error("MODEL_NOT_COMPATIBLE", detail="device tier insufficient")
    if envelope.runtime_abi != "any" and device.runtime_abi != envelope.runtime_abi:
        raise model_error("RUNTIME_ABI_MISMATCH")
    if envelope.peak_ram_bytes > 0 and device.free_ram_bytes < envelope.peak_ram_bytes:
        raise model_error("MODEL_NOT_COMPATIBLE", detail="insufficient ram")
    if (
        envelope.minimum_free_storage_bytes > 0
        and device.free_storage_bytes < envelope.minimum_free_storage_bytes
    ):
        raise model_error("INSUFFICIENT_STORAGE")
