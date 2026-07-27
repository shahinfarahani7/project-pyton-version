from __future__ import annotations

import json
from pathlib import Path

import pytest
from edgemint.pricing.engine import PriceInput, PricingEngine, PricingRejectedError, compute_price
from edgemint.pricing.money import apply_bps, ceil_div
from edgemint.pricing.policy import load_price_policy


def test_apply_bps_half_up() -> None:
    assert apply_bps(2500, 11500) == 2875
    assert apply_bps(2875, 7000) == 2013


def test_ceil_div_quantum() -> None:
    assert ceil_div(1, 1000) == 1
    assert ceil_div(1001, 1000) == 2


def test_engine_matches_first_vector_case() -> None:
    raw = {
        "taskType": "document.ocr",
        "quantity": 1,
        "plan": "developer",
        "priority": "batch",
        "verification": "standard",
        "region": "eu-north",
        "executionPolicy": "edge_only",
        "retention": "default",
    }
    expected = {
        "baseMicros": 2500,
        "beforeMinimumMicros": 2215,
        "chargeMicros": 2500,
        "minimumApplied": True,
        "currency": "EUR",
        "steps": [
            {"modifier": "plan", "value": "developer", "bps": 11500, "runningMicros": 2875},
            {"modifier": "priority", "value": "batch", "bps": 7000, "runningMicros": 2013},
            {"modifier": "verification", "value": "standard", "bps": 10000, "runningMicros": 2013},
            {"modifier": "region", "value": "eu-north", "bps": 10000, "runningMicros": 2013},
            {"modifier": "executionPolicy", "value": "edge_only", "bps": 11000, "runningMicros": 2215},
            {"modifier": "retention", "value": "default", "bps": 10000, "runningMicros": 2215},
        ],
    }
    assert compute_price(raw) == expected


def test_rejects_negative_quantity() -> None:
    engine = PricingEngine(load_price_policy())
    with pytest.raises(ValueError):
        engine.quote(
            PriceInput(
                task_type="document.ocr",
                quantity=0,
                plan="developer",
                priority="batch",
                verification="standard",
                region="eu-north",
                execution_policy="edge_only",
                retention="default",
            )
        )


def test_margin_floor_rejects_without_subsidy() -> None:
    engine = PricingEngine(load_price_policy())
    with pytest.raises(PricingRejectedError) as exc:
        engine.quote(
            PriceInput(
                task_type="document.ocr",
                quantity=1,
                plan="enterprise",
                priority="batch",
                verification="standard",
                region="eu-north",
                execution_policy="edge_only",
                retention="default",
                expected_cost_micros=10_000_000,
                stressed_cost_micros=10_000_000,
            )
        )
    assert exc.value.code == "NEGATIVE_MARGIN_FLOOR"


def test_production_engine_matches_oracle_sample() -> None:
    root = Path(__file__).resolve().parents[4]
    vector_path = root / "tests" / "vectors" / "pricing-vectors.jsonl"
    with vector_path.open(encoding="utf-8") as handle:
        for index, line in enumerate(handle):
            if index >= 100:
                break
            case = json.loads(line)
            assert compute_price(case["input"]) == case["expected"]
