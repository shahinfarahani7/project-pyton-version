"""Active model identity tracing and Native crash reconciliation (v2 A22 / T22)."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from pathlib import Path
from typing import Any

from typing import Any

import yaml
from pydantic import BaseModel, Field

DEFAULT_POLICY_PATH = (
    Path(__file__).resolve().parents[4]
    / "dsl"
    / "policies"
    / "worker"
    / "active-identity-native-lifecycle-v1.yaml"
)


class NativeHandleCounters(BaseModel):
    modelCreate: int = Field(default=0, ge=0)
    modelClose: int = Field(default=0, ge=0)
    sessionCreate: int = Field(default=0, ge=0)
    sessionClose: int = Field(default=0, ge=0)
    identityClear: int = Field(default=0, ge=0)

    model_config = {"extra": "forbid"}


class IdentityMutationEvent(BaseModel):
    sequence: int = Field(ge=1)
    kind: str = Field(min_length=1)
    caller: str = Field(min_length=1)
    reason: str | None = None
    before: dict[str, Any] | None = None
    after: dict[str, Any] | None = None
    observedAt: datetime | None = None

    model_config = {"extra": "forbid"}


class WorkerIdentityLifecycleView(BaseModel):
    eventSequence: int = Field(ge=0)
    bootstrapInFlight: bool = False
    runtimeGeneration: int = Field(default=0, ge=0)
    nativeHandlesInvalidated: bool = False
    idleChurnDetected: bool = False
    nativeHandleCounters: NativeHandleCounters = Field(default_factory=NativeHandleCounters)
    recentMutations: list[IdentityMutationEvent] = Field(default_factory=list)

    model_config = {"extra": "forbid"}


@dataclass(frozen=True)
class NativeCrashReconciliationResult:
    inferred_crash: bool
    grant_revoked: bool
    resume_blocked: bool
    failure_code: str | None
    detail: str


def load_active_identity_policy(path: Path | None = None) -> dict[str, Any]:
    policy_path = path or DEFAULT_POLICY_PATH
    raw = yaml.safe_load(policy_path.read_text(encoding="utf-8"))
    if not isinstance(raw, dict):
        raise ValueError(f"invalid identity lifecycle policy: {policy_path}")
    return raw


def detect_idle_churn(
    view: WorkerIdentityLifecycleView,
    *,
    has_active_assignment: bool,
    policy: dict[str, Any] | None = None,
) -> bool:
    loaded = policy or load_active_identity_policy()
    idle_policy = loaded.get("idleStability") or {}
    if has_active_assignment:
        return False
    if view.idleChurnDetected:
        return True
    max_clears = int(idle_policy.get("maxIdentityClearsPerHour", 2))
    counters = view.nativeHandleCounters
    return counters.identityClear > max_clears


def evaluate_bootstrap_overlap(view: WorkerIdentityLifecycleView) -> bool:
    """Return True when concurrent bootstrap is active (must serialize)."""
    if view.bootstrapInFlight:
        return True
    kinds = {event.kind for event in view.recentMutations[-4:]}
    return "bootstrapStarted" in kinds and "bootstrapCompleted" not in kinds


def reconcile_native_crash(
    *,
    assignment_id: str | None,
    lease_active: bool,
    connection_lost: bool,
    last_heartbeat_at: datetime | None,
    crash_metadata: dict[str, Any] | None,
    policy: dict[str, Any] | None = None,
) -> NativeCrashReconciliationResult:
    """Infer grant loss from lease/connection evidence without Dart after SIGSEGV."""
    loaded = policy or load_active_identity_policy()
    crash_policy = loaded.get("nativeCrashReconciliation") or {}
    codes = crash_policy.get("failureCodes") or {}
    native_crash_code = str(codes.get("nativeCrashInferred", "NATIVE_CRASH_INFERRED"))
    stale_grant_code = str(codes.get("staleGrantAfterCrash", "STALE_GRANT_AFTER_CRASH"))

    authenticated_restart = bool(crash_metadata and crash_metadata.get("authenticatedRestart"))
    inferred_native_crash = bool(
        crash_metadata
        and (
            crash_metadata.get("signal") in {"SIGSEGV", "SIGABRT", "SIGBUS"}
            or crash_metadata.get("nativeCrash") is True
        )
    )

    heartbeat_stale = False
    if last_heartbeat_at is not None:
        heartbeat_stale = datetime.now(UTC) - last_heartbeat_at > timedelta(minutes=5)

    inferred_crash = inferred_native_crash or (
        connection_lost and lease_active and heartbeat_stale and assignment_id is not None
    )

    if not inferred_crash:
        return NativeCrashReconciliationResult(
            inferred_crash=False,
            grant_revoked=False,
            resume_blocked=False,
            failure_code=None,
            detail="no crash evidence",
        )

    if lease_active and not authenticated_restart:
        return NativeCrashReconciliationResult(
            inferred_crash=True,
            grant_revoked=True,
            resume_blocked=True,
            failure_code=stale_grant_code,
            detail="active lease without authenticated restart after inferred native crash",
        )

    return NativeCrashReconciliationResult(
        inferred_crash=True,
        grant_revoked=inferred_crash,
        resume_blocked=inferred_crash and assignment_id is not None,
        failure_code=native_crash_code if inferred_native_crash else stale_grant_code,
        detail="native crash reconciled from lease and restart metadata",
    )


def evaluate_t22_certification(
    *,
    device_is_emulator: bool,
    scenarios_passed: set[str],
    policy: dict[str, Any] | None = None,
) -> dict[str, Any]:
    loaded = policy or load_active_identity_policy()
    matrix = loaded.get("physicalDeviceMatrix") or {}
    required: list[dict[str, Any]] = list(matrix.get("requiredScenarios") or [])
    physical_required = {
        str(row.get("id"))
        for row in required
        if bool(row.get("requiresPhysicalDevice", True))
    }
    emulator_only = {
        str(row.get("id"))
        for row in required
        if bool(row.get("emulatorSufficient", False))
    }

    missing = sorted(physical_required - scenarios_passed)
    emulator_blocked = device_is_emulator and bool(
        matrix.get("emulatorAloneCannotCertifyProduction", True)
    )

    certified = not missing and not emulator_blocked
    return {
        "certified": certified,
        "deviceIsEmulator": device_is_emulator,
        "physicalRequired": sorted(physical_required),
        "emulatorSufficient": sorted(emulator_only),
        "scenariosPassed": sorted(scenarios_passed),
        "missingPhysicalScenarios": missing,
        "emulatorAloneBlocked": emulator_blocked,
    }
