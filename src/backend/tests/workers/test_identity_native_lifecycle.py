from __future__ import annotations

from datetime import UTC, datetime, timedelta

from edgemint.workers.identity_native_lifecycle import (
    NativeHandleCounters,
    WorkerIdentityLifecycleView,
    detect_idle_churn,
    evaluate_bootstrap_overlap,
    evaluate_t22_certification,
    reconcile_native_crash,
)


def test_reconcile_native_crash_from_sigsegv_metadata() -> None:
    result = reconcile_native_crash(
        assignment_id="asg_1",
        lease_active=True,
        connection_lost=True,
        last_heartbeat_at=datetime.now(UTC) - timedelta(minutes=10),
        crash_metadata={"signal": "SIGSEGV", "nativeCrash": True},
    )
    assert result.inferred_crash is True
    assert result.grant_revoked is True
    assert result.resume_blocked is True
    assert result.failure_code == "STALE_GRANT_AFTER_CRASH"


def test_reconcile_native_crash_with_authenticated_restart() -> None:
    result = reconcile_native_crash(
        assignment_id="asg_2",
        lease_active=False,
        connection_lost=True,
        last_heartbeat_at=datetime.now(UTC) - timedelta(minutes=10),
        crash_metadata={
            "signal": "SIGSEGV",
            "nativeCrash": True,
            "authenticatedRestart": True,
        },
    )
    assert result.inferred_crash is True
    assert result.failure_code == "NATIVE_CRASH_INFERRED"


def test_reconcile_no_crash_when_heartbeat_recent() -> None:
    result = reconcile_native_crash(
        assignment_id="asg_3",
        lease_active=True,
        connection_lost=False,
        last_heartbeat_at=datetime.now(UTC) - timedelta(seconds=30),
        crash_metadata=None,
    )
    assert result.inferred_crash is False
    assert result.grant_revoked is False


def test_detect_idle_churn_without_assignment() -> None:
    view = WorkerIdentityLifecycleView(
        eventSequence=4,
        idleChurnDetected=True,
        nativeHandleCounters=NativeHandleCounters(identityClear=3),
    )
    assert detect_idle_churn(view, has_active_assignment=False) is True
    assert detect_idle_churn(view, has_active_assignment=True) is False


def test_evaluate_bootstrap_overlap_detects_inflight() -> None:
    view = WorkerIdentityLifecycleView(eventSequence=2, bootstrapInFlight=True)
    assert evaluate_bootstrap_overlap(view) is True


def test_t22_certification_blocks_emulator_only() -> None:
    report = evaluate_t22_certification(
        device_is_emulator=True,
        scenarios_passed={"missing_model_recovery"},
    )
    assert report["certified"] is False
    assert report["emulatorAloneBlocked"] is True


def test_t22_certification_requires_physical_scenarios() -> None:
    report = evaluate_t22_certification(
        device_is_emulator=False,
        scenarios_passed={"missing_model_recovery"},
    )
    assert report["certified"] is False
    assert "idle_identity_loop" in report["missingPhysicalScenarios"]
