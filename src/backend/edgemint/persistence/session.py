from __future__ import annotations

import hashlib
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from pathlib import Path
from uuid import UUID

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncConnection

from edgemint.building_blocks.database import get_engine, transaction


@asynccontextmanager
async def get_connection(*, workspace_id: UUID | None = None) -> AsyncIterator[AsyncConnection]:
    async with transaction(workspace_id=workspace_id) as connection:
        yield connection


class WorkspaceSession:
    """Scoped database access with mandatory workspace context for RLS-protected tables."""

    def __init__(self, workspace_id: UUID) -> None:
        self.workspace_id = workspace_id

    @asynccontextmanager
    async def connection(self, *, isolation: str = "SERIALIZABLE") -> AsyncIterator[AsyncConnection]:
        async with transaction(workspace_id=self.workspace_id, isolation=isolation) as conn:
            yield conn

    async def set_workspace_context(self, connection: AsyncConnection) -> None:
        await connection.execute(
            text("SELECT set_config('app.workspace_id', :workspace_id, true)"),
            {"workspace_id": str(self.workspace_id)},
        )


def migration_checksum(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


async def run_migrations_checksum(migrations_dir: Path) -> list[tuple[str, str]]:
    """Return applied migration versions and checksums from the live database."""
    async with get_engine().connect() as connection:
        result = await connection.execute(
            text("SELECT version, checksum_sha256 FROM public.schema_migrations ORDER BY version")
        )
        return [(row.version, row.checksum_sha256) for row in result]
