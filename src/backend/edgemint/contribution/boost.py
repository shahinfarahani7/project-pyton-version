from __future__ import annotations

from dataclasses import dataclass, replace
from datetime import datetime, timedelta
from typing import Protocol
from uuid import UUID


class ContributionError(Exception):
    __slots__ = ("code", "detail", "status")

    def __init__(self, code: str, status: int, detail: str | None = None) -> None:
        super().__init__(code)
        self.code = code
        self.status = status
        self.detail = detail


BOOST_PRICE_NOT_CONFIGURED = "BOOST_PRICE_NOT_CONFIGURED"
TOKEN_WALLET_UNAVAILABLE = "TOKEN_WALLET_UNAVAILABLE"  # noqa: S105 - error code, not a secret
TOKEN_DEBIT_FAILED = "TOKEN_DEBIT_FAILED"  # noqa: S105 - error code, not a secret
BOOST_ALREADY_ACTIVE = "BOOST_ALREADY_ACTIVE"


@dataclass(frozen=True, slots=True)
class TokenDebitReceipt:
    receipt_id: str
    amount_minor_units: int
    committed: bool


class ContributorTokenWallet(Protocol):
    """Debits contributor tokens. Never customer EUR credit."""

    @property
    def available(self) -> bool: ...

    async def debit(
        self,
        *,
        worker_id: UUID,
        amount_minor_units: int,
        idempotency_key: str,
    ) -> TokenDebitReceipt: ...


class UnavailableContributorTokenWallet:
    """Contributor tokens are disabled in GA1 (canonical-decisions spec.token.enabled=false)."""

    @property
    def available(self) -> bool:
        return False

    async def debit(
        self,
        *,
        worker_id: UUID,
        amount_minor_units: int,
        idempotency_key: str,
    ) -> TokenDebitReceipt:
        raise ContributionError(TOKEN_WALLET_UNAVAILABLE, 503)


@dataclass(frozen=True, slots=True)
class Boost:
    boost_id: UUID
    worker_device_id: UUID
    idempotency_key: str
    debit_receipt_id: str
    bonus_bps: int
    activated_at: datetime
    expires_at: datetime
    task_quota: int
    tasks_used: int

    def is_active(self, now: datetime) -> bool:
        return now < self.expires_at and self.tasks_used < self.task_quota

    def remaining_tasks(self) -> int:
        return max(0, self.task_quota - self.tasks_used)

    def covers(self, *, assigned_at: datetime, completed_at: datetime) -> bool:
        """Eligibility uses server assignment/completion times, never the scoring time."""
        return (
            self.activated_at <= assigned_at
            and completed_at < self.expires_at
            and self.tasks_used < self.task_quota
        )

    def consume_one(self) -> Boost:
        return replace(self, tasks_used=self.tasks_used + 1)


def new_boost(
    *,
    boost_id: UUID,
    worker_device_id: UUID,
    idempotency_key: str,
    debit_receipt_id: str,
    bonus_bps: int,
    duration_hours: int,
    task_quota: int,
    activated_at: datetime,
) -> Boost:
    return Boost(
        boost_id=boost_id,
        worker_device_id=worker_device_id,
        idempotency_key=idempotency_key,
        debit_receipt_id=debit_receipt_id,
        bonus_bps=bonus_bps,
        activated_at=activated_at,
        expires_at=activated_at + timedelta(hours=duration_hours),
        task_quota=task_quota,
        tasks_used=0,
    )
