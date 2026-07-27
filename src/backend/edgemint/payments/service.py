from __future__ import annotations

import json
from dataclasses import dataclass, field
from datetime import UTC, datetime
from typing import Any
from uuid import uuid4

from edgemint.payments.adapters.stripe.sandbox import StripeSandboxAdapter
from edgemint.payments.errors import payment_error
from edgemint.payments.idempotency import IdempotencyStore
from edgemint.payments.policy import country_allows_payout
from edgemint.payments.webhook import verify_stripe_webhook


@dataclass
class PaymentProviderService:
    adapter: StripeSandboxAdapter = field(default_factory=StripeSandboxAdapter)
    idempotency: IdempotencyStore = field(default_factory=IdempotencyStore)
    internal_ledger_micro_eur: int = 0
    webhook_events: list[dict[str, Any]] = field(default_factory=list)
    kyc_holds: set[str] = field(default_factory=set)

    def fund_customer_credit(
        self,
        *,
        customer_id: str,
        amount_micro_eur: int,
        idempotency_key: str,
    ) -> dict[str, Any]:
        cached = self.idempotency.get(idempotency_key)
        if cached is not None:
            return cached
        self.idempotency.begin(idempotency_key)
        result = self.adapter.fund_customer_credit(
            customer_id=customer_id,
            amount_micro_eur=amount_micro_eur,
            idempotency_key=idempotency_key,
        )
        self.internal_ledger_micro_eur += amount_micro_eur
        body = {
            "providerReference": result.provider_reference,
            "amountMicroEur": result.amount_micro_eur,
            "taxEvidenceId": result.tax_evidence_id,
        }
        return self.idempotency.complete(idempotency_key, body)

    def onboard_worker(
        self,
        *,
        worker_id: str,
        country_code: str,
        idempotency_key: str,
        sanctions_clear: bool = True,
        kyc_complete: bool = True,
    ) -> dict[str, Any]:
        if worker_id in self.kyc_holds:
            raise payment_error("KYC_INCOMPLETE")
        if not sanctions_clear:
            self.kyc_holds.add(worker_id)
            raise payment_error("SANCTIONS_HOLD")
        if not kyc_complete:
            raise payment_error("KYC_INCOMPLETE")
        if not country_allows_payout(country_code):
            raise payment_error("COUNTRY_NOT_SUPPORTED", detail=country_code)
        cached = self.idempotency.get(idempotency_key)
        if cached is not None:
            return cached
        self.idempotency.begin(idempotency_key)
        result = self.adapter.verify_worker_identity(
            worker_id=worker_id,
            country_code=country_code,
            idempotency_key=idempotency_key,
        )
        body = {
            "connectAccountId": result.connect_account_id,
            "kycStatus": result.kyc_status,
            "payoutsEnabled": result.payouts_enabled,
        }
        return self.idempotency.complete(idempotency_key, body)

    def submit_payout_batch(
        self,
        *,
        batch_id: str,
        transfers: list[dict[str, Any]],
        idempotency_key: str,
    ) -> dict[str, Any]:
        cached = self.idempotency.get(idempotency_key)
        if cached is not None:
            return cached
        self.idempotency.begin(idempotency_key)
        result = self.adapter.create_payout_batch(
            batch_id=batch_id,
            transfers=transfers,
            idempotency_key=idempotency_key,
        )
        body = {
            "batchId": result.batch_id,
            "transferCount": result.transfer_count,
            "totalMicroEur": result.total_micro_eur,
            "status": result.status,
        }
        return self.idempotency.complete(idempotency_key, body)

    def recover_failed_payout(self, *, payout_id: str, idempotency_key: str) -> dict[str, Any]:
        cached = self.idempotency.get(idempotency_key)
        if cached is not None:
            return cached
        self.idempotency.begin(idempotency_key)
        body = self.adapter.retry_failed_payout(payout_id=payout_id, idempotency_key=idempotency_key)
        return self.idempotency.complete(idempotency_key, body)

    def ingest_webhook(
        self,
        *,
        payload: bytes,
        signature_header: str,
        webhook_secret: str,
        now_epoch: int | None = None,
    ) -> dict[str, Any]:
        if not verify_stripe_webhook(
            payload=payload,
            signature_header=signature_header,
            secret=webhook_secret,
            now_epoch=now_epoch,
        ):
            raise payment_error("WEBHOOK_SIGNATURE_INVALID")
        event = json.loads(payload.decode("utf-8"))
        event_id = str(event["id"])
        if not self.idempotency.register_event(event_id):
            return {"status": "duplicate_ignored", "eventId": event_id}
        self.webhook_events.append(event)
        if event.get("type") == "payment_intent.succeeded":
            amount = int(event["data"]["object"]["amount"])
            self.internal_ledger_micro_eur += amount
        return {"status": "accepted", "eventId": event_id, "type": event.get("type")}

    def reconcile_provider_ledger(self) -> dict[str, Any]:
        provider_total = self.adapter.provider_balance_micro_eur()
        unexplained = provider_total - self.internal_ledger_micro_eur
        balanced = unexplained == 0
        if not balanced:
            raise payment_error(
                "PROVIDER_RECONCILIATION_MISMATCH",
                detail=f"provider={provider_total} internal={self.internal_ledger_micro_eur}",
            )
        return {
            "reconciliationId": f"rec_{uuid4().hex[:16]}",
            "generatedAt": datetime.now(UTC).isoformat(),
            "providerMicroEur": provider_total,
            "internalMicroEur": self.internal_ledger_micro_eur,
            "balanced": balanced,
        }
