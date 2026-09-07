from __future__ import annotations

from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path
from typing import Literal

import yaml
from pydantic import BaseModel, Field


class ResourcePolicyLimits(BaseModel):
    defaultApprovedPercent: int = Field(ge=1, le=100)
    maximumApprovedPercent: int = Field(ge=1, le=100)
    safetyReservePercent: int = Field(ge=0, le=100)
    heartbeatMaximumAgeSeconds: int = Field(ge=1)
    overbookingAllowed: bool

    model_config = {"extra": "forbid"}


class ContributionMode(BaseModel):
    id: str = Field(min_length=1, pattern=r"^[a-z][a-z0-9_]*$")
    label: str = Field(min_length=1)
    approvedPercent: int = Field(ge=1, le=100)
    requiresExplicitOptIn: bool

    model_config = {"extra": "forbid"}


class AssignmentLimits(BaseModel):
    absoluteMaximumPerDevice: int = Field(ge=1)

    model_config = {"extra": "forbid"}


class ConsentChangeBehavior(BaseModel):
    increaseAppliesToNewReservationsOnly: bool
    decreaseStopsNewStagesAboveLimit: bool
    revocationStopsNewWorkImmediately: bool

    model_config = {"extra": "forbid"}


class CpuEnforcementProfile(BaseModel):
    measurementWindowMs: int = Field(ge=1)
    coveredProcessScope: str = Field(min_length=1)
    toleratedBurstBps: int = Field(ge=0, le=10_000)
    controlStopReactionBoundMs: int = Field(ge=1)
    enforcementMechanism: str = Field(min_length=1)

    model_config = {"extra": "forbid"}


class UserResourcePolicySpec(BaseModel):
    resourcePolicy: ResourcePolicyLimits
    contributionModes: list[ContributionMode] = Field(min_length=1)
    runtimeLimits: dict[str, dict[str, int | bool]]
    assignmentLimits: AssignmentLimits
    consentChangeBehavior: ConsentChangeBehavior
    contributionRequiresExplicitOptIn: bool = True
    contributionEnabledByDefault: bool = False
    cpuEnforcement: CpuEnforcementProfile | None = None

    model_config = {"extra": "forbid"}


@dataclass(frozen=True, slots=True)
class ActiveUserResourcePolicy:
    name: str
    version: str
    spec: UserResourcePolicySpec


class UserResourceContributionPolicyView(BaseModel):
    """Server-authoritative contribution policy exposed to workers."""

    policyRef: str
    defaultModeId: str
    maximumApprovedPercent: int = Field(ge=1, le=100)
    safetyReservePercent: int = Field(ge=0, le=100)
    contributionModes: list[ContributionMode]
    assignmentLimits: AssignmentLimits
    consentChangeBehavior: ConsentChangeBehavior
    contributionRequiresExplicitOptIn: bool
    contributionEnabledByDefault: bool
    cpuEnforcement: CpuEnforcementProfile | None = None

    model_config = {"extra": "forbid"}


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[4]


def _validate_policy_spec(spec: UserResourcePolicySpec) -> None:
    limits = spec.resourcePolicy
    if limits.defaultApprovedPercent > limits.maximumApprovedPercent:
        raise ValueError("defaultApprovedPercent exceeds maximumApprovedPercent")
    mode_ids = {mode.id for mode in spec.contributionModes}
    if len(mode_ids) != len(spec.contributionModes):
        raise ValueError("duplicate contribution mode ids")
    approved_values = {mode.approvedPercent for mode in spec.contributionModes}
    if limits.defaultApprovedPercent not in approved_values:
        raise ValueError("defaultApprovedPercent missing from contributionModes")
    if limits.maximumApprovedPercent not in approved_values:
        raise ValueError("maximumApprovedPercent missing from contributionModes")
    default_modes = [
        mode for mode in spec.contributionModes if mode.approvedPercent == limits.defaultApprovedPercent
    ]
    if len(default_modes) != 1 or default_modes[0].requiresExplicitOptIn:
        raise ValueError("default contribution mode must exist and not require explicit opt-in")
    max_modes = [
        mode for mode in spec.contributionModes if mode.approvedPercent == limits.maximumApprovedPercent
    ]
    if len(max_modes) != 1 or not max_modes[0].requiresExplicitOptIn:
        raise ValueError("maximum contribution mode must exist and require explicit opt-in")
    if spec.cpuEnforcement is not None and spec.cpuEnforcement.measurementWindowMs <= 0:
        raise ValueError("cpuEnforcement.measurementWindowMs must be positive")


@lru_cache(maxsize=1)
def load_active_user_resource_policy() -> ActiveUserResourcePolicy:
    policy_dir = _repo_root() / "dsl" / "policies" / "consent"
    active: ActiveUserResourcePolicy | None = None
    for path in sorted(policy_dir.glob("*.yaml")):
        document = yaml.safe_load(path.read_text(encoding="utf-8"))
        if document.get("kind") != "UserResourcePolicy":
            continue
        metadata = document["metadata"]
        if metadata.get("status") != "active":
            continue
        spec = UserResourcePolicySpec.model_validate(document["spec"])
        _validate_policy_spec(spec)
        candidate = ActiveUserResourcePolicy(
            name=str(metadata["name"]),
            version=str(metadata["version"]),
            spec=spec,
        )
        if active is not None:
            raise ValueError("multiple active UserResourcePolicy documents")
        active = candidate
    if active is None:
        raise ValueError("no active UserResourcePolicy document")
    return active


def default_contribution_mode_id() -> str:
    policy = load_active_user_resource_policy()
    for mode in policy.spec.contributionModes:
        if mode.approvedPercent == policy.spec.resourcePolicy.defaultApprovedPercent:
            return mode.id
    raise ValueError("default contribution mode missing")


def approved_percent_for_mode(mode_id: str) -> int:
    policy = load_active_user_resource_policy()
    for mode in policy.spec.contributionModes:
        if mode.id == mode_id:
            return mode.approvedPercent
    raise ValueError(f"unknown contribution mode: {mode_id}")


def validate_contribution_mode_id(mode_id: str) -> ContributionMode:
    policy = load_active_user_resource_policy()
    for mode in policy.spec.contributionModes:
        if mode.id == mode_id:
            return mode
    raise ValueError(f"unknown contribution mode: {mode_id}")


def build_contribution_policy_view() -> UserResourceContributionPolicyView:
    policy = load_active_user_resource_policy()
    return UserResourceContributionPolicyView(
        policyRef=f"UserResourcePolicy/{policy.name}@{policy.version}",
        defaultModeId=default_contribution_mode_id(),
        maximumApprovedPercent=policy.spec.resourcePolicy.maximumApprovedPercent,
        safetyReservePercent=policy.spec.resourcePolicy.safetyReservePercent,
        contributionModes=policy.spec.contributionModes,
        assignmentLimits=policy.spec.assignmentLimits,
        consentChangeBehavior=policy.spec.consentChangeBehavior,
        contributionRequiresExplicitOptIn=policy.spec.contributionRequiresExplicitOptIn,
        contributionEnabledByDefault=policy.spec.contributionEnabledByDefault,
        cpuEnforcement=policy.spec.cpuEnforcement,
    )


ContributionModeId = Literal["balanced", "performance"]
