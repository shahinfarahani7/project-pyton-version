from __future__ import annotations

import asyncio
import inspect
from dataclasses import replace
from datetime import UTC, datetime, timedelta
from pathlib import Path
from uuid import UUID, uuid4

import pytest
from edgemint.contribution.boost import (
    BOOST_ALREADY_ACTIVE,
    BOOST_PRICE_NOT_CONFIGURED,
    TOKEN_DEBIT_FAILED,
    TOKEN_WALLET_UNAVAILABLE,
    Boost,
    ContributionError,
    TokenDebitReceipt,
)
from edgemint.contribution.engine import (
    TIME_COMPONENT_AVAILABLE,
    TIME_COMPONENT_UNAVAILABLE,
    compute_task_xp,
    format_centi_xp,
    level_progress,
)
from edgemint.contribution.policy import ContributionPolicy, load_contribution_policy
from edgemint.contribution.service import AcceptedRun, ContributionService, XpAwardRecord

T0 = datetime(2026, 7, 1, 12, 0, tzinfo=UTC)
DEVICE = UUID("00000000-0000-7000-8000-000000000001")
WORKER = UUID("00000000-0000-7000-8000-000000000002")


def _policy(price: int | None = None) -> ContributionPolicy:
    base = load_contribution_policy()
    return replace(base, boost=replace(base.boost, price_token_minor_units=price))


class MemoryRepository:
    def __init__(self) -> None:
        self.runs: list[AcceptedRun] = []
        self.award_rows: dict[UUID, XpAwardRecord] = {}
        self.boost_rows: dict[UUID, Boost] = {}
        self.fail_for: set[UUID] = set()
        self.lock_calls = 0

    async def unscored_accepted_runs(self, worker_device_id: UUID) -> list[AcceptedRun]:
        return [
            run
            for run in self.runs
            if run.worker_device_id == worker_device_id and run.task_run_id not in self.award_rows
        ]

    async def boosts(self, worker_device_id: UUID) -> list[Boost]:
        return [item for item in self.boost_rows.values() if item.worker_device_id == worker_device_id]

    async def record_award(self, award: XpAwardRecord, *, consumed_boost: Boost | None) -> bool:
        if award.task_run_id in self.fail_for:
            raise RuntimeError("scoring storage failure")
        if award.task_run_id in self.award_rows:
            return False
        self.award_rows[award.task_run_id] = award
        if consumed_boost is not None:
            self.boost_rows[consumed_boost.boost_id] = consumed_boost
        return True

    async def awards(self, worker_device_id: UUID) -> list[XpAwardRecord]:
        return [item for item in self.award_rows.values() if item.worker_device_id == worker_device_id]

    async def lock_boosts(self, worker_device_id: UUID) -> None:
        self.lock_calls += 1

    async def boost_by_idempotency_key(self, worker_device_id: UUID, key: str) -> Boost | None:
        return next(
            (
                item
                for item in self.boost_rows.values()
                if item.worker_device_id == worker_device_id and item.idempotency_key == key
            ),
            None,
        )

    async def insert_boost(self, boost: Boost) -> bool:
        if await self.boost_by_idempotency_key(boost.worker_device_id, boost.idempotency_key):
            return False
        self.boost_rows[boost.boost_id] = boost
        return True


class FakeWallet:
    def __init__(self, *, commit: bool = True, raises: bool = False) -> None:
        self.commit = commit
        self.raises = raises
        self.debits: dict[str, TokenDebitReceipt] = {}
        self.calls = 0

    @property
    def available(self) -> bool:
        return True

    async def debit(
        self, *, worker_id: UUID, amount_minor_units: int, idempotency_key: str
    ) -> TokenDebitReceipt:
        self.calls += 1
        if self.raises:
            raise ContributionError(TOKEN_DEBIT_FAILED, 402)
        if idempotency_key not in self.debits:
            self.debits[idempotency_key] = TokenDebitReceipt(
                receipt_id=f"debit-{len(self.debits) + 1}",
                amount_minor_units=amount_minor_units,
                committed=self.commit,
            )
        return self.debits[idempotency_key]


def _buy(service: ContributionService, key: str, now: datetime) -> tuple[Boost, bool]:
    return asyncio.run(
        service.purchase_boost(worker_id=WORKER, worker_device_id=DEVICE, idempotency_key=key, now=now)
    )


