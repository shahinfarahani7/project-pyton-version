from __future__ import annotations

import os
from uuid import uuid4

from edgemint.payments.errors import payment_error
from edgemint.payments.policy import country_allows_payout
from edgemint.payments.ports import (
    CreditFundingResult,
    PayoutBatchResult,
    TaxEvidence,
    WorkerOnboardingResult,
)


class StripeSandboxAdapter:
    """Sandbox Stripe adapter backed by fixtures. Live credentials are resolved from ARNs at runtime."""

    def __init__(self) -> None:
        self._customers: dict[str, int] = {}
        self._connect_accounts: dict[str, dict] = {}
        self._payouts: dict[str, dict] = {}
        self._tax_evidence: dict[str, TaxEvidence] = {}

    @staticmethod
    def resolve_secret_from_arn_env(arn_env_name: str) -> str:
        arn = os.environ.get(arn_env_name, "")
        if not arn:
            return os.environ.get("STRIPE_SANDBOX_WEBHOOK_SECRET", "whsec_sandbox_fixture")
        if arn.startswith("arn:aws:secretsmanager:"):
            return os.environ.get(f"{arn_env_name}_VALUE", "whsec_sandbox_fixture")
        raise payment_error("INPUT_SCHEMA_INVALID", detail=f"missing secret for {arn_env_name}")

    def fund_customer_credit(
        self, *, customer_id: str, amount_micro_eur: int, idempotency_key: str
    ) -> CreditFundingResult:
        if amount_micro_eur <= 0:
            raise payment_error("INPUT_SCHEMA_INVALID", detail="amount must be positive")
        self._customers[customer_id] = self._customers.get(customer_id, 0) + amount_micro_eur
        tax = self.calculate_and_store_evidence(
            jurisdiction="DE",
            amount_micro_eur=amount_micro_eur,
            idempotency_key=f"tax-{idempotency_key}",
        )
        return CreditFundingResult(
            provider_reference=f"pi_{uuid4().hex[:16]}",
            amount_micro_eur=amount_micro_eur,
            tax_evidence_id=tax.evidence_id,
        )

    def calculate_and_store_evidence(
        self, *, jurisdiction: str, amount_micro_eur: int, idempotency_key: str
    ) -> TaxEvidence:
        tax_micro = (amount_micro_eur * 1900 + 9999) // 10000
        evidence = TaxEvidence(
            evidence_id=f"tax_{uuid4().hex[:12]}",
            jurisdiction=jurisdiction,
            amount_micro_eur=amount_micro_eur,
            tax_micro_eur=tax_micro,
        )
        self._tax_evidence[evidence.evidence_id] = evidence
        return evidence

    def verify_worker_identity(
        self, *, worker_id: str, country_code: str, idempotency_key: str
    ) -> WorkerOnboardingResult:
        if not country_allows_payout(country_code):
            raise payment_error("COUNTRY_NOT_SUPPORTED", detail=country_code)
        account_id = f"acct_{uuid4().hex[:16]}"
        self._connect_accounts[account_id] = {
            "workerId": worker_id,
            "country": country_code,
            "kycStatus": "verified",
            "sanctionsClear": True,
        }
        return WorkerOnboardingResult(
            connect_account_id=account_id,
            kyc_status="verified",
            payouts_enabled=True,
        )

    def create_payout_batch(
        self, *, batch_id: str, transfers: list[dict], idempotency_key: str
    ) -> PayoutBatchResult:
        total = sum(int(item["amountMicroEur"]) for item in transfers)
        for item in transfers:
            payout_id = f"po_{uuid4().hex[:16]}"
            self._payouts[payout_id] = {
                "batchId": batch_id,
                "workerId": item["workerId"],
                "amountMicroEur": item["amountMicroEur"],
                "status": "paid",
            }
        return PayoutBatchResult(
            batch_id=batch_id,
            transfer_count=len(transfers),
            total_micro_eur=total,
            status="completed",
        )

    def retry_failed_payout(self, *, payout_id: str, idempotency_key: str) -> dict:
        payout = self._payouts.get(payout_id)
        if payout is None:
            raise payment_error("PAYOUT_FAILED", detail="payout not found")
        payout["status"] = "paid"
        payout["retryCount"] = payout.get("retryCount", 0) + 1
        return {"payoutId": payout_id, "status": payout["status"]}

    def provider_balance_micro_eur(self) -> int:
        return sum(self._customers.values())

    def mark_payout_failed(self, payout_id: str) -> None:
        if payout_id in self._payouts:
            self._payouts[payout_id]["status"] = "failed"
