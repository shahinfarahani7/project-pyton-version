from __future__ import annotations

from datetime import UTC, datetime, timedelta

from edgemint.routing.hard_eligibility import evaluate_hard_eligibility
from edgemint.routing.scarcity_cost import compute_failure_affinity_bps
from edgemint.routing.service import RouterService


def _candidate(**overrides: object) -> dict[str, object]:
    base: dict[str, object] = {
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
        "workerId": "wrk_failed",
    }
    base.update(overrides)
    return base


def test_active_cooldown_blocks_worker_via_failure_affinity() -> None:
    future = datetime.now(UTC) + timedelta(minutes=10)
    reasons = evaluate_hard_eligibility(
        _candidate(
            attemptFailures=[
                {
                    "workerId": "wrk_failed",
                    "failureCode": "THERMAL_BLOCK",
                    "observedAtUtc": datetime.now(UTC).isoformat(),
                    "cooldownUntilUtc": future.isoformat(),
                }
            ]
        )
    )
    assert "FAILURE_AFFINITY" in reasons


def test_expired_cooldown_deprioritizes_but_allows_scoring() -> None:
    past = datetime.now(UTC) - timedelta(minutes=1)
    affinity = compute_failure_affinity_bps(
        worker_id="wrk_failed",
        failures=[],
    )
    service = RouterService()
    ranked = service.rank_workers(
        task_id="tsk_retry",
        router_epoch=5,
        candidates=[
            {
                "workerId": "wrk_failed",
                "input": _candidate(
                    attemptFailures=[
                        {
                            "workerId": "wrk_failed",
                            "failureCode": "INSUFFICIENT_MEMORY",
                            "observedAtUtc": past.isoformat(),
                            "cooldownUntilUtc": past.isoformat(),
                        }
                    ]
                ),
            },
            {"workerId": "wrk_clean", "input": _candidate(workerId="wrk_clean")},
        ],
    )
    eligible = [row for row in ranked if row["eligible"]]
    assert eligible[0]["workerId"] == "wrk_clean"
    assert affinity == 10_000
