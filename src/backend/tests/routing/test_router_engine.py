from __future__ import annotations

from datetime import UTC, datetime

import pytest
from edgemint.routing.engine import evaluate_candidate
from edgemint.routing.errors import RouterServiceError
from edgemint.routing.fencing import (
    QueueAttempt,
    assert_monotonic_fence,
    assert_reassignment_budget,
    assert_renewal_sequence,
    compute_tie_breaker,
    rank_queue_attempts,
)
from edgemint.routing.policy import RoutingPolicy
from edgemint.routing.service import RouterService


def test_evaluate_rejects_ineligible_worker() -> None:
    result = evaluate_candidate(
        {
            "featuresBps": {
                "modelLocality": 0,
                "trust": 0,
                "predictedLatency": 10000,
                "batteryCharging": 3000,
                "network": 3000,
                "regionalCompliance": 0,
                "priceEfficiency": 0,
                "reliability": 0,
            },
            "heartbeatAgeSeconds": 0,
            "batteryPercent": 0,
            "thermalState": "nominal",
            "attested": False,
            "consentCurrent": False,
            "modelDigestMatch": False,
            "runtimeAbiMatch": False,
            "regionAllowed": False,
            "networkPolicyAllowed": False,
            "available": False,
        }
    )
    assert result["eligible"] is False
    assert "TRUST_TOO_LOW" in result["ineligibilityReasons"]
    assert result["score"] == 2150


def test_stale_fence_rejected() -> None:
    with pytest.raises(RouterServiceError) as exc:
        assert_monotonic_fence(presented=1, current=2)
    assert exc.value.code == "ASSIGNMENT_STALE_FENCE"


def test_renewal_sequence_must_increase() -> None:
    with pytest.raises(RouterServiceError) as exc:
        assert_renewal_sequence(presented=3, last_renewal=3)
    assert exc.value.code == "LEASE_RENEWAL_REJECTED"


def test_reassignment_budget_enforced() -> None:
    with pytest.raises(RouterServiceError) as exc:
        assert_reassignment_budget(assignment_count=3, max_reassignments=2)
    assert exc.value.code == "NO_CAPACITY"


def test_queue_starvation_precedence() -> None:
    now = datetime.now(UTC)
    attempts = [
        QueueAttempt("a1", "ws1", 2000, now, None, "t1", deficit_units=5, waiting_seconds=60),
        QueueAttempt("a2", "ws2", 2000, now, None, "t2", deficit_units=1, waiting_seconds=400),
    ]
    ranked = rank_queue_attempts(attempts)
    assert ranked[0].attempt_id == "a2"


def test_policy_forbids_worker_confirmation() -> None:
    policy = RoutingPolicy.load()
    assert policy.assignment_mode == "server_auto_lease"
    assert policy.per_task_worker_confirmation is False
    assert policy.delivery_ack_meaning == "transport_receipt_only"


def test_tie_breaker_is_deterministic() -> None:
    signing_key = "test-signing-key"
    first = compute_tie_breaker(task_id="tsk_1", worker_id="wrk_1", router_epoch=7, secret=signing_key)
    second = compute_tie_breaker(task_id="tsk_1", worker_id="wrk_1", router_epoch=7, secret=signing_key)
    third = compute_tie_breaker(task_id="tsk_1", worker_id="wrk_2", router_epoch=7, secret=signing_key)
    assert first == second
    assert first != third


def test_rank_workers_prefers_higher_score() -> None:
    service = RouterService()
    ranked = service.rank_workers(
        task_id="tsk_1",
        router_epoch=1,
        candidates=[
            {
                "workerId": "wrk_low",
                "input": {
                    "featuresBps": {
                        "modelLocality": 1000,
                        "trust": 1000,
                        "predictedLatency": 1000,
                        "batteryCharging": 1000,
                        "network": 1000,
                        "regionalCompliance": 1000,
                        "priceEfficiency": 1000,
                        "reliability": 1000,
                    },
                    "heartbeatAgeSeconds": 1,
                    "batteryPercent": 100,
                    "thermalState": "nominal",
                    "attested": True,
                    "consentCurrent": True,
                    "modelDigestMatch": True,
                    "runtimeAbiMatch": True,
                    "regionAllowed": True,
                    "networkPolicyAllowed": True,
                    "available": True,
                },
            },
            {
                "workerId": "wrk_high",
                "input": {
                    "featuresBps": {
                        "modelLocality": 10000,
                        "trust": 10000,
                        "predictedLatency": 10000,
                        "batteryCharging": 10000,
                        "network": 10000,
                        "regionalCompliance": 10000,
                        "priceEfficiency": 10000,
                        "reliability": 10000,
                    },
                    "heartbeatAgeSeconds": 1,
                    "batteryPercent": 100,
                    "thermalState": "nominal",
                    "attested": True,
                    "consentCurrent": True,
                    "modelDigestMatch": True,
                    "runtimeAbiMatch": True,
                    "regionAllowed": True,
                    "networkPolicyAllowed": True,
                    "available": True,
                },
            },
        ],
    )
    assert ranked[0]["workerId"] == "wrk_high"
    assert ranked[0]["eligible"] is True


def test_cloud_fallback_threshold() -> None:
    service = RouterService()
    assert service.cloud_fallback_due(edge_wait_seconds=50) is True
    assert service.cloud_fallback_due(edge_wait_seconds=10) is False
