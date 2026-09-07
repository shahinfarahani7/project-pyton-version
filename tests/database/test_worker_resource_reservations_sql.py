"""Static contract tests for worker resource reservation ledger SQL."""

from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MIGRATION = ROOT / "database" / "sql" / "018_worker_resource_reservations.sql"


def test_worker_resource_reservation_migration_exists() -> None:
    assert MIGRATION.exists()


def test_worker_resource_reservation_migration_is_transactional() -> None:
    text = MIGRATION.read_text(encoding="utf-8")
    assert "BEGIN;" in text
    lines = [line.strip() for line in text.splitlines() if line.strip() and not line.strip().startswith("--")]
    assert lines[-1] == "COMMIT;"


def test_worker_resource_reservation_table_and_states() -> None:
    text = MIGRATION.read_text(encoding="utf-8")
    assert "CREATE TABLE IF NOT EXISTS public.worker_resource_reservations" in text
    for status in ("reserved", "active", "released", "expired", "revoked"):
        assert status in text
    for column in (
        "assignment_id",
        "worker_device_id",
        "task_revision_id",
        "cpu_units",
        "memory_bytes",
        "storage_bytes",
        "accelerator_units",
        "model_session_units",
        "exclusive_group",
        "fence_token",
        "reserved_at_utc",
        "activated_at_utc",
        "released_at_utc",
        "expires_at_utc",
    ):
        assert column in text


def test_worker_resource_reservation_functions_cover_lifecycle() -> None:
    text = MIGRATION.read_text(encoding="utf-8")
    for function_name in (
        "create_worker_resource_reservation",
        "activate_worker_resource_reservation",
        "release_worker_resource_reservation",
        "release_worker_resource_reservation_by_assignment",
        "worker_device_resource_totals",
    ):
        assert re.search(rf"FUNCTION public\.{function_name}\(", text)
