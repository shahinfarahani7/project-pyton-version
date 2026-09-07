from __future__ import annotations

from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path
from typing import Literal

import yaml
from pydantic import BaseModel, Field

ExecutionPolicyId = Literal["edge_only", "edge_preferred", "cloud_permitted"]
ProcessingDestination = Literal[
    "edge_worker",
    "cloud_provider",
    "third_party_worker_unattested",
    "cross_tenant_artifact",
    "revoked_worker_device",
]


class DataProcessingRules(BaseModel):
    allowedExecutionPolicies: list[str] = Field(min_length=1)
    regionEnforcement: bool
    prohibitedDestinations: list[str] = Field(default_factory=list)
    permittedCloudRegions: list[str] = Field(default_factory=list)
    requireDataOwnerProcessingConsent: bool = True

    model_config = {"extra": "forbid"}


class TrustProfileSpec(BaseModel):
    requiresAttestation: bool = False
    minimumTrustMilli: int | None = None
    allowedDeviceStatuses: list[str] = Field(default_factory=list)
    permittedRegions: list[str] = Field(default_factory=list)

    model_config = {"extra": "forbid"}


DEFAULT_ACTIVE_DATA_POLICY_NAME = "production-data-policy-v1"


class DataPolicySpec(BaseModel):
    classification: str
    processing: DataProcessingRules
    trustProfiles: dict[str, TrustProfileSpec] = Field(default_factory=dict)

    model_config = {"extra": "ignore"}


@dataclass(frozen=True, slots=True)
class ActiveDataPolicy:
    name: str
    version: str
    spec: DataPolicySpec


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[4]


@lru_cache(maxsize=1)
def load_active_data_policy() -> ActiveDataPolicy:
    policy_dir = _repo_root() / "dsl" / "policies" / "data"
    active: ActiveDataPolicy | None = None
    for path in sorted(policy_dir.glob("*.yaml")):
        document = yaml.safe_load(path.read_text(encoding="utf-8"))
        if document.get("kind") != "DataPolicy":
            continue
        metadata = document["metadata"]
        if str(metadata.get("name")) != DEFAULT_ACTIVE_DATA_POLICY_NAME:
            continue
        if metadata.get("status") != "active":
            continue
        spec = DataPolicySpec.model_validate(document["spec"])
        candidate = ActiveDataPolicy(
            name=str(metadata["name"]),
            version=str(metadata["version"]),
            spec=spec,
        )
        if active is not None:
            raise ValueError("duplicate active default DataPolicy document")
        active = candidate
    if active is None:
        raise ValueError("no active DataPolicy document")
    return active


def data_policy_ref() -> str:
    policy = load_active_data_policy()
    return f"DataPolicy/{policy.name}@{policy.version}"
