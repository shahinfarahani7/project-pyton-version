from __future__ import annotations

from uuid import UUID

import pytest

from edgemint.billing.errors import FinanceServiceError
from edgemint.billing.service import FinanceService
from edgemint.pricing.engine import PriceInput
from edgemint.results.entitlement_keys import (
    DEFAULT_ENTITLEMENT_COMPONENT,
    entitlement_business_key,
    evaluate_payload_idempotency,
    external_effect_key,
)
from edgemint.results.external_effects import ExternalEffectService, payload_digest
from edgemint.results.result_acceptance import ResultAcceptanceService

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


def test_entitlement_business_key_is_stable() -> None:
    workspace_id = UUID(int=10)
    task_run_id = UUID(int=20)
    key = entitlement_business_key(workspace_id=workspace_id, task_run_id=task_run_id)
    assert key == f"ent:{workspace_id}:{task_run_id}:{DEFAULT_ENTITLEMENT_COMPONENT}"
    assert (
        ResultAcceptanceService.expected_entitlement_receipt(
            workspace_id=workspace_id,
            task_run_id=task_run_id,
        )
        == key
    )


def test_external_effect_key_and_payload_digest() -> None:
    payload_a = {"amountMicroEur": 100, "workerId": "w1"}
    payload_b = {"workerId": "w1", "amountMicroEur": 100}
    digest = payload_digest(payload_a)
    assert digest == payload_digest(payload_b)
    assert external_effect_key(
        destination_type="payout_provider",
        destination_id="stripe",
        idempotency_key="pay-1",
    ) == "payout_provider|stripe|pay-1"


def test_payload_idempotency_replay_and_conflict() -> None:
    digest = payload_digest({"x": 1})
    assert evaluate_payload_idempotency(existing_digest=None, incoming_digest=digest) == "fresh"
    assert evaluate_payload_idempotency(existing_digest=digest, incoming_digest=digest) == "replay"
    assert (
        evaluate_payload_idempotency(existing_digest=digest, incoming_digest="other")
        == "conflict"
    )
    assert (
        ExternalEffectService.classify_replay(
            existing_digest=digest,
            incoming_payload={"x": 1},
        )
        == "replay"
    )


def test_finance_finalize_replays_same_idempotency_key() -> None:
    service = FinanceService()
    price = service.pricing_engine.quote(PriceInput.from_vector(PRICE_INPUT))
    service.capture_reservation(
        task_id="tsk_replay",
        quote_id="qte_replay",
        amount_micro_eur=price.charge_micros,
        available_micro_eur=price.charge_micros,
    )
    first = service.finalize_paid_task(
        idempotency_key="ent:ws:run:completion",
        task_id="tsk_replay",
        task_revision_id="rev_replay",
        result_id="res_replay",
        verification_id="ver_replay",
        price_input=PRICE_INPUT,
        reward_input=REWARD_INPUT,
    )
    replay = service.finalize_paid_task(
        idempotency_key="ent:ws:run:completion",
        task_id="tsk_replay",
        task_revision_id="rev_replay",
        result_id="res_replay_dup",
        verification_id="ver_replay_dup",
        price_input=PRICE_INPUT,
        reward_input=REWARD_INPUT,
        replay_on_duplicate=True,
    )
    assert replay["rewardAccrual"]["accrualId"] == first["rewardAccrual"]["accrualId"]
    assert len(service.reward_accruals) == 1


def test_finance_duplicate_without_replay_conflicts() -> None:
    service = FinanceService()
    price = service.pricing_engine.quote(PriceInput.from_vector(PRICE_INPUT))
    service.capture_reservation(
        task_id="tsk_conflict",
        quote_id="qte_conflict",
        amount_micro_eur=price.charge_micros,
        available_micro_eur=price.charge_micros,
    )
    service.finalize_paid_task(
        idempotency_key="idem-conflict",
        task_id="tsk_conflict",
        task_revision_id="rev_conflict",
        result_id="res_conflict",
        verification_id="ver_conflict",
        price_input=PRICE_INPUT,
        reward_input=REWARD_INPUT,
    )
    with pytest.raises(FinanceServiceError) as exc:
        service.finalize_paid_task(
            idempotency_key="idem-conflict",
            task_id="tsk_conflict",
            task_revision_id="rev_conflict",
            result_id="res_conflict_dup",
            verification_id="ver_conflict_dup",
            price_input=PRICE_INPUT,
            reward_input=REWARD_INPUT,
        )
    assert exc.value.code == "IDEMPOTENCY_CONFLICT"


def test_sql_migration_declares_uniqueness_constraints() -> None:
    from pathlib import Path

    migration = (
        Path(__file__).resolve().parents[4]
        / "database/sql/032_result_candidates_reward_entitlements.sql"
    ).read_text(encoding="utf-8")
    for token in (
        "UQ_result_candidates_run_digest",
        "UQ_reward_entitlement_business_key",
        "UQ_external_effect_dedup",
        "accept_task_run_with_entitlement",
        "record_external_effect_receipt",
    ):
        assert token in migration
