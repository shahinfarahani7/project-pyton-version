from __future__ import annotations

from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from uuid import UUID

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncConnection, AsyncEngine, create_async_engine

from .settings import get_settings

_engine: AsyncEngine | None = None


def get_engine() -> AsyncEngine:
    """Create the process-local async engine lazily.

    Lazy creation keeps contract-generation and import-only verification independent from
    a locally installed PostgreSQL driver while production requests still fail closed when
    the configured driver or database is unavailable.
    """
    global _engine
    if _engine is None:
        _engine = create_async_engine(
            get_settings().require_database_url(),
            pool_pre_ping=True,
            pool_size=10,
            max_overflow=20,
        )
    return _engine


@asynccontextmanager
async def transaction(
    *, workspace_id: UUID | None = None, isolation: str = "SERIALIZABLE"
) -> AsyncIterator[AsyncConnection]:
    async with get_engine().connect() as connection:
        connection = await connection.execution_options(isolation_level=isolation)
        async with connection.begin():
            # A transaction-local GUC cannot leak to another request through connection pooling.
            if workspace_id is not None:
                await connection.execute(
                    text("SELECT set_config('app.workspace_id', :workspace_id, true)"),
                    {"workspace_id": str(workspace_id)},
                )
            yield connection


async def readiness() -> bool:
    try:
        async with get_engine().connect() as connection:
            return bool((await connection.execute(text("SELECT 1"))).scalar_one())
    except Exception:
        return False


async def dispose_engine() -> None:
    global _engine
    if _engine is not None:
        await _engine.dispose()
        _engine = None
