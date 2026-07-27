from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

import yaml

from edgemint.models.errors import model_error


@dataclass(frozen=True, slots=True)
class ModelProfile:
    name: str
    version: str
    family: str
    runtime: str
    runtime_abi: str
    minimum_tier: str
    peak_ram_bytes: int | None
    minimum_free_storage_bytes: int | None
    license_status: str
    production_eligible: bool
    required_evidence: tuple[str, ...]


def load_model_profiles(root: Path | None = None) -> dict[str, ModelProfile]:
    base = root or Path(__file__).resolve().parents[4] / "dsl" / "catalog" / "models"
    profiles: dict[str, ModelProfile] = {}
    for path in sorted(base.glob("*.yaml")):
        document = yaml.safe_load(path.read_text(encoding="utf-8"))
        spec = document["spec"]
        metadata = document["metadata"]
        profiles[metadata["name"]] = ModelProfile(
            name=metadata["name"],
            version=metadata["version"],
            family=spec["family"],
            runtime=spec["runtime"],
            runtime_abi=spec.get("runtimeAbi", "unknown"),
            minimum_tier=spec["resources"]["minimumTier"],
            peak_ram_bytes=spec["resources"].get("peakRamBytes"),
            minimum_free_storage_bytes=spec["resources"].get("minimumFreeStorageBytes"),
            license_status=spec["license"]["status"],
            production_eligible=bool(spec["release"]["productionEligible"]),
            required_evidence=tuple(spec["release"].get("requiredEvidence") or ()),
        )
    return profiles


def assert_profile_production_ready(profile: ModelProfile) -> None:
    if not profile.production_eligible:
        raise model_error("MODEL_RELEASE_EVIDENCE_MISSING", detail=f"{profile.name} not production eligible")
    if profile.license_status != "approved":
        raise model_error("MODEL_RELEASE_EVIDENCE_MISSING", detail="license not approved")
    missing = [item for item in profile.required_evidence if item not in {
        "exact artifact bytes",
        "sha256",
        "signature",
        "license approval",
        "real-device benchmark",
        "runtime compatibility",
    }]
    if missing:
        raise model_error("MODEL_RELEASE_EVIDENCE_MISSING", detail=f"unknown evidence: {missing[0]}")