def _run(
    *,
    task_type: str = "text.summarize",
    assigned: datetime = T0,
    started: datetime | None = T0 + timedelta(minutes=1),
    minutes: float = 2,
    device: UUID = DEVICE,
) -> AcceptedRun:
    completed = (started or assigned) + timedelta(minutes=minutes)
    return AcceptedRun(
        task_run_id=uuid4(),
        result_candidate_id=uuid4(),
        worker_device_id=device,
        task_type=task_type,
        assigned_at=assigned,
        started_at=started,
        completed_at=completed,
    )


def _boost(*, activated: datetime = T0, used: int = 0) -> Boost:
    return Boost(
        boost_id=uuid4(),
        worker_device_id=DEVICE,
        idempotency_key=f"seed-{uuid4().hex}",
        debit_receipt_id=f"seed-debit-{uuid4().hex}",
        bonus_bps=2500,
        activated_at=activated,
        expires_at=activated + timedelta(hours=24),
        task_quota=50,
        tasks_used=used,
    )


# --- levels -----------------------------------------------------------------


@pytest.mark.parametrize(
    ("centi_xp", "level", "next_level"),
    [
        (0, "bronze", "silver"),
        (49_999, "bronze", "silver"),
        (50_000, "silver", "gold"),
        (199_999, "silver", "gold"),
        (200_000, "gold", "platinum"),
        (599_999, "gold", "platinum"),
        (600_000, "platinum", None),
        (10_000_000, "platinum", None),
    ],
)
def test_level_boundaries_are_exact(centi_xp: int, level: str, next_level: str | None) -> None:
    progress = level_progress(load_contribution_policy(), centi_xp)
    assert progress.level_id == level
    assert progress.next_level_id == next_level


def test_progress_is_measured_between_current_and_next_threshold() -> None:
    policy = load_contribution_policy()
    silver_mid = level_progress(policy, 125_000)
    assert silver_mid.current_min_centi_xp == 50_000
    assert silver_mid.next_min_centi_xp == 200_000
    assert silver_mid.progress_bps == 5_000
    assert silver_mid.remaining_centi_xp == 75_000
    platinum = level_progress(policy, 600_000)
    assert platinum.progress_bps == 10_000
    assert platinum.remaining_centi_xp is None


def test_level_thresholds_are_configurable() -> None:
    document = {
        "metadata": {"name": "custom", "version": "1.0.0"},
        "spec": {
            "baseXp": 10,
            "xpPerAcceptedMinute": 2,
            "processingCapsMs": [],
            "levels": [
                {"id": "bronze", "minXp": 0},
                {"id": "silver", "minXp": 10},
                {"id": "gold", "minXp": 20},
                {"id": "platinum", "minXp": 30},
            ],
            "boost": {"bonusBps": 2500, "durationHours": 24, "taskQuota": 50, "priceTokenMinorUnits": None},
        },
    }
    policy = ContributionPolicy.from_document(document)
    assert level_progress(policy, 2_999).level_id == "gold"
    assert level_progress(policy, 3_000).level_id == "platinum"
    document["spec"]["levels"][2]["minXp"] = 10
    with pytest.raises(ValueError):
        ContributionPolicy.from_document(document)


# --- XP formula ---------------------------------------------------------------


def test_xp_is_base_plus_two_per_accepted_minute() -> None:
    award = compute_task_xp(load_contribution_policy(), task_type="text.summarize", processing_ms=150_000)
    assert award.centi_xp == 1_500
    assert award.accepted_processing_ms == 150_000
    assert award.time_component == TIME_COMPONENT_AVAILABLE


def test_processing_time_is_capped_per_task_type() -> None:
    policy = load_contribution_policy()
    assert policy.cap_ms_for("text.summarize") == 180_000
    capped = compute_task_xp(policy, task_type="text.summarize", processing_ms=3_600_000)
    assert capped.accepted_processing_ms == 180_000
    assert capped.centi_xp == 1_600


def test_xp_rounds_half_up_to_hundredths_with_integers_only() -> None:
    policy = load_contribution_policy()
    # 2 XP/min * 75 ms = 0.0025 XP -> 10.0025 -> 10.00 ; 225 ms -> 10.0075 -> 10.01
    assert compute_task_xp(policy, task_type="text.summarize", processing_ms=75).centi_xp == 1_000
    assert compute_task_xp(policy, task_type="text.summarize", processing_ms=150).centi_xp == 1_001
    assert compute_task_xp(policy, task_type="text.summarize", processing_ms=225).centi_xp == 1_001
    assert format_centi_xp(1_001) == "10.01"


