from __future__ import annotations

from edgemint.routing.routing_audit import policy_hash
from edgemint.routing.service import RouterService


def _candidate(worker_id: str) -> dict[str, object]:
    return {
        "workerId": worker_id,
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
            "modelAvailable": True,
            "runtimeAbiMatch": True,
            "regionAllowed": True,
            "networkPolicyAllowed": True,
            "available": True,
            "workerId": worker_id,
        },
    }


def test_worker_scoring_is_deterministic_over_100_iterations() -> None:
    service = RouterService()
    candidates = [_candidate("wrk_a"), _candidate("wrk_b")]
    first = service.select_worker(task_id="tsk_det", router_epoch=11, candidates=candidates)
    assert first is not None
    for _ in range(100):
        winner = service.select_worker(task_id="tsk_det", router_epoch=11, candidates=candidates)
        assert winner == first


def test_policy_hash_is_stable() -> None:
    assert policy_hash() == policy_hash()
