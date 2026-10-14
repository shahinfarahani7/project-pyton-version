from __future__ import annotations

import logging
from dataclasses import dataclass
from datetime import datetime
from typing import Any, Protocol
from uuid import UUID, uuid4

from edgemint.contribution.boost import (
    BOOST_ALREADY_ACTIVE,
    BOOST_PRICE_NOT_CONFIGURED,
    TOKEN_DEBIT_FAILED,
    TOKEN_WALLET_UNAVAILABLE,
    Boost,
    ContributionError,
    ContributorTokenWallet,
    UnavailableContributorTokenWallet,
    new_boost,
)
from edgemint.contribution.engine import (
    compute_task_xp,
    format_centi_xp,
    level_progress,
)
from edgemint.contribution.policy import ContributionPolicy, load_contribution_policy

logger = logging.getLogger(__name__)


@dataclass(frozen=True, slots=True)
class AcceptedRun:
    """An accepted result candidate with a reward entitlement, read from server records."""

    task_run_id: UUID
    result_candidate_id: UUID
    worker_device_id: UUID
    task_type: str
    assigned_at: datetime
    started_at: datetime | None
    completed_at: datetime

    def processing_ms(self) -> int | None:
        if self.started_at is None or self.completed_at < self.started_at:
            return None
        delta = self.completed_at - self.started_at
        return (delta.days * 86_400 + delta.seconds) * 1000 + delta.microseconds // 1000


@dataclass(frozen=True, slots=True)
class XpAwardRecord:
    task_run_id: UUID
    result_candidate_id: UUID
    worker_device_id: UUID
    task_type: str
    centi_xp: int
    accepted_processing_ms: int | None
    time_component: str
    boost_id: UUID | None
    policy_version: str


class ContributionRepository(Protocol):
    async def unscored_accepted_runs(self, worker_device_id: UUID) -> list[AcceptedRun]: ...

    async def boosts(self, worker_device_id: UUID) -> list[Boost]: ...

    async def record_award(self, award: XpAwardRecord, *, consumed_boost: Boost | None) -> bool:
        """Insert once per task run and, in the same transaction, store the consumed boost slot."""
        ...

    async def awards(self, worker_device_id: UUID) -> list[XpAwardRecord]: ...

    async def lock_boosts(self, worker_device_id: UUID) -> None:
        """Serialize boost purchases per device until the surrounding transaction ends."""
        ...

    async def boost_by_idempotency_key(self, worker_device_id: UUID, key: str) -> Boost | None: ...

    async def insert_boost(self, boost: Boost) -> bool: ...