def test_boost_adds_twenty_five_percent_with_single_rounding() -> None:
    award = compute_task_xp(
        load_contribution_policy(), task_type="text.summarize", processing_ms=150_000, boost_bonus_bps=2_500
    )
    assert award.centi_xp == 1_875
    assert award.boost_applied


@pytest.mark.parametrize("processing_ms", [None, -1])
def test_missing_or_invalid_time_records_base_only(processing_ms: int | None) -> None:
    policy = load_contribution_policy()
    award = compute_task_xp(policy, task_type="text.summarize", processing_ms=processing_ms)
    assert award.centi_xp == 1_000
    assert award.accepted_processing_ms is None
    assert award.time_component == TIME_COMPONENT_UNAVAILABLE


def test_task_type_without_cap_records_base_only() -> None:
    award = compute_task_xp(load_contribution_policy(), task_type="text.direct", processing_ms=120_000)
    assert award.centi_xp == 1_000
    assert award.time_component == TIME_COMPONENT_UNAVAILABLE


def test_engine_has_no_float_arithmetic() -> None:
    import ast

    import edgemint.contribution.engine as engine

    tree = ast.parse(inspect.getsource(engine))
    for node in ast.walk(tree):
        assert not isinstance(node, ast.Div), "true division produces floats"
        assert not (isinstance(node, ast.Constant) and isinstance(node.value, float))
        assert not (isinstance(node, ast.Name) and node.id in {"float", "Decimal"})


# --- scoring ------------------------------------------------------------------


def test_scoring_awards_accepted_runs_and_is_idempotent() -> None:
    repo = MemoryRepository()
    run = _run(minutes=2.5)
    repo.runs.append(run)
    service = ContributionService(repository=repo, policy=_policy())

    first = asyncio.run(service.summary(DEVICE, now=T0 + timedelta(hours=1)))
    second = asyncio.run(service.summary(DEVICE, now=T0 + timedelta(hours=2)))

    assert first["totalCentiXp"] == 1_500
    assert second["totalCentiXp"] == 1_500
    assert second["verifiedTaskCount"] == 1
    assert second["acceptedProcessingMs"] == 150_000
    assert len(repo.award_rows) == 1


def test_duplicate_award_insert_does_not_double_count() -> None:
    repo = MemoryRepository()
    run = _run()
    repo.runs.extend([run, run])
    service = ContributionService(repository=repo, policy=_policy())
    asyncio.run(service.score_pending(DEVICE))
    assert len(repo.award_rows) == 1


def test_rejected_or_unaccepted_results_never_reach_scoring() -> None:
    from edgemint.contribution import sql_repository

    source = inspect.getsource(sql_repository.SqlContributionRepository.unscored_accepted_runs)
    assert "candidate.status = 'accepted'" in source
    assert "public.reward_entitlements" in source
    assert "run.status IN ('succeeded', 'partial_succeeded')" in source
    assert "assignment.status = 'completed'" in source
    assert "candidate.worker_device_id = :worker_device_id" in source

    repo = MemoryRepository()
    service = ContributionService(repository=repo, policy=_policy())
    summary = asyncio.run(service.summary(DEVICE, now=T0))
    assert summary["totalCentiXp"] == 0
    assert summary["verifiedTaskCount"] == 0
    assert summary["acceptedProcessingMs"] is None


def test_xp_goes_only_to_the_owning_device() -> None:
    repo = MemoryRepository()
    other = UUID("00000000-0000-7000-8000-0000000000ff")
    repo.runs.append(_run(device=other))
    service = ContributionService(repository=repo, policy=_policy())
    assert asyncio.run(service.summary(DEVICE, now=T0))["totalCentiXp"] == 0
    assert asyncio.run(service.summary(other, now=T0))["totalCentiXp"] == 1_400


def test_queue_wait_before_start_earns_nothing() -> None:
    repo = MemoryRepository()
    repo.runs.append(_run(assigned=T0, started=T0 + timedelta(minutes=30), minutes=1))
    service = ContributionService(repository=repo, policy=_policy())
    summary = asyncio.run(service.summary(DEVICE, now=T0 + timedelta(hours=1)))
    assert summary["acceptedProcessingMs"] == 60_000
    assert summary["totalCentiXp"] == 1_200


