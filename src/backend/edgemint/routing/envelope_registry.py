from __future__ import annotations

import json
import re
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path

import yaml

_ENVELOPE_REF = re.compile(r"^TaskResourceEnvelope/([A-Za-z0-9._-]+)@([0-9.]+)$")


@dataclass(frozen=True, slots=True)
class ResourceEnvelopeSpec:
    name: str
    version: str
    task_type: str
    runtime_class: str
    cpu_units: int
    memory_reservation_bytes: int
    storage_reservation_bytes: int
    accelerator_units: int
    model_session_units: int
    estimated_duration_ms: int
    maximum_parallel_per_device: int
    exclusive_group: str


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[4]


@lru_cache(maxsize=1)
def _load_envelope_specs() -> dict[str, ResourceEnvelopeSpec]:
    envelope_dir = _repo_root() / "dsl" / "catalog" / "resource-envelopes"
    specs: dict[str, ResourceEnvelopeSpec] = {}
    for path in sorted(envelope_dir.glob("*.yaml")):
        document = yaml.safe_load(path.read_text(encoding="utf-8"))
        metadata = document["metadata"]
        spec = document["spec"]
        key = f"{metadata['name']}@{metadata['version']}"
        specs[key] = ResourceEnvelopeSpec(
            name=str(metadata["name"]),
            version=str(metadata["version"]),
            task_type=str(spec["taskType"]),
            runtime_class=str(spec["runtimeClass"]),
            cpu_units=int(spec["cpuUnits"]),
            memory_reservation_bytes=int(spec["memoryReservationBytes"]),
            storage_reservation_bytes=int(spec["storageReservationBytes"]),
            accelerator_units=int(spec["acceleratorUnits"]),
            model_session_units=int(spec["modelSessionUnits"]),
            estimated_duration_ms=int(spec["estimatedDurationMs"]),
            maximum_parallel_per_device=int(spec["maximumParallelPerDevice"]),
            exclusive_group=str(spec["exclusiveGroup"]),
        )
    return specs


@lru_cache(maxsize=1)
def _load_task_envelope_refs() -> dict[str, str]:
    catalog_path = _repo_root() / "src" / "shared" / "task-types" / "catalog.json"
    document = json.loads(catalog_path.read_text(encoding="utf-8"))
    refs: dict[str, str] = {}
    for category in document["categories"]:
        for item in category["types"]:
            ref = item.get("resourceEnvelopeRef")
            if ref:
                refs[str(item["value"])] = str(ref)
    return refs


def parse_envelope_ref(ref: str) -> tuple[str, str]:
    match = _ENVELOPE_REF.match(ref)
    if match is None:
        raise ValueError(f"INVALID_ENVELOPE_REF:{ref}")
    return match.group(1), match.group(2)


def envelope_for_task_type(task_type: str) -> ResourceEnvelopeSpec | None:
    ref = _load_task_envelope_refs().get(task_type)
    if ref is None:
        return None
    name, version = parse_envelope_ref(ref)
    return _load_envelope_specs().get(f"{name}@{version}")
