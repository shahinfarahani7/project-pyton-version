from __future__ import annotations

import pytest
from edgemint.building_blocks.settings import Settings
from edgemint.workers.attestation import public_key_fingerprint, verify_attestation
from edgemint.workers.errors import WorkerServiceError
from edgemint.workers.lifecycle import WorkerLifecycle
from edgemint.workers.readiness import (
    WorkerReadinessSnapshot,
    assess_paid_work_eligibility,
    derive_device_tier,
)


def test_worker_lifecycle_matches_dsl() -> None:
    lifecycle = WorkerLifecycle.load()
    assert lifecycle.can_transition("registered", "attesting")
    assert lifecycle.can_transition("benchmarking", "ready")
    assert lifecycle.can_transition("ready", "reserved")
    assert not lifecycle.can_transition("banned", "ready")


def test_terminal_worker_state_rejects_transition() -> None:
    lifecycle = WorkerLifecycle.load()
    with pytest.raises(WorkerServiceError) as exc:
        lifecycle.assert_transition("banned", "ready")
    assert exc.value.code == "WORKER_QUARANTINED"


def test_attestation_rejects_emulator_in_staging() -> None:
    settings = Settings(environment="staging", worker_consent_policy_version="2026-q3-v1")
    with pytest.raises(WorkerServiceError) as exc:
        verify_attestation(
            attestation={"nonce": "abc", "emulator": True, "consentPolicyVersion": "2026-q3-v1"},
            challenge_nonce="abc",
            public_key_pem=None,
            platform="android",
            settings=settings,
        )
    assert exc.value.code == "EMULATOR_POLICY_BREACH"


def test_attestation_rejects_consent_mismatch() -> None:
    with pytest.raises(WorkerServiceError) as exc:
        verify_attestation(
            attestation={"nonce": "abc", "consentPolicyVersion": "old"},
            challenge_nonce="abc",
            public_key_pem=None,
            platform="android",
        )
    assert exc.value.code == "CONSENT_MISMATCH"


def test_attestation_rejects_cloned_key_fingerprint() -> None:
    public_key = "-----BEGIN PUBLIC KEY-----\nabc\n-----END PUBLIC KEY-----"
    with pytest.raises(WorkerServiceError) as exc:
        verify_attestation(
            attestation={
                "nonce": "abc",
                "consentPolicyVersion": "2026-q3-v1",
                "publicKeyFingerprint": "deadbeef",
            },
            challenge_nonce="abc",
            public_key_pem=public_key,
            platform="android",
        )
    assert exc.value.code == "DEVICE_KEY_MISMATCH"


def test_public_key_fingerprint_is_stable() -> None:
    pem = "-----BEGIN PUBLIC KEY-----\ntest\n-----END PUBLIC KEY-----"
    assert public_key_fingerprint(pem) == public_key_fingerprint(pem)


def test_readiness_requires_ready_status_and_availability() -> None:
    from datetime import UTC, datetime, timedelta

    now = datetime.now(UTC)
    snapshot = WorkerReadinessSnapshot(
        worker_status="benchmarking",
        device_status="active",
        attestation_status="verified",
        attestation_expires_at=now + timedelta(hours=1),
        consent_policy_version="2026-q3-v1",
        consent_withdrawn=False,
        preferences_availability="available",
        has_benchmark=True,
    )
    with pytest.raises(WorkerServiceError) as exc:
        assess_paid_work_eligibility(snapshot, now=now)
    assert exc.value.code == "WORKER_NOT_READY"

    ready = WorkerReadinessSnapshot(
        worker_status="ready",
        device_status="active",
        attestation_status="verified",
        attestation_expires_at=now + timedelta(hours=1),
        consent_policy_version="2026-q3-v1",
        consent_withdrawn=False,
        preferences_availability="available",
        has_benchmark=True,
    )
    assess_paid_work_eligibility(ready, now=now)


def test_readiness_rejects_unavailable_worker() -> None:
    from datetime import UTC, datetime, timedelta

    now = datetime.now(UTC)
    snapshot = WorkerReadinessSnapshot(
        worker_status="ready",
        device_status="active",
        attestation_status="verified",
        attestation_expires_at=now + timedelta(hours=1),
        consent_policy_version="2026-q3-v1",
        consent_withdrawn=False,
        preferences_availability="unavailable",
        has_benchmark=True,
    )
    with pytest.raises(WorkerServiceError) as exc:
        assess_paid_work_eligibility(snapshot, now=now)
    assert exc.value.code == "WORKER_NOT_READY"


def test_derive_device_tier_from_benchmark() -> None:
    assert derive_device_tier([{"metric": "tokens_per_second", "value": 150}]) == "A"
    assert derive_device_tier([{"metric": "tokens_per_second", "value": 10}]) == "D"
