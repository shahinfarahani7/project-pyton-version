from __future__ import annotations

_QUALITY_FAILURE_CODES: frozenset[str] = frozenset(
    {
        "RESULT_VALIDATION_FAILED",
        "SEMANTIC_QUALITY_FAILED",
        "OCR_EMPTY_RESULT",
        "VISION_LOW_CONFIDENCE",
        "RESULT_LOW_CONFIDENCE",
        "RESULT_EMPTY",
        "GOLDEN_VALIDATION_FAILED",
    }
)

_CAPACITY_FAILURE_CODES: frozenset[str] = frozenset(
    {
        "MODEL_UNAVAILABLE",
        "RESOURCE_EXHAUSTED",
        "WORKER_OFFLINE",
        "LEASE_EXPIRED",
    }
)

_VERIFICATION_LADDER: tuple[str, ...] = ("standard", "high", "premium")


def escalation_class_for_failure(failure_code: str) -> str:
    """Section 49/58: distinguish quality validation from capacity failures."""
    normalized = failure_code.upper()
    if normalized in _QUALITY_FAILURE_CODES:
        return "quality"
    if normalized in _CAPACITY_FAILURE_CODES:
        return "capacity"
    return "other"


def escalated_verification_tier(*, current_tier: str, failure_code: str) -> str:
    """Section 49: bump quote verification tier after quality validation failures only."""
    if escalation_class_for_failure(failure_code) != "quality":
        return current_tier
    try:
        index = _VERIFICATION_LADDER.index(current_tier)
    except ValueError:
        index = 0
    next_index = min(index + 1, len(_VERIFICATION_LADDER) - 1)
    return _VERIFICATION_LADDER[next_index]
