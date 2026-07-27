from __future__ import annotations


def ceil_div(value: int, quantum: int) -> int:
    if quantum <= 0:
        raise ValueError("QUANTUM_MUST_BE_POSITIVE")
    if value < 0:
        raise ValueError("NEGATIVE_INPUT")
    return (value + quantum - 1) // quantum


def apply_bps(value: int, bps: int) -> int:
    """HALF_UP basis-point multiplication on integer micro-EUR amounts."""
    if value < 0:
        raise ValueError("NEGATIVE_INPUT")
    if bps < 0:
        raise ValueError("NEGATIVE_BPS")
    return (value * bps + 9_999) // 10_000
