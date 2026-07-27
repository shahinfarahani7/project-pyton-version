from __future__ import annotations

import pytest
from edgemint.billing.errors import FinanceServiceError
from edgemint.billing.service import FinanceService
from edgemint.ledger.engine import compute_ledger
from edgemint.pricing.engine import PriceInput
from edgemint.rewards.engine import compute_reward

PRICE_INPUT = {
    "taskType": "document.ocr",
    "quantity": 100,
    "plan": "startup",
    "priority": "standard",
    "verification": "standard",
    "region": "eu-central",
    "executionPolicy": "edge_only",
    "retention": "default",
}

REWARD_INPUT = {
    "taskType": "document.ocr",
    "quanta": 1,
    "tier": "T2",
    "qualityMilli": 950,
    "urgency": "standard",
    "scarcityBps": 10000,
    "reliabilityBps": 10000,
}


def test_reward_engine_matches_vector_expectation() -> None:
    expected = {
        "caseId": "REWARD-sample",
        "input": REWARD_INPUT,
    }
    result = compute_reward(expected["input"])
    assert result["eligible"] is True
    assert result["rewardMicros"] > 0
    assert result["unit"] == "EUR_REWARD_MICROS"


def test_ledger_entries_are_balanced() -> None:
    entries, expected = compute_ledger({"chargeMicros": 1000, "rewardMicros": 200, "refundMicros": 50})
    assert expected["balancedByCurrency"] is True
    assert len(entries) == 6


def test_duplicate_finalize_is_idempotent_conflict() -> None:
    service = FinanceService()
    price = service.pricing_engine.quote(PriceInput.from_vector(PRICE_INPUT))
    service.capture_reservation(
        task_id="tsk_fin",
        quote_id="qte_fin",
        amount_micro_eur=price.charge_micros,
        available_micro_eur=price.charge_micros,
    )
    service.finalize_paid_task(
        idempotency_key="idem-1",
        task_id="tsk_fin",
        task_revision_id="rev_fin",
        result_id="res_fin",
        verification_id="ver_fin",
        price_input=PRICE_INPUT,
        reward_input=REWARD_INPUT,
    )
    with pytest.raises(FinanceServiceError) as exc:
        service.finalize_paid_task(
            idempotency_key="idem-1",
            task_id="tsk_fin",
            task_revision_id="rev_fin",
            result_id="res_fin",
            verification_id="ver_fin",
            price_input=PRICE_INPUT,
            reward_input=REWARD_INPUT,
        )
    assert exc.value.code == "IDEMPOTENCY_CONFLICT"


def test_paid_task_finalization_posts_balanced_ledger() -> None:
    service = FinanceService()
    price = service.pricing_engine.quote(PriceInput.from_vector(PRICE_INPUT))
    service.capture_reservation(
        task_id="tsk_fin2",
        quote_id="qte_fin2",
        amount_micro_eur=price.charge_micros,
        available_micro_eur=price.charge_micros,
    )
    body = service.finalize_paid_task(
        idempotency_key="idem-2",
        task_id="tsk_fin2",
        task_revision_id="rev_fin2",
        result_id="res_fin2",
        verification_id="ver_fin2",
        price_input=PRICE_INPUT,
        reward_input=REWARD_INPUT,
    )
    assert body["posting"]["ledgerExpected"]["balancedByCurrency"] is True
    assert body["rewardAccrual"]["status"] == "held"


def test_daily_reconciliation_zero_unexplained_difference() -> None:
    service = FinanceService()
    price = service.pricing_engine.quote(PriceInput.from_vector(PRICE_INPUT))
    service.capture_reservation(
        task_id="tsk_rec",
        quote_id="qte_rec",
        amount_micro_eur=price.charge_micros,
        available_micro_eur=price.charge_micros,
    )
    service.finalize_paid_task(
        idempotency_key="idem-rec",
        task_id="tsk_rec",
        task_revision_id="rev_rec",
        result_id="res_rec",
        verification_id="ver_rec",
        price_input=PRICE_INPUT,
        reward_input=REWARD_INPUT,
    )
    report = service.run_daily_reconciliation()
    assert report["balanced"] is True
    assert report["unexplainedDifferenceMicros"] == 0


def test_reward_reversal_and_expiry() -> None:
    service = FinanceService()
    price = service.pricing_engine.quote(PriceInput.from_vector(PRICE_INPUT))
    service.capture_reservation(
        task_id="tsk_rev",
        quote_id="qte_rev",
        amount_micro_eur=price.charge_micros,
        available_micro_eur=price.charge_micros,
    )
    body = service.finalize_paid_task(
        idempotency_key="idem-rev",
        task_id="tsk_rev",
        task_revision_id="rev_rev",
        result_id="res_rev",
        verification_id="ver_rev",
        price_input=PRICE_INPUT,
        reward_input=REWARD_INPUT,
    )
    accrual_id = body["rewardAccrual"]["accrualId"]
    reversed_accrual = service.reverse_reward(accrual_id=accrual_id, reason="dispute")
    assert reversed_accrual["status"] == "reversed"
