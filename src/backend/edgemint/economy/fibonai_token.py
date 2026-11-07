"""FibonAI token accounting from whitepaper v0.5.

Supply, yearly emission, and payout splits live here. Worker selection,
retries, and the EUR task ledger stay on their existing path.
"""

from __future__ import annotations

from dataclasses import dataclass
from decimal import ROUND_DOWN, Decimal, localcontext
from functools import lru_cache
from pathlib import Path
from typing import Any, Literal

import yaml

PayoutKind = Literal["full", "partial_pair", "none"]
_BPS = 10_000
_SERIES_TERMS = 600
_DECIMAL_PRECISION = 120


def _whole(name: str, value: object) -> int:
    if type(value) is not int:
        raise ValueError(f"{name}_MUST_BE_INT")
    return value


@dataclass(frozen=True, slots=True)
class FibonaiEconomy:
    max_supply: int
    atomic_units_per_token: int
    participant_pool: int
    investor_pool: int
    exponent_numerator: int
    exponent_denominator: int
    full_participant_pool_bps: int
    full_treasury_bps: int
    partial_each_bps: int
    partial_treasury_bps: int
    recycle_participant_bps: int
    recycle_treasury_bps: int
    minimum_ram_bytes: int
    minimum_free_storage_bytes: int
    monthly_free_request_cap: int | None
    series_first: int
    series_second: int
    base_task_atomic: int
    default_difficulty_grade: int

    @property
    def minting_disabled(self) -> bool:
        return True


@dataclass(frozen=True, slots=True)
class TaskPayout:
    paid_participants: int
    each_atomic: int
    treasury_atomic: int
    unreleased_atomic: int

    @property
    def participant_total_atomic(self) -> int:
        return self.paid_participants * self.each_atomic


@dataclass(frozen=True, slots=True)
class YearEndTreasury:
    participant_paid: int
    treasury_from_distribution: int
    unused_emission: int

    @property
    def treasury_total(self) -> int:
        return self.treasury_from_distribution + self.unused_emission


@dataclass(frozen=True, slots=True)
class TreasuryRecycle:
    to_participants: int
    retained: int


@dataclass(frozen=True, slots=True)
class AcceptedTaskQuote:
    """Charge and reward for one accepted task on the current single-result path.

    The requester pays ``difficulty * base``. The worker who completed the
    accepted result receives the participant pool (75 percent) and the treasury
    receives 25 percent. This does not add workers or change consensus.
    """

    difficulty_grade: int
    charge_atomic: int
    worker_reward_atomic: int
    treasury_atomic: int


def load_economy(root: Path | None = None) -> FibonaiEconomy:
    repo_root = root or Path(__file__).resolve().parents[4]
    path = repo_root / "dsl" / "economy" / "fibonai-token-v1.yaml"
    document = yaml.safe_load(path.read_text(encoding="utf-8"))
    if not isinstance(document, dict):
        raise ValueError("ECONOMY_POLICY_INVALID")
    spec = document.get("spec")
    if not isinstance(spec, dict):
        raise ValueError("ECONOMY_POLICY_INVALID")
    return _economy_from_spec(spec)


@lru_cache
def cached_economy() -> FibonaiEconomy:
    return load_economy()


def participant_emission(year: int, *, policy: FibonaiEconomy | None = None) -> int:
    active = policy or cached_economy()
    return emission_tokens(active.participant_pool, year, policy=active)


def investor_emission(year: int, *, policy: FibonaiEconomy | None = None) -> int:
    active = policy or cached_economy()
    return emission_tokens(active.investor_pool, year, policy=active)


def emission_tokens(pool_tokens: int, year: int, *, policy: FibonaiEconomy | None = None) -> int:
    """Whole tokens released in `year` from `pool_tokens`.

    Year n is weighted by G_n ** (-1/4). G starts 1, 2, 3, 5, ... so the
    schedule is strictly decreasing. The whitepaper rounds year 1 of the
    16 billion participant pool to about 1.88 billion.
    """
    active = policy or cached_economy()
    pool = _whole("pool", pool_tokens)
    index = _whole("year", year)
    if pool < 0 or index < 1:
        raise ValueError("NEGATIVE_INPUT")
    weights, total = _emission_weights(
        active.series_first,
        active.series_second,
        active.exponent_numerator,
        active.exponent_denominator,
    )
    if index > len(weights):
        return 0
    with localcontext() as ctx:
        ctx.prec = _DECIMAL_PRECISION
        issued = (weights[index - 1] / total * Decimal(pool)).to_integral_value(rounding=ROUND_DOWN)
    return int(issued)


