from __future__ import annotations

from datetime import UTC, datetime
from decimal import Decimal
from types import SimpleNamespace

import pytest
from edgemint.dev.fibonai_credits import issued_atomic, recent_credit_records


def test_issued_atomic_accepts_a_non_negative_credit_sum() -> None:
    assert issued_atomic(0) == 0
    assert issued_atomic(300_000) == 300_000
    assert issued_atomic(Decimal("300000")) == 300_000


def test_issued_atomic_rejects_a_partial_or_negative_total() -> None:
    with pytest.raises(TypeError):
        issued_atomic(1.5)
    with pytest.raises(TypeError):
        issued_atomic(True)
    with pytest.raises(ValueError):
        issued_atomic(-1)


def test_recent_credit_records_emit_positive_points_as_utc() -> None:
    rows = [
        SimpleNamespace(points=40, created_at_utc=datetime(2026, 11, 3, 6, 30, tzinfo=UTC)),
        (40, datetime(2026, 11, 2, 21, 0)),
        SimpleNamespace(points=0, created_at_utc=datetime(2026, 11, 1, tzinfo=UTC)),
        SimpleNamespace(points=40, created_at_utc="not-a-timestamp"),
    ]

    assert recent_credit_records(rows) == [
        {"points": 40, "creditedAtUtc": "2026-11-03T06:30:00Z"},
        {"points": 40, "creditedAtUtc": "2026-11-02T21:00:00Z"},
    ]
