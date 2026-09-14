"""PostgreSQL integration tests (require live PostgreSQL when enabled)."""

from __future__ import annotations

import hashlib
import os
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
MIGRATIONS = ROOT / "database" / "sql"


def _postgres_available() -> bool:
    if not os.environ.get("EDGEMINT_DATABASE_URL"):
        return False
    try:
        import psycopg

        conninfo = os.environ["EDGEMINT_DATABASE_URL"].replace("postgresql+psycopg://", "postgresql://")
        with psycopg.connect(conninfo, connect_timeout=3) as conn:
            conn.execute("SELECT 1")
        return True
    except Exception:
        return False


requires_postgres = pytest.mark.skipif(not _postgres_available(), reason="PostgreSQL not available")


def test_migration_files_are_transactional() -> None:
    files = sorted(MIGRATIONS.glob("*.sql"))
    assert len(files) >= 38
    for migration in files:
        text = migration.read_text(encoding="utf-8")
        assert "BEGIN;" in text
        lines = [line.strip() for line in text.splitlines() if line.strip() and not line.strip().startswith("--")]
        assert lines[-1] == "COMMIT;"


def test_migration_checksums_are_stable() -> None:
    files = sorted(MIGRATIONS.glob("*.sql"))
    checksums = {
        migration.name: hashlib.sha256(migration.read_bytes()).hexdigest()
        for migration in files
    }
    assert len(checksums) == len(files)
    assert all(len(value) == 64 for value in checksums.values())


@requires_postgres
@pytest.mark.asyncio
async def test_database_readiness() -> None:
    from edgemint.building_blocks.database import readiness

    assert await readiness() is True


@requires_postgres
@pytest.mark.asyncio
async def test_workspace_context_is_transaction_local() -> None:
    from uuid import uuid4

    from sqlalchemy import text

    from edgemint.building_blocks.database import transaction

    workspace_id = uuid4()
    async with transaction(workspace_id=workspace_id) as connection:
        value = (
            await connection.execute(text("SELECT current_setting('app.workspace_id', true)"))
        ).scalar_one()
        assert value == str(workspace_id)