def quote_accepted_task(
    grade: int | None = None,
    *,
    policy: FibonaiEconomy | None = None,
) -> AcceptedTaskQuote:
    active = policy or cached_economy()
    difficulty = active.default_difficulty_grade if grade is None else grade
    released = scale_by_difficulty(active.base_task_atomic, difficulty)
    worker_reward, treasury = scheduled_distribution(
        released,
        participant_bps=active.full_participant_pool_bps,
    )
    return AcceptedTaskQuote(difficulty, released, worker_reward, treasury)


def scale_by_difficulty(base_amount: int, grade: int) -> int:
    """Whitepaper grade K multiplies both the charge and the token release."""
    base = _whole("base", base_amount)
    difficulty = _whole("grade", grade)
    if base < 0 or difficulty < 1:
        raise ValueError("NEGATIVE_INPUT")
    return base * difficulty


def split_released(
    released_atomic: int,
    outcome: PayoutKind,
    agreeing: int,
    *,
    policy: FibonaiEconomy | None = None,
) -> TaskPayout:
    """Split one task release. Remainder atomic units stay with the treasury."""
    active = policy or cached_economy()
    released = _whole("released", released_atomic)
    agreed = _whole("agreeing", agreeing)
    if released < 0 or agreed < 0:
        raise ValueError("NEGATIVE_INPUT")
    if outcome == "none":
        return TaskPayout(0, 0, 0, released)
    if outcome == "partial_pair":
        if agreed != 2:
            raise ValueError("PARTIAL_PAIR_REQUIRES_TWO")
        each = released * active.partial_each_bps // _BPS
        paid = each * agreed
        return TaskPayout(agreed, each, released - paid, 0)
    if outcome == "full":
        if agreed < 3:
            raise ValueError("FULL_CONSENSUS_REQUIRES_THREE")
        each = released * active.full_participant_pool_bps // (_BPS * agreed)
        paid = each * agreed
        return TaskPayout(agreed, each, released - paid, 0)
    raise ValueError("UNKNOWN_PAYOUT")


def year_end_treasury(
    annual_emission: int,
    *,
    participant_paid: int,
    treasury_paid: int,
) -> YearEndTreasury:
    """Move this year's unreleased emission into the treasury. No new tokens."""
    annual = _whole("annual", annual_emission)
    participants = _whole("participants", participant_paid)
    treasury = _whole("treasury", treasury_paid)
    if annual < 0 or participants < 0 or treasury < 0:
        raise ValueError("NEGATIVE_INPUT")
    consumed = participants + treasury
    if consumed > annual:
        raise ValueError("OVER_SUBSCRIBED")
    return YearEndTreasury(participants, treasury, annual - consumed)


def scheduled_distribution(gross: int, *, participant_bps: int) -> tuple[int, int]:
    """Split a gross release. The remainder above the participant pool goes to treasury."""
    amount = _whole("gross", gross)
    bps = _whole("participant_bps", participant_bps)
    if amount < 0 or bps < 0 or bps > _BPS:
        raise ValueError("NEGATIVE_INPUT")
    participants = amount * bps // _BPS
    return participants, amount - participants


def recycle_treasury(
    balance: int,
    *,
    vote_accepted: bool,
    policy: FibonaiEconomy | None = None,
) -> TreasuryRecycle:
    """One accepted vote returns 75% of this balance to participants and keeps 25%."""
    active = policy or cached_economy()
    amount = _whole("balance", balance)
    if amount < 0:
        raise ValueError("NEGATIVE_INPUT")
    if not vote_accepted:
        return TreasuryRecycle(0, amount)
    to_participants = amount * active.recycle_participant_bps // _BPS
    return TreasuryRecycle(to_participants, amount - to_participants)


