from __future__ import annotations

from edgemint.governance.policy_readiness_gate import (
    PolicyCompatibility,
    PolicyReadinessRecord,
    evaluate_activation_gate,
    evaluate_dependency_enablement,
    evaluate_mixed_version_rollout,
    evaluate_policy_area,
    evaluate_storage_restore_dedup,
    hash_policy_values,
)


def test_evaluate_policy_area_partial_blocks_activation() -> None:
    area = evaluate_policy_area(
        area="execution_grant",
        configured_values=["leaseSeconds=120"],
        missing_values=["replayHorizonSeconds"],
    )
    assert area.status == "PARTIAL"
    assert area.activation_blocked is True


def test_activation_gate_closed_without_record() -> None:
    area = evaluate_policy_area(
        area="execution_grant",
        configured_values=["leaseSeconds=120"],
        missing_values=[],
    )
    result = evaluate_activation_gate(policy_areas=[area], record=None)
    assert result.status == "CLOSED"
    assert result.reason == "policy_readiness_record_missing"


def test_activation_gate_open_with_record_and_evidence() -> None:
    area = evaluate_policy_area(
        area="execution_grant",
        configured_values=["leaseSeconds=120"],
        missing_values=[],
    )
    record = PolicyReadinessRecord(
        architectureVersion="2.0",
        policyVersionHash=hash_policy_values({"leaseSeconds": 120}),
        runtimeProfileScope="production-v1",
        responsibleOwner="platform-sre",
        values={"leaseSeconds": 120},
        evidence=["plan/evidence/phase-08-p8-t04-policy-readiness-gap.json"],
        compatibility=PolicyCompatibility(workerAppMinBuild=1, workerAppMaxBuild=None),
        featureFlags={"mixedVersionRollout": False},
    )
    result = evaluate_activation_gate(policy_areas=[area], record=record)
    assert result.status == "OPEN"


def test_dependency_gate_blocks_missing_checkout_evidence() -> None:
    result = evaluate_dependency_enablement(
        architecture_version="2.0",
        pinned_checkout_evidence=None,
        path_inventory_evidence="plan/evidence/phase-08-p8-t05-current-state-register.json",
    )
    assert result.status == "CLOSED"
    assert result.reason == "pinned_checkout_evidence_missing"


def test_mixed_version_rollout_rejects_incompatible_pair() -> None:
    result = evaluate_mixed_version_rollout(
        server_architecture_version="2.0",
        worker_architecture_version="1.0",
        worker_app_build=100,
    )
    assert result.allowed is False
    assert result.requires_rollback_first is True


def test_mixed_version_rollout_accepts_compatible_pair() -> None:
    result = evaluate_mixed_version_rollout(
        server_architecture_version="2.0",
        worker_architecture_version="2.0",
        worker_app_build=100,
    )
    assert result.allowed is True


def test_storage_restore_dedup_detects_ownership_conflict() -> None:
    result = evaluate_storage_restore_dedup(
        ownership_key="workspace:ws_1",
        existing_owner="device_a",
        incoming_owner="device_b",
    )
    assert result.recovered is False
    assert result.duplicate_detected is True
