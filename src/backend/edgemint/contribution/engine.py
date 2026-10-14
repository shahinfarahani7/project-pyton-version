from __future__ import annotations

from dataclasses import dataclass

from edgemint.contribution.policy import CENTI_PER_XP, ContributionPolicy

MS_PER_MINUTE = 60_000
BPS_SCALE = 10_000
TIME_COMPONENT_AVAILABLE = "TIME_COMPONENT_AVAILABLE"
TIME_COMPONENT_UNAVAILABLE = "TIME_COMPONENT_UNAVAILABLE"


def _half_up_div(numerator: int, denominator: int) -> int:
    if numerator < 0 or denominator <= 0:
        raise ValueError("half-up division expects a non-negative numerator and positive denominator")
    return (2 * numerator + denominator) // (2 * denominator)


@dataclass(frozen=True, slots=True)
class XpAward:
    centi_xp: int
    accepted_processing_ms: int | None
    time_component: str
    boost_applied: bool


def compute_task_xp(
    policy: ContributionPolicy,
    *,
    task_type: str,
    processing_ms: int | None,
    boost_bonus_bps: int | None = None,
) -> XpAward:
    """Exact integer XP: (base + perMinute * minutes(min(processing, cap))) * (1 + boost).

    Rounded once, HALF_UP, to 0.01 XP.
    """
    cap_ms = policy.cap_ms_for(task_type)
    accepted_ms: int | None = None
    if processing_ms is not None and processing_ms >= 0 and cap_ms is not None:
        accepted_ms = min(processing_ms, cap_ms)
    numerator = policy.base_xp * CENTI_PER_XP * MS_PER_MINUTE
    if accepted_ms is not None:
        numerator += policy.xp_per_accepted_minute * CENTI_PER_XP * accepted_ms
    denominator = MS_PER_MINUTE
    if boost_bonus_bps:
        numerator *= BPS_SCALE + boost_bonus_bps
        denominator *= BPS_SCALE
    return XpAward(
        centi_xp=_half_up_div(numerator, denominator),
        accepted_processing_ms=accepted_ms,
        time_component=TIME_COMPONENT_AVAILABLE if accepted_ms is not None else TIME_COMPONENT_UNAVAILABLE,
        boost_applied=bool(boost_bonus_bps),
    )


@dataclass(frozen=True, slots=True)
class LevelProgress:
    level_id: str
    next_level_id: str | None
    current_min_centi_xp: int
    next_min_centi_xp: int | None
    remaining_centi_xp: int | None
    progress_bps: int


def level_progress(policy: ContributionPolicy, total_centi_xp: int) -> LevelProgress:
    if total_centi_xp < 0:
        raise ValueError("total XP cannot be negative")
    levels = policy.levels
    index = 0
    for position, level in enumerate(levels):
        if total_centi_xp >= level.min_centi_xp:
            index = position
    current = levels[index]
    if index == len(levels) - 1:
        return LevelProgress(
            level_id=current.level_id,
            next_level_id=None,
            current_min_centi_xp=current.min_centi_xp,
            next_min_centi_xp=None,
            remaining_centi_xp=None,
            progress_bps=BPS_SCALE,
        )
    upcoming = levels[index + 1]
    span = upcoming.min_centi_xp - current.min_centi_xp
    return LevelProgress(
        level_id=current.level_id,
        next_level_id=upcoming.level_id,
        current_min_centi_xp=current.min_centi_xp,
        next_min_centi_xp=upcoming.min_centi_xp,
        remaining_centi_xp=upcoming.min_centi_xp - total_centi_xp,
        progress_bps=(total_centi_xp - current.min_centi_xp) * BPS_SCALE // span,
    )


def format_centi_xp(centi_xp: int) -> str:
    return f"{centi_xp // CENTI_PER_XP}.{centi_xp % CENTI_PER_XP:02d}"
