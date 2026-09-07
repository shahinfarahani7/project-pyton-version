from __future__ import annotations

from datetime import UTC, datetime, timedelta

import pytest

from edgemint.routing.engine import evaluate_candidate
from edgemint.routing.hard_eligibility import evaluate_hard_eligibility
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
        "freeStorageBytes": 20_000_000_000,
        "requiredFreeStorageBytes": 1_000_000_000,
        "cooldownActive": False,
        "assignmentSafetyBlocked": False,
        "workerRuntimeClasses": ["mediapipe_llm", "system"],
        "taskRuntimeClass": "mediapipe_llm",
        "deviceTier": "T4",
    }
    base.update(overrides)
    return base


@pytest.mark.parametrize(
    ("override", "expected_reason"),
    [
        ({"heartbeatAgeSeconds": 999}, "STALE_HEARTBEAT"),
        ({"available": False}, "WORKER_UNAVAILABLE"),
        ({"featuresBps": {**_candidate()["featuresBps"], "trust": 0}}, "TRUST_TOO_LOW"),
        ({"attested": False}, "ATTESTATION_REQUIRED"),
        ({"consentCurrent": False}, "CONSENT_REQUIRED"),
        (
            {"requireCpuEnforcementCertification": True, "cpuEnforcementCertified": False},
            "CPU_ENFORCEMENT_UNCERTIFIED",
        ),
        ({"batteryPercent": 10}, "BATTERY_TOO_LOW"),
        ({"thermalState": "critical"}, "THERMAL_BLOCK"),
        ({"regionAllowed": False}, "REGION_NOT_ALLOWED"),
        ({"networkPolicyAllowed": False}, "NETWORK_POLICY_BLOCKED"),
        ({"modelDigestMatch": False}, "MODEL_DIGEST_MISMATCH"),
        ({"modelAvailable": False}, "MODEL_UNAVAILABLE"),
        ({"runtimeAbiMatch": False}, "RUNTIME_ABI_MISMATCH"),
        ({"freeStorageBytes": 100, "requiredFreeStorageBytes": 1_000_000_000}, "INSUFFICIENT_STORAGE"),
        ({"cooldownActive": True}, "FAILURE_COOLDOWN"),
        ({"assignmentSafetyBlocked": True}, "ASSIGNMENT_SAFETY_BLOCKED"),
        (
            {
                "workerRuntimeClasses": ["paddle_ocr"],
                "taskRuntimeClass": "mediapipe_llm",
            },
            "RUNTIME_INCOMPATIBLE",
        ),
    ],
)
def test_each_hard_eligibility_gate(override: dict[str, object], expected_reason: str) -> None:
    candidate = _candidate(**override)
    reasons = evaluate_hard_eligibility(candidate)
    assert expected_reason in reasons


def test_cooldown_until_blocks_until_expiry() -> None:
    future = datetime.now(UTC) + timedelta(minutes=5)
    reasons = evaluate_hard_eligibility(_candidate(cooldownUntilUtc=future.isoformat()))
    assert "FAILURE_COOLDOWN" in reasons

    past = datetime.now(UTC) - timedelta(minutes=5)
    reasons = evaluate_hard_eligibility(_candidate(cooldownUntilUtc=past.isoformat()))
    assert "FAILURE_COOLDOWN" not in reasons


def test_ineligible_workers_receive_zero_score() -> None:
    result = evaluate_candidate(_candidate(attested=False))
    assert result["eligible"] is False
    assert result["score"] == 0


def test_eligible_worker_is_scored() -> None:
    result = evaluate_candidate(_candidate())
    assert result["eligible"] is True
    assert result["score"] > 0


def test_rank_workers_places_ineligible_after_eligible_and_zero_score() -> None:
    service = RouterService()
    ranked = service.rank_workers(
        task_id="tsk_gate",
        router_epoch=3,
        candidates=[
            {
                "workerId": "wrk_bad",
                "input": _candidate(attested=False),
            },
            {
                "workerId": "wrk_good",
                "input": _candidate(),
            },
        ],
    )
    assert ranked[0]["workerId"] == "wrk_good"
    assert ranked[0]["eligible"] is True
    assert ranked[0]["score"] > 0
    assert ranked[1]["workerId"] == "wrk_bad"
    assert ranked[1]["eligible"] is False
    assert ranked[1]["score"] == 0


def test_apply_hard_eligibility_filter_partitions_candidates() -> None:
    service = RouterService()
    eligible, ineligible = service.apply_hard_eligibility_filter(
        [
            {"workerId": "wrk_ok", "input": _candidate()},
            {"workerId": "wrk_no", "input": _candidate(modelAvailable=False)},
        ]
    )
    assert [item["workerId"] for item in eligible] == ["wrk_ok"]
    assert ineligible[0]["workerId"] == "wrk_no"
    assert "MODEL_UNAVAILABLE" in ineligible[0]["ineligibilityReasons"]
