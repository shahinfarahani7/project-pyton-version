from __future__ import annotations

import pytest
from edgemint.economy.fibonai_token import (
    cached_economy,
    investor_emission,
    load_economy,
    participant_emission,
    quote_accepted_task,
    recycle_treasury,
    scale_by_difficulty,
    scheduled_distribution,
    split_released,
    year_end_treasury,
)

_GIB = 1024**3


def test_policy_matches_whitepaper_supply() -> None:
    policy = load_economy()
    assert policy.max_supply == 21_000_000_000
    assert policy.participant_pool == 16_000_000_000
    assert policy.investor_pool == 5_000_000_000
    assert policy.participant_pool + policy.investor_pool == policy.max_supply
    assert policy.minting_disabled is True
    assert policy.exponent_numerator == 1
    assert policy.exponent_denominator == 4
    assert policy.atomic_units_per_token == 10_000
    assert policy.full_participant_pool_bps == 7_500
    assert policy.full_treasury_bps == 2_500
    assert policy.partial_each_bps == 2_500
    assert policy.partial_treasury_bps == 5_000
    assert policy.monthly_free_request_cap is None
    assert policy.minimum_ram_bytes == 4 * _GIB
    assert policy.minimum_free_storage_bytes == 4 * _GIB
    assert policy.base_task_atomic == 400_000
    assert policy.default_difficulty_grade == 1
    assert cached_economy() == policy


def test_year_one_emission_rounds_to_whitepaper_illustration() -> None:
    participant_year_one = participant_emission(1)
    investor_year_one = investor_emission(1)
    assert participant_year_one == 1_879_797_899
    assert investor_year_one == 587_436_843
    assert (participant_year_one + 5_000_000) // 10_000_000 == 188
    assert participant_emission(1) > participant_emission(2) > participant_emission(3)
    assert participant_emission(2) == 1_580_715_314
    assert participant_year_one + investor_year_one < 21_000_000_000


def test_emission_stays_inside_the_closed_pool() -> None:
    policy = load_economy()
    released = sum(participant_emission(year) for year in range(1, 301))
    assert released <= policy.participant_pool
    assert policy.participant_pool - released < 1_000
    assert participant_emission(601) == 0
    with pytest.raises(ValueError, match="NEGATIVE_INPUT"):
        participant_emission(0)


def test_full_consensus_pays_seventy_five_and_treasury_twenty_five() -> None:
    released = 160_000
    payout = split_released(released, "full", 3)
    assert payout.paid_participants == 3
    assert payout.each_atomic == 40_000
    assert payout.treasury_atomic == 40_000
    assert payout.participant_total_atomic + payout.treasury_atomic == released

    four = split_released(released, "full", 4)
    assert four.each_atomic == 30_000
    assert four.participant_total_atomic == 120_000
    assert four.treasury_atomic == 40_000

    five = split_released(released, "full", 5)
    assert five.each_atomic == 24_000
    assert five.participant_total_atomic == 120_000
    assert five.treasury_atomic == 40_000


def test_two_of_three_pays_each_quarter_and_treasury_half() -> None:
    payout = split_released(160_000, "partial_pair", 2)
    assert payout.paid_participants == 2
    assert payout.each_atomic == 40_000
    assert payout.treasury_atomic == 80_000
    assert payout.unreleased_atomic == 0
    assert payout.participant_total_atomic + payout.treasury_atomic == 160_000


def test_failed_consensus_releases_nothing() -> None:
    payout = split_released(160_000, "none", 0)
    assert payout.participant_total_atomic == 0
    assert payout.treasury_atomic == 0
    assert payout.unreleased_atomic == 160_000


def test_split_remainder_stays_in_treasury_without_minting() -> None:
    payout = split_released(10, "full", 3)
    assert payout.each_atomic == 2
    assert payout.participant_total_atomic + payout.treasury_atomic + payout.unreleased_atomic == 10
    assert payout.treasury_atomic == 4


def test_accepted_task_charges_forty_fibon_and_pays_the_worker_pool() -> None:
    quote = quote_accepted_task()
    assert quote.difficulty_grade == 1
    assert quote.charge_atomic == 400_000
    assert quote.worker_reward_atomic == 300_000
    assert quote.treasury_atomic == 100_000
    graded = quote_accepted_task(3)
    assert graded.charge_atomic == 1_200_000
    assert graded.worker_reward_atomic == 900_000
    assert graded.treasury_atomic == 300_000


def test_difficulty_grade_scales_charge_and_release() -> None:
    assert scale_by_difficulty(100, 3) == 300
    base_release = 160_000
    released = scale_by_difficulty(base_release, 3)
    payout = split_released(released, "full", 3)
    assert payout.each_atomic == 120_000
    assert payout.treasury_atomic == 120_000
    with pytest.raises(ValueError, match="NEGATIVE_INPUT"):
        scale_by_difficulty(100, 0)


def test_year_end_illustration_sends_unused_and_quarter_to_treasury() -> None:
    annual = 1_880_000_000
    consumed = 1_600_000_000
    participants, treasury = scheduled_distribution(consumed, participant_bps=7_500)
    assert participants == 1_200_000_000
    assert treasury == 400_000_000
    closed = year_end_treasury(annual, participant_paid=participants, treasury_paid=treasury)
    assert closed.unused_emission == 280_000_000
    assert closed.treasury_total == 680_000_000

    full_participants, full_treasury = scheduled_distribution(annual, participant_bps=7_500)
    assert full_treasury == 470_000_000
    assert full_participants == 1_410_000_000
    with pytest.raises(ValueError, match="OVER_SUBSCRIBED"):
        year_end_treasury(annual, participant_paid=annual, treasury_paid=1)


def test_governance_recycle_uses_only_the_treasury_balance() -> None:
    recycled = recycle_treasury(470_000_000, vote_accepted=True)
    assert recycled.to_participants == 352_500_000
    assert recycled.retained == 117_500_000
    held = recycle_treasury(recycled.retained, vote_accepted=False)
    assert held.to_participants == 0
    assert held.retained == 117_500_000
    again = recycle_treasury(held.retained, vote_accepted=True)
    assert again.to_participants == 88_125_000
    assert again.retained == 29_375_000


def test_rejects_unknown_consensus_shape() -> None:
    with pytest.raises(ValueError, match="FULL_CONSENSUS_REQUIRES_THREE"):
        split_released(160_000, "full", 2)
    with pytest.raises(ValueError, match="PARTIAL_PAIR_REQUIRES_TWO"):
        split_released(160_000, "partial_pair", 3)
