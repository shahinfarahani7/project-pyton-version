from __future__ import annotations

from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.responses import ORJSONResponse

from .database import dispose_engine, readiness

CONTRACT_VERSION = "5.0.0"


def create_service_app(service_name: str) -> FastAPI:
    @asynccontextmanager
    async def lifespan(_: FastAPI) -> AsyncIterator[None]:
        yield
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
