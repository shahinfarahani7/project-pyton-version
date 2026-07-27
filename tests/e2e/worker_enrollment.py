from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "src" / "backend"))

from edgemint.workers.errors import WorkerServiceError  # noqa: E402
from edgemint.workers.lifecycle import WorkerLifecycle  # noqa: E402
from edgemint.workers.readiness import WorkerReadinessSnapshot, assess_paid_work_eligibility  # noqa: E402


def contract_checks() -> list[str]:
    errors: list[str] = []
    enrollment = (ROOT / "src/backend/edgemint/workers/enrollment.py").read_text(encoding="utf-8")
    service = (ROOT / "src/backend/edgemint/services/worker_registry.py").read_text(encoding="utf-8")
    settings = (ROOT / "src/backend/edgemint/building_blocks/settings.py").read_text(encoding="utf-8")

    for token in [
        "create_device_challenge",
        "register_worker_device",
        "send_heartbeat",
        "submit_benchmark_for_session",
        "replace_worker_preferences",
        "verify_attestation",
    ]:
        if token not in enrollment:
            errors.append(f"enrollment missing:{token}")
    for route in [
        '"/auth/challenges"',
        '"/workers/register"',
        '"/sessions:refresh"',
        '"/workers/{worker_id}/heartbeat"',
        '"/worker-preferences"',
    ]:
        if route not in service:
            errors.append(f"worker-registry missing route {route}")
    for setting in [
        "worker_challenge_ttl_seconds",
        "worker_consent_policy_version",
        "worker_registry_workspace_id",
    ]:
        if setting not in settings:
            errors.append(f"settings missing {setting}")
    lifecycle = WorkerLifecycle.load()
    if not lifecycle.can_transition("attesting", "benchmarking"):
        errors.append("worker lifecycle missing attesting->benchmarking")
    return errors


def semantic_checks() -> list[str]:
    errors: list[str] = []
    from datetime import UTC, datetime, timedelta

    now = datetime.now(UTC)
    snapshot = WorkerReadinessSnapshot(
        worker_status="quarantined",
        device_status="active",
        attestation_status="verified",
        attestation_expires_at=now + timedelta(hours=1),
        consent_policy_version="2026-q3-v1",
        consent_withdrawn=False,
        preferences_availability="available",
        has_benchmark=True,
    )
    try:
        assess_paid_work_eligibility(snapshot, now=now)
    except WorkerServiceError as exc:
        if exc.code != "WORKER_QUARANTINED":
            errors.append("unexpected quarantine error code")
    else:
        errors.append("quarantined worker accepted for paid work")
    return errors


def main() -> int:
    errors = contract_checks() + semantic_checks()
    if errors:
        for item in errors:
            print(item)
        return 1
    print("worker enrollment e2e checks passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
