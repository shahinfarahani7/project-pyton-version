from __future__ import annotations

from edgemint.routing.scoring_features import compute_model_locality_bps
from edgemint.routing.service import RouterService


def _base_input(**overrides: object) -> dict[str, object]:
    base: dict[str, object] = {
        "featuresBps": {
            "modelLocality": 0,
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
        "requiredModelIds": ["mdv_qwen2_5_0_5b"],
    }
    base.update(overrides)
    return base


def test_loaded_model_scores_higher_than_installed() -> None:
    loaded = compute_model_locality_bps(
        required_model_ids=["mdv_qwen2_5_0_5b"],
        loaded_model_ids=["mdv_qwen2_5_0_5b"],
    )
    installed = compute_model_locality_bps(
        required_model_ids=["mdv_qwen2_5_0_5b"],
        installed_model_ids=["mdv_qwen2_5_0_5b"],
    )
    cold = compute_model_locality_bps(required_model_ids=["mdv_qwen2_5_0_5b"])
    assert loaded == 10000
    assert installed == 8500
    assert cold == 0
    assert loaded > installed > cold


def test_rank_workers_prefers_resident_model_over_cold_worker() -> None:
    service = RouterService()
    ranked = service.rank_workers(
        task_id="tsk_locality",
        router_epoch=9,
        candidates=[
            {
                "workerId": "wrk_cold",
                "input": _base_input(
                    loadedModelIds=[],
                    installedModelIds=[],
                ),
            },
            {
                "workerId": "wrk_loaded",
                "input": _base_input(
                    loadedModelIds=["mdv_qwen2_5_0_5b"],
                    installedModelIds=["mdv_qwen2_5_0_5b"],
                ),
            },
            {
                "workerId": "wrk_installed",
                "input": _base_input(
                    loadedModelIds=[],
                    installedModelIds=["mdv_qwen2_5_0_5b"],
                ),
            },
        ],
    )
    eligible = [row for row in ranked if row["eligible"]]
    assert [row["workerId"] for row in eligible] == [
        "wrk_loaded",
        "wrk_installed",
        "wrk_cold",
    ]
    assert eligible[0]["featuresBps"]["modelLocality"] == 10000
    assert eligible[1]["featuresBps"]["modelLocality"] == 8500
    assert eligible[2]["featuresBps"]["modelLocality"] == 0


def test_tie_break_uses_hmac_when_locality_and_score_match() -> None:
    service = RouterService()
    ranked = service.rank_workers(
        task_id="tsk_tie",
        router_epoch=1,
        candidates=[
            {
                "workerId": "wrk_b",
                "input": _base_input(
                    loadedModelIds=["mdv_qwen2_5_0_5b"],
                    installedModelIds=["mdv_qwen2_5_0_5b"],
                ),
            },
            {
                "workerId": "wrk_a",
                "input": _base_input(
                    loadedModelIds=["mdv_qwen2_5_0_5b"],
                    installedModelIds=["mdv_qwen2_5_0_5b"],
                ),
            },
        ],
    )
    assert ranked[0]["score"] == ranked[1]["score"]
    assert ranked[0]["tieBreakDigest"] != ranked[1]["tieBreakDigest"]
    assert ranked[0]["workerId"] != ranked[1]["workerId"]
