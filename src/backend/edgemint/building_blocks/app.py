from __future__ import annotations

import asyncio
import contextlib
from collections.abc import AsyncIterator, Awaitable, Callable
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.responses import ORJSONResponse

from .database import dispose_engine, readiness

CONTRACT_VERSION = "5.0.0"


def create_service_app(
    service_name: str,
    background: Callable[[], Awaitable[None]] | None = None,
) -> FastAPI:
    @asynccontextmanager
    async def lifespan(_: FastAPI) -> AsyncIterator[None]:
        task: asyncio.Task[None] | None = None
        if background is not None:
            task = asyncio.create_task(background())
        try:
            yield
        finally:
            if task is not None:
                task.cancel()
                with contextlib.suppress(asyncio.CancelledError):
                    await task
            await dispose_engine()

    app = FastAPI(
        title=f"EdgeMint {service_name}",
        version=CONTRACT_VERSION,
        default_response_class=ORJSONResponse,
        lifespan=lifespan,
    )

    @app.get("/health/live", include_in_schema=False)
    async def live() -> dict[str, str]:
        return {"status": "live"}

    @app.get("/health/ready", include_in_schema=False)
    async def ready() -> ORJSONResponse:
        ok = await readiness()
        return ORJSONResponse(
            {"status": "ready" if ok else "not_ready"},
            status_code=200 if ok else 503,
        )

    @app.get("/version", include_in_schema=False)
    async def version() -> dict[str, str]:
        return {"service": service_name, "version": CONTRACT_VERSION}

    @app.get("/", include_in_schema=False)
    async def root() -> dict[str, str]:
        return {"service": service_name, "status": "ready", "contractVersion": CONTRACT_VERSION}

    return app
