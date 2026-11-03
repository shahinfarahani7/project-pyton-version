from __future__ import annotations

from datetime import UTC, datetime
from types import SimpleNamespace

from edgemint.dev.fibonai_credits import recent_credit_records


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
