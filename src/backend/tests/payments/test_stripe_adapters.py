from __future__ import annotations

import json
import time

import pytest
from edgemint.claims.service import ClaimPayoutService, evaluate_claim_eligibility
from edgemint.payments.adapters.stripe.sandbox import StripeSandboxAdapter
from edgemint.payments.errors import PaymentProviderError
from edgemint.payments.service import PaymentProviderService
from edgemint.payments.webhook import compute_stripe_signature, verify_stripe_webhook


@pytest.fixture
def payments() -> PaymentProviderService:
    return PaymentProviderService()


def test_fund_customer_credit_is_idempotent(payments: PaymentProviderService) -> None:
    first = payments.fund_customer_credit(
        customer_id="cus_1",
        amount_micro_eur=1_000_000,
        idempotency_key="idem-fund-1",
    )
    second = payments.fund_customer_credit(
        customer_id="cus_1",
        amount_micro_eur=1_000_000,
        idempotency_key="idem-fund-1",
    )
    assert first == second
    with pytest.raises(PaymentProviderError) as exc:
        payments.idempotency.begin("idem-fund-1")
    assert exc.value.code == "IDEMPOTENCY_CONFLICT"


def test_unsupported_country_fails_closed(payments: PaymentProviderService) -> None:
    with pytest.raises(PaymentProviderError) as exc:
        payments.onboard_worker(
            worker_id="wrk_kp",
            country_code="KP",
            idempotency_key="idem-kp",
        )
    assert exc.value.code == "COUNTRY_NOT_SUPPORTED"


def test_incomplete_kyc_fails_closed(payments: PaymentProviderService) -> None:
    with pytest.raises(PaymentProviderError) as exc:
        payments.onboard_worker(
            worker_id="wrk_kyc",
            country_code="DE",
            idempotency_key="idem-kyc",
            kyc_complete=False,
        )
    assert exc.value.code == "KYC_INCOMPLETE"


def test_webhook_signature_and_duplicate_events(payments: PaymentProviderService) -> None:
    webhook_secret = "whsec_test_fixture"  # noqa: S105
    payload = json.dumps(
        {
            "id": "evt_123",
            "type": "payment_intent.succeeded",
            "data": {"object": {"amount": 500000}},
        }
    ).encode("utf-8")
    ts = int(time.time())
    signature = compute_stripe_signature(secret=webhook_secret, payload=payload, timestamp=ts)
    assert verify_stripe_webhook(
        payload=payload, signature_header=signature, secret=webhook_secret, now_epoch=ts
    )
    first = payments.ingest_webhook(
        payload=payload,
        signature_header=signature,
        webhook_secret=webhook_secret,
        now_epoch=ts,
    )
    second = payments.ingest_webhook(
        payload=payload,
        signature_header=signature,
        webhook_secret=webhook_secret,
        now_epoch=ts,
    )
    assert first["status"] == "accepted"
    assert second["status"] == "duplicate_ignored"


def test_provider_and_internal_ledger_reconcile(payments: PaymentProviderService) -> None:
    payments.fund_customer_credit(
        customer_id="cus_rec",
        amount_micro_eur=2_500_000,
        idempotency_key="idem-rec",
    )
    report = payments.reconcile_provider_ledger()
    assert report["balanced"] is True


def test_claim_batch_requires_eligibility() -> None:
    service = ClaimPayoutService()
    with pytest.raises(PaymentProviderError) as exc:
        service.submit_claim_batch(
            batch_id="batch_1",
            idempotency_key="idem-batch",
            claims=[
                {
                    "workerId": "wrk_1",
                    "verifiedRewardMicros": 150_000_000,
                    "kycApproved": False,
                    "sanctionsClear": True,
                    "jurisdictionAllowed": True,
                    "fraudHold": False,
                    "destinationVerified": True,
                }
            ],
        )
    assert exc.value.code == "KYC_INCOMPLETE"


def test_claim_batch_submits_payouts_for_eligible_workers() -> None:
    service = ClaimPayoutService()
    body = service.submit_claim_batch(
        batch_id="batch_2",
        idempotency_key="idem-batch-2",
        claims=[
            {
                "workerId": "wrk_2",
                "verifiedRewardMicros": 150_000_000,
                "kycApproved": True,
                "sanctionsClear": True,
                "jurisdictionAllowed": True,
                "fraudHold": False,
                "destinationVerified": True,
            }
        ],
    )
    assert body["status"] == "completed"
    assert body["totalMicroEur"] == 150_000_000


def test_failed_payout_recovery() -> None:
    service = ClaimPayoutService()
    service.payments.submit_payout_batch(
        batch_id="batch_3",
        transfers=[{"workerId": "wrk_3", "amountMicroEur": 100_000_000}],
        idempotency_key="idem-batch-3",
    )
    payout_id = next(iter(service.payments.adapter._payouts))
    service.payments.adapter.mark_payout_failed(payout_id)
    recovered = service.payments.recover_failed_payout(payout_id=payout_id, idempotency_key="idem-recover")
    assert recovered["status"] == "paid"


def test_evaluate_claim_eligibility_matches_vector_oracle_shape() -> None:
    result = evaluate_claim_eligibility(
        {
            "policyEnabled": True,
            "verifiedRewardMicros": 150_000_000,
            "kycApproved": True,
            "sanctionsClear": True,
            "jurisdictionAllowed": True,
            "fraudHold": False,
            "destinationVerified": True,
        }
    )
    assert result["eligible"] is True


def test_secret_resolution_uses_arn_env_not_source_keys() -> None:
    secret = StripeSandboxAdapter.resolve_secret_from_arn_env("STRIPE_WEBHOOK_SECRET_ARN")
    assert secret.startswith("whsec_")
    assert "sk_live" not in secret
