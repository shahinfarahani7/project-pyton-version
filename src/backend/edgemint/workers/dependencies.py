from __future__ import annotations

from typing import Annotated

from fastapi import Depends, Header

from edgemint.workers.errors import worker_error


async def worker_bearer_token(authorization: str | None = Header(default=None, alias="Authorization")) -> str:
    if not authorization or not authorization.startswith("Bearer "):
        raise worker_error("AUTH_INVALID_CREDENTIAL")
    token = authorization.removeprefix("Bearer ").strip()
    if not token:
        raise worker_error("AUTH_INVALID_CREDENTIAL")
    return token


WorkerBearerToken = Annotated[str, Depends(worker_bearer_token)]
