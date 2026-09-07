"""Static contract tests for atomic assignment transaction SQL."""

from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MIGRATION = ROOT / "database" / "sql" / "019_atomic_assignment_transaction.sql"


def test_atomic_assignment_transaction_migration_exists() -> None:
    assert MIGRATION.exists()


def test_atomic_assignment_transaction_migration_is_transactional() -> None:
    text = MIGRATION.read_text(encoding="utf-8")
    assert "BEGIN;" in text
    lines = [line.strip() for line in text.splitlines() if line.strip() and not line.strip().startswith("--")]
    assert lines[-1] == "COMMIT;"


def test_atomic_assignment_transaction_wraps_lease_and_reservation() -> None:
    text = MIGRATION.read_text(encoding="utf-8")
    assert re.search(r"FUNCTION public\.atomic_acquire_assignment_with_reservation\(", text)
    assert "public.acquire_assignment_lease(" in text
    assert "public.create_worker_resource_reservation(" in text
    assert "Architecture §20 atomic boundary" in text
