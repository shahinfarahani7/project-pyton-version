from __future__ import annotations

import os

import httpx
from fastapi import Request, Response

from edgemint.building_blocks.app import create_service_app

WORKER_REGISTRY = os.environ.get("EDGEMINT_WORKER_REGISTRY_URL", "http://worker-registry:8080").rstrip("/")
MODEL_REGISTRY = os.environ.get("EDGEMINT_MODEL_REGISTRY_URL", "http://model-registry:8080").rstrip("/")

HOP_BY_HOP = frozenset(
    {
        "connection",
        "keep-alive",
        "proxy-authenticate",
        "proxy-authorization",
        "te",
        "trailers",
        "transfer-encoding",
        "upgrade",
        "content-encoding",
        "content-length",
    }
)

app = create_service_app("worker-gateway")
_client: httpx.AsyncClient | None = None


def _client_or_create() -> httpx.AsyncClient:
    global _client
    if _client is None:
        _client = httpx.AsyncClient(timeout=httpx.Timeout(120.0))
    return _client


def _filter_headers(headers: httpx.Headers) -> dict[str, str]:
    return {key: value for key, value in headers.items() if key.lower() not in HOP_BY_HOP}


def _upstream_for(path: str) -> str:
    if path.startswith("/models"):
        return MODEL_REGISTRY
    return WORKER_REGISTRY


@app.api_route("/{full_path:path}", methods=["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD"])
async def forward_worker_request(full_path: str, request: Request) -> Response:
    path = f"/{full_path}"
    upstream = _upstream_for(path)
    body = await request.body()
    headers = {
        key: value
        for key, value in request.headers.items()
        if key.lower() not in {"host", "content-length"}
    }
    response = await _client_or_create().request(
        request.method,
        f"{upstream}{path}",
        params=request.query_params,
        content=body,
        headers=headers,
    )
    return Response(
        content=response.content,
        status_code=response.status_code,
        headers=_filter_headers(response.headers),
    )