@dataclass
class ContributionService:
    repository: ContributionRepository
    policy: ContributionPolicy | None = None
    wallet: ContributorTokenWallet | None = None

    def __post_init__(self) -> None:
        if self.policy is None:
            self.policy = load_contribution_policy()
        if self.wallet is None:
            self.wallet = UnavailableContributorTokenWallet()

    @property
    def _policy(self) -> ContributionPolicy:
        assert self.policy is not None
        return self.policy

    async def score_pending(self, worker_device_id: UUID) -> int:
        """Award XP for accepted runs not yet scored. Returns the number of runs that failed to score."""
        runs = sorted(
            await self.repository.unscored_accepted_runs(worker_device_id),
            key=lambda run: (run.completed_at, str(run.task_run_id)),
        )
        failures = 0
        for run in runs:
            try:
                await self._score_run(run)
            except Exception:
                failures += 1
                logger.exception("contribution XP scoring failed for task run %s", run.task_run_id)
        return failures

    async def _score_run(self, run: AcceptedRun) -> None:
        boost = next(
            (
                item
                for item in await self.repository.boosts(run.worker_device_id)
                if item.covers(assigned_at=run.assigned_at, completed_at=run.completed_at)
            ),
            None,
        )
        xp = compute_task_xp(
            self._policy,
            task_type=run.task_type,
            processing_ms=run.processing_ms(),
            boost_bonus_bps=boost.bonus_bps if boost else None,
        )
        await self.repository.record_award(
            XpAwardRecord(
                task_run_id=run.task_run_id,
                result_candidate_id=run.result_candidate_id,
                worker_device_id=run.worker_device_id,
                task_type=run.task_type,
                centi_xp=xp.centi_xp,
                accepted_processing_ms=xp.accepted_processing_ms,
                time_component=xp.time_component,
                boost_id=boost.boost_id if boost else None,
                policy_version=self._policy.version_label,
            ),
            consumed_boost=boost.consume_one() if boost else None,
        )

    def purchase_block_reason(self) -> str | None:
        if self._policy.boost.price_token_minor_units is None:
            return BOOST_PRICE_NOT_CONFIGURED
        assert self.wallet is not None
        if not self.wallet.available:
            return TOKEN_WALLET_UNAVAILABLE
        return None

    async def purchase_boost(
        self,
        *,
        worker_id: UUID,
        worker_device_id: UUID,
        idempotency_key: str,
        now: datetime,
    ) -> tuple[Boost, bool]:
        """Returns (boost, replayed). Activation happens only after a committed token debit."""
        await self.repository.lock_boosts(worker_device_id)
        existing = await self.repository.boost_by_idempotency_key(worker_device_id, idempotency_key)
        if existing is not None:
            return existing, True
        reason = self.purchase_block_reason()
        if reason is not None:
            raise ContributionError(reason, 409 if reason == BOOST_PRICE_NOT_CONFIGURED else 503)
        if any(item.is_active(now) for item in await self.repository.boosts(worker_device_id)):
            raise ContributionError(BOOST_ALREADY_ACTIVE, 409)
        terms = self._policy.boost
        assert self.wallet is not None and terms.price_token_minor_units is not None
        receipt = await self.wallet.debit(
            worker_id=worker_id,
            amount_minor_units=terms.price_token_minor_units,
            idempotency_key=f"contribution-boost:{worker_device_id}:{idempotency_key}",
        )
        if not receipt.committed or receipt.amount_minor_units != terms.price_token_minor_units:
            raise ContributionError(TOKEN_DEBIT_FAILED, 402)
        boost = new_boost(
            boost_id=uuid4(),
            worker_device_id=worker_device_id,
            idempotency_key=idempotency_key,
            debit_receipt_id=receipt.receipt_id,
            bonus_bps=terms.bonus_bps,
            duration_hours=terms.duration_hours,
            task_quota=terms.task_quota,
            activated_at=now,
        )
        if not await self.repository.insert_boost(boost):
            replay = await self.repository.boost_by_idempotency_key(worker_device_id, idempotency_key)
            if replay is None:
                raise ContributionError(TOKEN_DEBIT_FAILED, 402, detail="boost activation conflict")
            return replay, True
        return boost, False

    async def summary(self, worker_device_id: UUID, *, now: datetime) -> dict[str, Any]:
        scoring_failures = 0
        try:
            scoring_failures = await self.score_pending(worker_device_id)
        except Exception:
            scoring_failures = -1
            logger.exception("contribution XP scoring unavailable for device %s", worker_device_id)
        awards = await self.repository.awards(worker_device_id)
        total = sum(item.centi_xp for item in awards)
        timed = [item.accepted_processing_ms for item in awards if item.accepted_processing_ms is not None]
        progress = level_progress(self._policy, total)
        boosts = await self.repository.boosts(worker_device_id)
        active = next((item for item in boosts if item.is_active(now)), None)
        terms = self._policy.boost
        block_reason = self.purchase_block_reason()
        return {
            "policyVersion": self._policy.version_label,
            "level": progress.level_id,
            "nextLevel": progress.next_level_id,
            "totalCentiXp": total,
            "totalXp": format_centi_xp(total),
            "currentLevelMinCentiXp": progress.current_min_centi_xp,
            "nextLevelMinCentiXp": progress.next_min_centi_xp,
            "remainingCentiXp": progress.remaining_centi_xp,
            "progressBps": progress.progress_bps,
            "verifiedTaskCount": len(awards),
            "acceptedProcessingMs": sum(timed) if timed else None,
            "boost": {
                "active": active is not None,
                "bonusBps": terms.bonus_bps,
                "expiresAt": active.expires_at.isoformat() if active else None,
                "remainingTasks": active.remaining_tasks() if active else None,
            },
            "boostPurchase": {
                "enabled": block_reason is None and active is None,
                "blockedReason": block_reason or (BOOST_ALREADY_ACTIVE if active else None),
                "priceTokenMinorUnits": terms.price_token_minor_units,
                "durationHours": terms.duration_hours,
                "taskQuota": terms.task_quota,
            },
            "scoringStatus": "ok" if scoring_failures == 0 else "degraded",
        }
