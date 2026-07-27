from __future__ import annotations

import sys
from datetime import UTC, datetime, timedelta
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "src" / "backend"))

from edgemint.routing.policy import RoutingPolicy  # noqa: E402
from edgemint.routing.service import RouterService  # noqa: E402


def contract_checks() -> list[str]:
    errors: list[str] = []
    service_src = (ROOT / "src/backend/edgemint/routing/service.py").read_text(encoding="utf-8")
    router_api = (ROOT / "src/backend/edgemint/services/router.py").read_text(encoding="utf-8")
    for token in [
        "evaluate_candidate",
        "rank_queue_attempts",
        "assert_monotonic_fence",
        "acquire_assignment_lease",
        "renew_assignment_lease",
        "select_next_attempt",
    ]:
        if token not in service_src:
            errors.append(f"routing service missing:{token}")
    for route in ['"/internal/router/evaluate"', '"/router/policy"']:
        if route not in router_api:
            errors.append(f"router api missing route {route}")
    policy = RoutingPolicy.load()
    if policy.per_task_worker_confirmation:
        errors.append("per-task worker confirmation must remain forbidden")
    if policy.assignment_mode != "server_auto_lease":
        errors.append("assignment mode must be server_auto_lease")
    return errors


def semantic_checks() -> list[str]:
    errors: list[str] = []
    service = RouterService()
    explanation = service.explain_decision(
        attempt_id="att_1",
        worker_id="wrk_1",
        candidate_input={
            "featuresBps": {
                "modelLocality": 10000,
                "trust": 7000,
                "predictedLatency": 9000,
                "batteryCharging": 10000,
                "network": 8500,
                "regionalCompliance": 10000,
                "priceEfficiency": 5000,
                "reliability": 6000,
            },
            "heartbeatAgeSeconds": 10,
            "batteryPercent": 80,
            "thermalState": "nominal",
            "attested": True,
            "consentCurrent": True,
            "modelDigestMatch": True,
            "runtimeAbiMatch": True,
            "regionAllowed": True,
            "networkPolicyAllowed": True,
            "available": True,
        },
    )
    if explanation["workerConfirmationRequired"]:
        errors.append("worker confirmation must not be required")
    if explanation["deliveryAckMeaning"] != "transport_receipt_only":
        errors.append("delivery ack must be transport-only")
    ranked = service.rank_attempts_for_tests(
        [
            {
                "attemptId": "att_newer",
                "workspaceId": "ws_a",
                "priorityBps": 2000,
                "submittedAt": datetime.now(UTC),
                "taskId": "tsk_b",
                "deficitUnits": 10,
                "waitingSeconds": 30,
            },
            {
                "attemptId": "att_starved",
                "workspaceId": "ws_b",
                "priorityBps": 2000,
                "submittedAt": datetime.now(UTC) - timedelta(minutes=10),
                "taskId": "tsk_a",
                "deficitUnits": 1,
                "waitingSeconds": 400,
            },
        ]
    )
    if ranked[0] != "att_starved":
        errors.append("starvation override did not win")
    return errors


def main() -> int:
    errors = contract_checks() + semantic_checks()
    if errors:
        for item in errors:
            print(item)
        return 1
    print("router e2e checks passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