def test_run_without_start_time_records_unavailable_time() -> None:
    repo = MemoryRepository()
    repo.runs.append(_run(started=None))
    service = ContributionService(repository=repo, policy=_policy())
    summary = asyncio.run(service.summary(DEVICE, now=T0 + timedelta(hours=1)))
    assert summary["totalCentiXp"] == 1_000
    assert summary["acceptedProcessingMs"] is None
    award = next(iter(repo.award_rows.values()))
    assert award.time_component == TIME_COMPONENT_UNAVAILABLE


def test_scoring_failure_is_isolated_and_reported_as_degraded() -> None:
    repo = MemoryRepository()
    bad, good = _run(), _run()
    repo.runs.extend([bad, good])
    repo.fail_for.add(bad.task_run_id)
    service = ContributionService(repository=repo, policy=_policy())
    summary = asyncio.run(service.summary(DEVICE, now=T0 + timedelta(hours=1)))
    assert summary["scoringStatus"] == "degraded"
    assert summary["verifiedTaskCount"] == 1
    repo.fail_for.clear()
    assert asyncio.run(service.summary(DEVICE, now=T0 + timedelta(hours=1)))["scoringStatus"] == "ok"


def test_task_execution_path_does_not_depend_on_contribution_scoring() -> None:
    root = Path(__file__).resolve().parents[2] / "edgemint"
    execution_paths = (
        "workers/assignments.py",
        "results/result_acceptance.py",
        "routing",
        "billing",
        "rewards",
    )
    for relative in execution_paths:
        target = root / relative
        files = [target] if target.is_file() else sorted(target.rglob("*.py"))
        for path in files:
            assert "edgemint.contribution" not in path.read_text(encoding="utf-8"), path


# --- boost eligibility ----------------------------------------------------------


def test_boost_applies_to_tasks_accepted_after_activation_and_completed_before_expiry() -> None:
    repo = MemoryRepository()
    boost = _boost(activated=T0)
    repo.boost_rows[boost.boost_id] = boost
    before = _run(assigned=T0 - timedelta(minutes=1), started=T0, minutes=2)
    inside = _run(assigned=T0 + timedelta(minutes=5), started=T0 + timedelta(minutes=6), minutes=2.5)
    late = T0 + timedelta(hours=23, minutes=59)
    after = _run(assigned=late, started=late, minutes=2)
    repo.runs.extend([before, inside, after])
    service = ContributionService(repository=repo, policy=_policy())
    asyncio.run(service.score_pending(DEVICE))

    assert repo.award_rows[before.task_run_id].boost_id is None
    assert repo.award_rows[inside.task_run_id].boost_id == boost.boost_id
    assert repo.award_rows[inside.task_run_id].centi_xp == 1_875
    assert repo.award_rows[after.task_run_id].boost_id is None
    assert repo.boost_rows[boost.boost_id].tasks_used == 1


def test_boost_eligibility_ignores_late_event_processing() -> None:
    repo = MemoryRepository()
    boost = _boost(activated=T0)
    repo.boost_rows[boost.boost_id] = boost
    run = _run(assigned=T0 + timedelta(hours=1), started=T0 + timedelta(hours=1), minutes=2)
    repo.runs.append(run)
    service = ContributionService(repository=repo, policy=_policy())
    summary = asyncio.run(service.summary(DEVICE, now=T0 + timedelta(days=3)))
    assert repo.award_rows[run.task_run_id].boost_id == boost.boost_id
    assert summary["boost"]["active"] is False


def test_boost_quota_ends_after_fifty_successful_tasks() -> None:
    repo = MemoryRepository()
    boost = _boost(activated=T0, used=49)
    repo.boost_rows[boost.boost_id] = boost
    last, extra = (
        _run(assigned=T0 + timedelta(minutes=1), started=T0 + timedelta(minutes=1), minutes=1),
        _run(assigned=T0 + timedelta(minutes=2), started=T0 + timedelta(minutes=3), minutes=1),
    )
    repo.runs.extend([last, extra])
    service = ContributionService(repository=repo, policy=_policy())
    summary = asyncio.run(service.summary(DEVICE, now=T0 + timedelta(hours=1)))
    assert repo.award_rows[last.task_run_id].boost_id == boost.boost_id
    assert repo.award_rows[extra.task_run_id].boost_id is None
    assert repo.boost_rows[boost.boost_id].tasks_used == 50
    assert summary["boost"]["active"] is False


