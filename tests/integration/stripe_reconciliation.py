from __future__ import annotations

import json
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "src" / "backend"))

from edgemint.claims.service import ClaimPayoutService  # noqa: E402
from edgemint.payments.errors import PaymentProviderError  # noqa: E402
from edgemint.payments.service import PaymentProviderService  # noqa: E402
from edgemint.payments.webhook import compute_stripe_signature  # noqa: E402


def contract_checks() -> list[str]:
    errors: list[str] = []
    billing_src = (ROOT / "src/backend/edgemint/services/billing.py").read_text(encoding="utf-8")
    claim_src = (ROOT / "src/backend/edgemint/services/claim.py").read_text(encoding="utf-8")
    for route in [
        '"/internal/billing/stripe/credit:fund"',
        '"/internal/billing/stripe/webhooks:ingest"',
        '"/internal/billing/stripe/reconciliation:provider"',
        '"/internal/claims/batches:submit"',
        '"/internal/claims/payouts:recover"',
    ]:
        if route not in billing_src and route not in claim_src:
            errors.append(f"missing stripe route {route}")
    if "sk_live" in billing_src or "sk_live" in claim_src:
        errors.append("live stripe key must not appear in source")
    return errors


def semantic_checks() -> list[str]:
    errors: list[str] = []
    payments = PaymentProviderService()
    funded = payments.fund_customer_credit(
        customer_id="cus_int",
        amount_micro_eur=3_000_000,
        idempotency_key="idem-int-fund",
    )
    if funded["taxEvidenceId"] is None:
        errors.append("tax evidence missing on credit funding")

    secret = "whsec_integration_fixture"
    payload = json.dumps(
        {"id": "evt_int_1", "type": "invoice.paid", "data": {"object": {"amount": 0}}}
    ).encode("utf-8")
    ts = int(time.time())
    signature = compute_stripe_signature(secret=secret, payload=payload, timestamp=ts)
    duplicate = payments.ingest_webhook(
        payload=payload,
        signature_header=signature,
        webhook_secret=secret,
        now_epoch=ts,
    )
    replay = payments.ingest_webhook(
        payload=payload,
        signature_header=signature,
        webhook_secret=secret,
        now_epoch=ts,
    )
    if duplicate["status"] != "accepted" or replay["status"] != "duplicate_ignored":
        errors.append("webhook reorder/idempotency failed")

    try:
        payments.onboard_worker(
            worker_id="wrk_bad",
            country_code="IR",
            idempotency_key="idem-int-country",
        )
        errors.append("unsupported country should fail closed")
    except PaymentProviderError as exc:
        if exc.code != "COUNTRY_NOT_SUPPORTED":
            errors.append("unexpected country failure code")

    claims = ClaimPayoutService(payments=payments)
    batch = claims.submit_claim_batch(
        batch_id="batch_int",
        idempotency_key="idem-int-batch",
        claims=[
            {
                "workerId": "wrk_ok",
                "verifiedRewardMicros": 120_000_000,
                "kycApproved": True,
                "sanctionsClear": True,
                "jurisdictionAllowed": True,
                "fraudHold": False,
                "destinationVerified": True,
            }
        ],
    )
    if batch["transferCount"] != 1:
        errors.append("payout batch transfer count mismatch")

    try:
        payments.reconcile_provider_ledger()
    except PaymentProviderError:
        errors.append("provider reconciliation should balance after controlled funding")
    return errors


def main() -> int:
    errors = contract_checks() + semantic_checks()
    if errors:
        for item in errors:
            print(item)
        return 1
    print("stripe reconciliation integration checks passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
