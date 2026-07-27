from __future__ import annotations

from dataclasses import dataclass
from typing import Protocol


@dataclass(frozen=True, slots=True)
class CreditFundingResult:
    provider_reference: str
    amount_micro_eur: int
    tax_evidence_id: str | None


@dataclass(frozen=True, slots=True)
class TaxEvidence:
    evidence_id: str
    jurisdiction: str
    amount_micro_eur: int
    tax_micro_eur: int


@dataclass(frozen=True, slots=True)
class WorkerOnboardingResult:
    connect_account_id: str
    kyc_status: str
    payouts_enabled: bool


@dataclass(frozen=True, slots=True)
class PayoutBatchResult:
    batch_id: str
    transfer_count: int
    total_micro_eur: int
    status: str


class BillingPort(Protocol):
    def fund_customer_credit(
        self, *, customer_id: str, amount_micro_eur: int, idempotency_key: str
    ) -> CreditFundingResult: ...


class TaxPort(Protocol):
    def calculate_and_store_evidence(
        self, *, jurisdiction: str, amount_micro_eur: int, idempotency_key: str
    ) -> TaxEvidence: ...


class IdentityPort(Protocol):
    def verify_worker_identity(
        self, *, worker_id: str, country_code: str, idempotency_key: str
    ) -> WorkerOnboardingResult: ...


class ConnectPort(Protocol):
    def create_payout_batch(
        self, *, batch_id: str, transfers: list[dict], idempotency_key: str
    ) -> PayoutBatchResult: ...

    def retry_failed_payout(self, *, payout_id: str, idempotency_key: str) -> dict: ...
