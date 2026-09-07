from __future__ import annotations

from edgemint.routing.hard_eligibility import evaluate_hard_eligibility
from edgemint.routing.scoring_features import compute_resource_fit_bps
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
        "effectiveBudgets": {"cpuUnits": 100, "memoryBytes": 8_000_000_000, "storageBytes": 4_000_000_000},
        "reservedTotals": {"cpuUnits": 0, "memoryBytes": 0, "storageBytes": 0},
        "requestedTotals": {"cpuUnits": 40, "memoryBytes": 1_600_000_000, "storageBytes": 100_000_000},
    }
    base.update(overrides)
    return base


def test_resource_budget_exceeded_filters_worker() -> None:
    reasons = evaluate_hard_eligibility(
        _candidate(
            effectiveBudgets={"cpuUnits": 80, "memoryBytes": 8_000_000_000, "storageBytes": 4_000_000_000},
            reservedTotals={"cpuUnits": 10, "memoryBytes": 0, "storageBytes": 0},
            requestedTotals={"cpuUnits": 75, "memoryBytes": 1_600_000_000, "storageBytes": 100_000_000},
        )
    )
    assert "CPU_BUDGET_EXCEEDED" in reasons


def test_resource_fit_prefers_worker_with_more_headroom() -> None:
    tight = compute_resource_fit_bps(
        effective_budgets={"cpuUnits": 100, "memoryBytes": 8_000_000_000, "storageBytes": 4_000_000_000},
        reserved_totals={"cpuUnits": 50, "memoryBytes": 6_000_000_000, "storageBytes": 3_000_000_000},
        requested_totals={"cpuUnits": 40, "memoryBytes": 1_000_000_000, "storageBytes": 500_000_000},
    )
    roomy = compute_resource_fit_bps(
        effective_budgets={"cpuUnits": 100, "memoryBytes": 8_000_000_000, "storageBytes": 4_000_000_000},
        reserved_totals={"cpuUnits": 0, "memoryBytes": 0, "storageBytes": 0},
        requested_totals={"cpuUnits": 40, "memoryBytes": 1_000_000_000, "storageBytes": 500_000_000},
    )
    assert roomy > tight


def test_rank_workers_orders_by_resource_headroom_when_locality_equal() -> None:
    service = RouterService()
    ranked = service.rank_workers(
        task_id="tsk_fit",
        router_epoch=2,
        candidates=[
            {
                "workerId": "wrk_tight",
                "input": _candidate(
                    reservedTotals={"cpuUnits": 50, "memoryBytes": 0, "storageBytes": 0},
                ),
            },
            {
                "workerId": "wrk_roomy",
                "input": _candidate(
                    reservedTotals={"cpuUnits": 0, "memoryBytes": 0, "storageBytes": 0},
                ),
            },
        ],
    )
    eligible = [row for row in ranked if row["eligible"]]
    assert eligible[0]["workerId"] == "wrk_roomy"
    assert eligible[0]["score"] > eligible[1]["score"]
