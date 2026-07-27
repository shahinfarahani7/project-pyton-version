from __future__ import annotations

from dataclasses import dataclass, field
from datetime import UTC, datetime
from typing import Any
from uuid import uuid4

from edgemint.billing.errors import finance_error
from edgemint.ledger.engine import compute_ledger
from edgemint.pricing.engine import PriceInput, PricingEngine
from edgemint.rewards.engine import compute_reward


@dataclass(frozen=True, slots=True)
class UsageEvent:
    task_id: str
    task_revision_id: str
    result_id: str
    verification_id: str
    quantity: int
    charge_micros: int
    reward_micros: int
    policy_version: str


@dataclass
class ReservationState:
    reservation_id: str
    task_id: str
    quote_id: str
    amount_micro_eur: int
    status: str
    released_micro_eur: int = 0


@dataclass(frozen=True, slots=True)
class InvoiceLine:
    line_id: str
    task_id: str
    description: str
    amount_micro_eur: int


@dataclass
class FinanceService:
    pricing_engine: PricingEngine = field(default_factory=PricingEngine)
    reservations: dict[str, ReservationState] = field(default_factory=dict)
    usage_events: list[UsageEvent] = field(default_factory=list)
    invoice_lines: list[InvoiceLine] = field(default_factory=list)
    ledger_postings: list[dict[str, Any]] = field(default_factory=list)
    reward_accruals: list[dict[str, Any]] = field(default_factory=list)
    processed_idempotency: set[str] = field(default_factory=set)
    reconciliation_runs: list[dict[str, Any]] = field(default_factory=list)

    def capture_reservation(
        self,
        *,
        task_id: str,
        quote_id: str,
        amount_micro_eur: int,
        available_micro_eur: int,
    ) -> ReservationState:
        if amount_micro_eur < 0:
            raise finance_error("INPUT_SCHEMA_INVALID", detail="negative reservation")
        active_total = sum(
            item.amount_micro_eur for item in self.reservations.values() if item.status == "active"
        )
        if available_micro_eur - active_total < amount_micro_eur:
            raise finance_error("INSUFFICIENT_CREDIT")
        reservation = ReservationState(
            reservation_id=f"res_{uuid4().hex[:16]}",
            task_id=task_id,
            quote_id=quote_id,
            amount_micro_eur=amount_micro_eur,
            status="active",
        )
        self.reservations[reservation.reservation_id] = reservation
        return reservation

    def release_reservation(self, *, task_id: str) -> int:
        released = 0
        for reservation in self.reservations.values():
            if reservation.task_id == task_id and reservation.status == "active":
                reservation.status = "released"
                reservation.released_micro_eur = reservation.amount_micro_eur
                released += reservation.amount_micro_eur
        return released

    def finalize_paid_task(
        self,
        *,
        idempotency_key: str,
        task_id: str,
        task_revision_id: str,
        result_id: str,
        verification_id: str,
        price_input: dict[str, Any],
        reward_input: dict[str, Any],
        refund_micros: int = 0,
    ) -> dict[str, Any]:
        if idempotency_key in self.processed_idempotency:
            raise finance_error("IDEMPOTENCY_CONFLICT")
        price = self.pricing_engine.quote(PriceInput.from_vector(price_input))
        reward = compute_reward(reward_input)
        entries, ledger_expected = compute_ledger(
            {
                "chargeMicros": price.charge_micros,
                "rewardMicros": reward["rewardMicros"],
                "refundMicros": refund_micros,
            }
        )
        reserved = sum(
            item.amount_micro_eur
            for item in self.reservations.values()
            if item.task_id == task_id and item.status == "active"
        )
        charged = price.charge_micros
        released = max(0, reserved - charged)
        for reservation in self.reservations.values():
            if reservation.task_id == task_id and reservation.status == "active":
                reservation.released_micro_eur = max(0, reservation.amount_micro_eur - charged)
                reservation.status = "settled"
        if reserved > 0 and reserved != charged + released:
            raise finance_error(
                "RECONCILIATION_MISMATCH",
                detail=f"reserved={reserved} charged={charged} released={released}",
            )

        usage = UsageEvent(
            task_id=task_id,
            task_revision_id=task_revision_id,
            result_id=result_id,
            verification_id=verification_id,
            quantity=int(price_input["quantity"]),
            charge_micros=charged,
            reward_micros=int(reward["rewardMicros"]),
            policy_version=price.policy_version,
        )
        self.usage_events.append(usage)
        line = InvoiceLine(
            line_id=f"inv_{uuid4().hex[:16]}",
            task_id=task_id,
            description=f"task:{task_id}",
            amount_micro_eur=charged,
        )
        self.invoice_lines.append(line)
        posting = {
            "postingId": f"post_{uuid4().hex[:16]}",
            "taskId": task_id,
            "taskRevisionId": task_revision_id,
            "resultId": result_id,
            "verificationId": verification_id,
            "entries": entries,
            "ledgerExpected": ledger_expected,
            "traceability": {
                "pricePolicy": price.policy_version,
                "rewardPolicy": "worker-reward-v2@2.0.0",
            },
        }
        self.ledger_postings.append(posting)
        accrual = {
            "accrualId": f"rac_{uuid4().hex[:16]}",
            "workerRewardMicros": reward["rewardMicros"],
            "holdHours": reward["holdHours"],
            "status": "held" if reward["eligible"] else "zero",
            "taskId": task_id,
            "resultId": result_id,
        }
        self.reward_accruals.append(accrual)
        self.processed_idempotency.add(idempotency_key)
        return {
            "usage": usage,
            "invoiceLine": line,
            "posting": posting,
            "rewardAccrual": accrual,
            "reservedMicros": reserved,
            "chargedMicros": charged,
            "releasedMicros": released,
        }

    def reverse_reward(self, *, accrual_id: str, reason: str) -> dict[str, Any]:
        for accrual in self.reward_accruals:
            if accrual["accrualId"] != accrual_id:
                continue
            if accrual["status"] == "reversed":
                raise finance_error("IDEMPOTENCY_CONFLICT")
            accrual["status"] = "reversed"
            accrual["reverseReason"] = reason
            return accrual
        raise finance_error("TENANT_RESOURCE_NOT_FOUND", detail="accrual not found")

    def expire_reward_hold(self, *, accrual_id: str) -> dict[str, Any]:
        for accrual in self.reward_accruals:
            if accrual["accrualId"] != accrual_id:
                continue
            accrual["status"] = "expired"
            return accrual
        raise finance_error("TENANT_RESOURCE_NOT_FOUND", detail="accrual not found")

    def run_daily_reconciliation(self) -> dict[str, Any]:
        captured_total = sum(item.amount_micro_eur for item in self.reservations.values())
        active_total = sum(
            item.amount_micro_eur for item in self.reservations.values() if item.status == "active"
        )
        charged_total = sum(item.charge_micros for item in self.usage_events)
        released_total = sum(item.released_micro_eur for item in self.reservations.values())
        unexplained = captured_total - active_total - charged_total - released_total
        report = {
            "runId": f"rec_{uuid4().hex[:16]}",
            "generatedAt": datetime.now(UTC).isoformat(),
            "reservedMicros": active_total,
            "capturedMicros": captured_total,
            "chargedMicros": charged_total,
            "releasedMicros": released_total,
            "unexplainedDifferenceMicros": unexplained,
            "balanced": unexplained == 0,
            "ledgerPostings": len(self.ledger_postings),
            "rewardAccruals": len(self.reward_accruals),
        }
        self.reconciliation_runs.append(report)
        return report

    def financial_close_report(self) -> dict[str, Any]:
        reconciliation = self.run_daily_reconciliation()
        return {
            "closeId": f"close_{uuid4().hex[:16]}",
            "generatedAt": datetime.now(UTC).isoformat(),
            "invoiceLineCount": len(self.invoice_lines),
            "totalInvoicedMicros": sum(line.amount_micro_eur for line in self.invoice_lines),
            "totalRewardMicros": sum(item["workerRewardMicros"] for item in self.reward_accruals),
            "reconciliation": reconciliation,
            "immutableEvidence": True,
        }