def test_failed_tasks_do_not_consume_boost_quota() -> None:
    repo = MemoryRepository()
    boost = _boost(activated=T0)
    repo.boost_rows[boost.boost_id] = boost
    service = ContributionService(repository=repo, policy=_policy())
    summary = asyncio.run(service.summary(DEVICE, now=T0 + timedelta(hours=1)))
    assert summary["boost"] == {
        "active": True,
        "bonusBps": 2500,
        "expiresAt": boost.expires_at.isoformat(),
        "remainingTasks": 50,
    }


def test_boost_expires_after_twenty_four_hours() -> None:
    boost = _boost(activated=T0)
    assert boost.is_active(T0 + timedelta(hours=23, minutes=59))
    assert not boost.is_active(T0 + timedelta(hours=24))


# --- boost purchase -------------------------------------------------------------


def test_purchase_disabled_without_price() -> None:
    repo = MemoryRepository()
    wallet = FakeWallet()
    service = ContributionService(repository=repo, policy=_policy(price=None), wallet=wallet)
    with pytest.raises(ContributionError) as caught:
        _buy(service, "k-0001", T0)
    assert caught.value.code == BOOST_PRICE_NOT_CONFIGURED
    assert wallet.calls == 0
    summary = asyncio.run(service.summary(DEVICE, now=T0))
    assert summary["boostPurchase"]["enabled"] is False
    assert summary["boostPurchase"]["blockedReason"] == BOOST_PRICE_NOT_CONFIGURED


def test_production_wallet_is_unavailable_and_blocks_purchase() -> None:
    repo = MemoryRepository()
    service = ContributionService(repository=repo, policy=_policy(price=500))
    with pytest.raises(ContributionError) as caught:
        _buy(service, "k-0001", T0)
    assert caught.value.code == TOKEN_WALLET_UNAVAILABLE
    assert repo.boost_rows == {}


def test_shipped_policy_keeps_purchase_disabled() -> None:
    summary = asyncio.run(ContributionService(repository=MemoryRepository()).summary(DEVICE, now=T0))
    assert summary["boostPurchase"]["enabled"] is False
    assert summary["boostPurchase"]["priceTokenMinorUnits"] is None


def test_purchase_activates_only_after_committed_debit_and_replays_without_second_debit() -> None:
    repo = MemoryRepository()
    wallet = FakeWallet()
    service = ContributionService(repository=repo, policy=_policy(price=500), wallet=wallet)
    boost, replayed = _buy(service, "k-0001", T0)
    again, replayed_again = _buy(service, "k-0001", T0)
    assert not replayed and replayed_again
    assert again.boost_id == boost.boost_id
    assert wallet.calls == 1
    assert len(repo.boost_rows) == 1
    assert boost.expires_at == T0 + timedelta(hours=24)
    assert boost.debit_receipt_id == "debit-1"
    assert repo.lock_calls == 2


def test_second_boost_while_active_is_rejected_before_debit() -> None:
    repo = MemoryRepository()
    wallet = FakeWallet()
    service = ContributionService(repository=repo, policy=_policy(price=500), wallet=wallet)
    _buy(service, "k-0001", T0)
    with pytest.raises(ContributionError) as caught:
        _buy(service, "k-0002", T0 + timedelta(hours=1))
    assert caught.value.code == BOOST_ALREADY_ACTIVE
    assert wallet.calls == 1
    assert len(repo.boost_rows) == 1


@pytest.mark.parametrize("wallet", [FakeWallet(commit=False), FakeWallet(raises=True)])
def test_failed_debit_never_activates_boost(wallet: FakeWallet) -> None:
    repo = MemoryRepository()
    service = ContributionService(repository=repo, policy=_policy(price=500), wallet=wallet)
    with pytest.raises(ContributionError) as caught:
        _buy(service, "k-0001", T0)
    assert caught.value.code == TOKEN_DEBIT_FAILED
    assert repo.boost_rows == {}


def test_buying_a_boost_does_not_change_past_xp() -> None:
    repo = MemoryRepository()
    run = _run(assigned=T0, started=T0, minutes=2)
    repo.runs.append(run)
    service = ContributionService(repository=repo, policy=_policy(price=500), wallet=FakeWallet())
    before = asyncio.run(service.summary(DEVICE, now=T0 + timedelta(minutes=5)))["totalCentiXp"]
    _buy(service, "k-0001", T0 + timedelta(minutes=6))
    after = asyncio.run(service.summary(DEVICE, now=T0 + timedelta(minutes=7)))["totalCentiXp"]
    assert before == after == 1_400
