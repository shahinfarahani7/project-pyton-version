from __future__ import annotations

from edgemint.routing.scarcity_cost import compute_scarcity_fragmentation_bps
from edgemint.routing.service import RouterService


GOLDEN_VECTORS = [
    {
        "name": "cheap_task_on_idle_t4",
        "task_cost_units": 10,
        "device_tier": "T4",
        "effective_cpu_units": 100,
        "reserved_cpu_units": 0,
        "requested_cpu_units": 10,
        "expected_bps": 9100,
    },
    {
        "name": "heavy_task_on_t4",
        "task_cost_units": 80,
        "device_tier": "T4",
        "effective_cpu_units": 100,
        "reserved_cpu_units": 0,
        "requested_cpu_units": 80,
        "expected_bps": 8400,
    },
    {
        "name": "cheap_task_on_t1",
        "task_cost_units": 10,
        "device_tier": "T1",
        "effective_cpu_units": 40,
        "reserved_cpu_units": 0,
        "requested_cpu_units": 10,
        "expected_bps": 10000,
    },
]


def test_golden_scarcity_vectors() -> None:
    for vector in GOLDEN_VECTORS:
        actual = compute_scarcity_fragmentation_bps(
            task_cost_units=vector["task_cost_units"],
            device_tier=vector["device_tier"],
            effective_cpu_units=vector["effective_cpu_units"],
            reserved_cpu_units=vector["reserved_cpu_units"],
            requested_cpu_units=vector["requested_cpu_units"],
        )
        assert actual == vector["expected_bps"], vector["name"]


def test_rank_workers_penalizes_cheap_task_on_premium_worker() -> None:
    service = RouterService()
    base = {
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
        "requestedTotals": {"cpuUnits": 10, "memoryBytes": 1_000_000_000, "storageBytes": 100_000_000},
        "taskCostUnits": 10,
    }
    ranked = service.rank_workers(
        task_id="tsk_scarcity",
        router_epoch=4,
        candidates=[
            {"workerId": "wrk_t4", "input": {**base, "deviceTier": "T4"}},
            {"workerId": "wrk_t1", "input": {**base, "deviceTier": "T1", "effectiveBudgets": {"cpuUnits": 40, "memoryBytes": 8_000_000_000, "storageBytes": 4_000_000_000}}},
        ],
    )
    by_id = {row["workerId"]: row for row in ranked if row["eligible"]}
    assert by_id["wrk_t1"]["featuresBps"]["scarcityCost"] > by_id["wrk_t4"]["featuresBps"]["scarcityCost"]