def _economy_from_spec(spec: dict[str, Any]) -> FibonaiEconomy:
    token = _mapping(spec, "token")
    allocations = _mapping(spec, "allocations")
    emission = _mapping(spec, "emission")
    series = _mapping(emission, "series")
    distribution = _mapping(spec, "distributionBps")
    participation = _mapping(spec, "participation")
    requester = _mapping(spec, "requester")
    if token.get("minting") != "disabled":
        raise ValueError("MINTING_DISABLED")
    if emission.get("model") != "IFPEM":
        raise ValueError("IFPEM_REQUIRED")
    economy = FibonaiEconomy(
        max_supply=_positive("maxSupply", token.get("maxSupply")),
        atomic_units_per_token=_positive("atomicUnitsPerToken", token.get("atomicUnitsPerToken")),
        participant_pool=_positive("participants", allocations.get("participants")),
        investor_pool=_positive(
            "parentCompanyAndTokenHolders",
            allocations.get("parentCompanyAndTokenHolders"),
        ),
        exponent_numerator=_positive("exponentNumerator", emission.get("exponentNumerator")),
        exponent_denominator=_positive("exponentDenominator", emission.get("exponentDenominator")),
        full_participant_pool_bps=_bps(
            "fullConsensusParticipantPool",
            distribution.get("fullConsensusParticipantPool"),
        ),
        full_treasury_bps=_bps("fullConsensusTreasury", distribution.get("fullConsensusTreasury")),
        partial_each_bps=_bps("partialPairEachParticipant", distribution.get("partialPairEachParticipant")),
        partial_treasury_bps=_bps("partialPairTreasury", distribution.get("partialPairTreasury")),
        recycle_participant_bps=_bps(
            "governanceRecycleParticipant",
            distribution.get("governanceRecycleParticipant"),
        ),
        recycle_treasury_bps=_bps(
            "governanceRecycleTreasury",
            distribution.get("governanceRecycleTreasury"),
        ),
        minimum_ram_bytes=_positive("minimumRamBytes", participation.get("minimumRamBytes")),
        minimum_free_storage_bytes=_positive(
            "minimumFreeStorageBytes",
            participation.get("minimumFreeStorageBytes"),
        ),
        monthly_free_request_cap=_optional_nonneg(requester.get("monthlyFreeRequestCap")),
        series_first=_positive("firstTerm", series.get("firstTerm")),
        series_second=_positive("secondTerm", series.get("secondTerm")),
        base_task_atomic=_positive("baseTaskAtomic", _mapping(spec, "task").get("baseTaskAtomic")),
        default_difficulty_grade=_positive(
            "defaultDifficultyGrade",
            _mapping(spec, "task").get("defaultDifficultyGrade"),
        ),
    )
    if economy.participant_pool + economy.investor_pool != economy.max_supply:
        raise ValueError("SUPPLY_NOT_CLOSED")
    if economy.full_participant_pool_bps + economy.full_treasury_bps != _BPS:
        raise ValueError("FULL_SPLIT_MUST_SUM_10000")
    pair_total = 2 * economy.partial_each_bps + economy.partial_treasury_bps
    if pair_total != _BPS:
        raise ValueError("PARTIAL_SPLIT_MUST_SUM_10000")
    if economy.recycle_participant_bps + economy.recycle_treasury_bps != _BPS:
        raise ValueError("RECYCLE_SPLIT_MUST_SUM_10000")
    if economy.series_second != economy.series_first + economy.series_first:
        raise ValueError("FIBONACCI_SEED_INVALID")
    return economy


def _mapping(spec: dict[str, Any], key: str) -> dict[str, Any]:
    value = spec.get(key)
    if not isinstance(value, dict):
        raise ValueError("ECONOMY_POLICY_INVALID")
    return value


def _positive(name: str, value: object) -> int:
    number = _whole(name, value)
    if number < 1:
        raise ValueError("NEGATIVE_INPUT")
    return number


def _bps(name: str, value: object) -> int:
    number = _whole(name, value)
    if number < 0 or number > _BPS:
        raise ValueError("BPS_OUT_OF_RANGE")
    return number


def _optional_nonneg(value: object) -> int | None:
    if value is None:
        return None
    number = _whole("monthlyFreeRequestCap", value)
    if number < 0:
        raise ValueError("NEGATIVE_INPUT")
    return number


@lru_cache(maxsize=4)
def _emission_weights(
    first: int,
    second: int,
    numerator: int,
    denominator: int,
) -> tuple[tuple[Decimal, ...], Decimal]:
    with localcontext() as ctx:
        ctx.prec = _DECIMAL_PRECISION
        exponent = Decimal(numerator) / Decimal(denominator)
        terms = [first, second]
        while len(terms) < _SERIES_TERMS:
            terms.append(terms[-1] + terms[-2])
        weights = [Decimal(term) ** (-exponent) for term in terms]
        last = weights[-1]
        prior = weights[-2]
        ratio = last / prior
        if ratio >= 1:
            raise ValueError("EMISSION_NOT_DECREASING")
        tail = last * ratio / (Decimal(1) - ratio)
        return tuple(weights), sum(weights, Decimal(0)) + tail
