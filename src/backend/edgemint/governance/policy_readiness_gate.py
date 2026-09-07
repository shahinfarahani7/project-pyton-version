"""Policy readiness activation gate and mixed-version rollout (v2 A23 / T23)."""

from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Literal

import yaml
from pydantic import BaseModel, Field

DEFAULT_POLICY_PATH = (
    Path(__file__).resolve().parents[4]
    / "dsl"
    / "policies"
    / "governance"
    / "policy-readiness-gate-v1.yaml"
)

PolicyAreaStatus = Literal["CONFIGURED", "PARTIAL", "MISSING"]
ActivationStatus = Literal["OPEN", "CLOSED"]


class PolicyCompatibility(BaseModel):
    workerAppMinBuild: int = Field(ge=1)
    workerAppMaxBuild: int | None = Field(default=None, ge=1)

    model_config = {"extra": "forbid"}


class PolicyReadinessRecord(BaseModel):
    architectureVersion: str = Field(min_length=1)
    policyVersionHash: str = Field(pattern=r"^[a-f0-9]{64}$")
    runtimeProfileScope: str = Field(min_length=1)
    responsibleOwner: str = Field(min_length=1)
    values: dict[str, Any] = Field(default_factory=dict)
    evidence: list[str] = Field(default_factory=list)
    compatibility: PolicyCompatibility
    featureFlags: dict[str, bool] = Field(default_factory=dict)

    model_config = {"extra": "forbid"}


@dataclass(frozen=True)
class PolicyAreaEvaluation:
    area: str
    status: PolicyAreaStatus
    missing_values: tuple[str, ...]
    activation_blocked: bool


@dataclass(frozen=True)
class ActivationGateResult:
    status: ActivationStatus
    blocked_areas: tuple[str, ...]
    reason: str


@dataclass(frozen=True)
class MixedVersionRolloutResult:
    allowed: bool
    reason: str
    requires_rollback_first: bool = False


@dataclass(frozen=True)
class StorageRestoreDedupResult:
    recovered: bool
    duplicate_detected: bool
    ownership_key: str
    detail: str


def load_policy_readiness_gate(path: Path | None = None) -> dict[str, Any]:
    policy_path = path or DEFAULT_POLICY_PATH
    raw = yaml.safe_load(policy_path.read_text(encoding="utf-8"))
    if not isinstance(raw, dict):
        raise ValueError(f"invalid policy readiness gate document: {policy_path}")
    return raw


def hash_policy_values(values: dict[str, Any]) -> str:
    encoded = json.dumps(values, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def evaluate_policy_area(
    *,
    area: str,
    configured_values: list[str],
    missing_values: list[str],
    policy: dict[str, Any] | None = None,
) -> PolicyAreaEvaluation:
    loaded = policy or load_policy_readiness_gate()
    gate = loaded.get("activationGate") or {}
    if missing_values and not configured_values:
        status: PolicyAreaStatus = "MISSING"
    elif missing_values:
        status = "PARTIAL"
    else:
        status = "CONFIGURED"
    blocked = bool(missing_values) and bool(gate.get("blockPartialPolicyAreas", True))
    return PolicyAreaEvaluation(
        area=area,
        status=status,
        missing_values=tuple(missing_values),
        activation_blocked=blocked,
    )


def evaluate_activation_gate(
    *,
    policy_areas: list[PolicyAreaEvaluation],
    record: PolicyReadinessRecord | None = None,
    policy: dict[str, Any] | None = None,
) -> ActivationGateResult:
    loaded = policy or load_policy_readiness_gate()
    gate = loaded.get("activationGate") or {}
    blocked = [area.area for area in policy_areas if area.activation_blocked]
    if blocked:
        return ActivationGateResult(
            status="CLOSED",
            blocked_areas=tuple(blocked),
            reason="missing_or_partial_policy_values",
        )
    if gate.get("requirePolicyReadinessRecord", True) and record is None:
        return ActivationGateResult(
            status="CLOSED",
            blocked_areas=tuple(),
            reason="policy_readiness_record_missing",
        )
    if record is not None and not record.evidence:
        return ActivationGateResult(
            status="CLOSED",
            blocked_areas=tuple(),
            reason="policy_evidence_missing",
        )
    return ActivationGateResult(
        status="OPEN",
        blocked_areas=tuple(),
        reason="all_policy_areas_configured",
    )


def evaluate_dependency_enablement(
    *,
    architecture_version: str,
    pinned_checkout_evidence: str | None,
    path_inventory_evidence: str | None,
    policy: dict[str, Any] | None = None,
) -> ActivationGateResult:
    loaded = policy or load_policy_readiness_gate()
    gates = loaded.get("dependencyGates") or {}
    if gates.get("requireArchitectureVersionMatch", True) and not architecture_version:
        return ActivationGateResult("CLOSED", tuple(), "architecture_version_missing")
    if gates.get("requirePinnedCheckoutEvidence", True) and not pinned_checkout_evidence:
        return ActivationGateResult("CLOSED", tuple(), "pinned_checkout_evidence_missing")
    if gates.get("requirePathInventoryForSection3", True) and not path_inventory_evidence:
        return ActivationGateResult("CLOSED", tuple(), "section3_path_inventory_missing")
    return ActivationGateResult("OPEN", tuple(), "dependency_evidence_present")


def evaluate_mixed_version_rollout(
    *,
    server_architecture_version: str,
    worker_architecture_version: str,
    worker_app_build: int,
    policy: dict[str, Any] | None = None,
) -> MixedVersionRolloutResult:
    loaded = policy or load_policy_readiness_gate()
    rollout = loaded.get("mixedVersionRollout") or {}
    pairs = rollout.get("supportedPairs") or []
    for pair in pairs:
        if (
            pair.get("serverArchitectureVersion") == server_architecture_version
            and pair.get("workerArchitectureVersion") == worker_architecture_version
        ):
            min_build = int(pair.get("workerAppMinBuild", 1))
            max_build = pair.get("workerAppMaxBuild")
            if worker_app_build < min_build:
                return MixedVersionRolloutResult(
                    allowed=False,
                    reason="worker_build_below_minimum",
                    requires_rollback_first=bool(rollout.get("rollbackBeforeForwardAdoption", True)),
                )
            if max_build is not None and worker_app_build > int(max_build):
                return MixedVersionRolloutResult(
                    allowed=False,
                    reason="worker_build_above_maximum",
                )
            return MixedVersionRolloutResult(allowed=True, reason="compatible_pair")
    return MixedVersionRolloutResult(
        allowed=False,
        reason="unsupported_architecture_pair",
        requires_rollback_first=bool(rollout.get("rollbackBeforeForwardAdoption", True)),
    )


def evaluate_storage_restore_dedup(
    *,
    ownership_key: str,
    existing_owner: str | None,
    incoming_owner: str,
    policy: dict[str, Any] | None = None,
) -> StorageRestoreDedupResult:
    loaded = policy or load_policy_readiness_gate()
    restore = loaded.get("storageRestore") or {}
    if restore.get("requireOwnershipDedupRecovery", True) and existing_owner and existing_owner != incoming_owner:
        return StorageRestoreDedupResult(
            recovered=False,
            duplicate_detected=True,
            ownership_key=ownership_key,
            detail="ownership_conflict_requires_reconciliation",
        )
    return StorageRestoreDedupResult(
        recovered=True,
        duplicate_detected=existing_owner == incoming_owner and existing_owner is not None,
        ownership_key=ownership_key,
        detail="ownership_recovered_or_first_claim",
    )
