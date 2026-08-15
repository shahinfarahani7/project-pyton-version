from __future__ import annotations

import os
from collections.abc import AsyncIterator

import httpx
from fastapi import Request, Response
from starlette.responses import StreamingResponse

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


def _timeout_for(path: str) -> httpx.Timeout:
    if path.startswith("/models/") and (
        path.endswith("/artifact") or "/files/" in path
    ):
        return httpx.Timeout(connect=30.0, read=None, write=30.0, pool=30.0)
    return httpx.Timeout(120.0)


def _filter_headers(headers: httpx.Headers) -> dict[str, str]:
    return {key: value for key, value in headers.items() if key.lower() not in HOP_BY_HOP}


def _upstream_for(path: str) -> str:
    if path.startswith("/models"):
        return MODEL_REGISTRY
    return WORKER_REGISTRY


def _is_artifact_download(path: str) -> bool:
    return path.startswith("/models/") and (
        path.endswith("/artifact") or "/files/" in path
    )


async def _forward_artifact_stream(
    *,
    upstream: str,
    path: str,
    request: Request,
    headers: dict[str, str],
    body: bytes,
) -> StreamingResponse:
    client = httpx.AsyncClient(timeout=_timeout_for(path))
    upstream_request = client.build_request(
        request.method,
        f"{upstream}{path}",
        params=request.query_params,
        content=body,
        headers=headers,
    )
    upstream_response = await client.send(upstream_request, stream=True)

    async def body_iter() -> AsyncIterator[bytes]:
        try:
            async for chunk in upstream_response.aiter_bytes():
                yield chunk
        finally:
            await upstream_response.aclose()
            await client.aclose()

    return StreamingResponse(
        body_iter(),
        status_code=upstream_response.status_code,
        headers=_filter_headers(upstream_response.headers),
    )


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
    if _is_artifact_download(path) and request.method == "GET":
        return await _forward_artifact_stream(
            upstream=upstream,
            path=path,
            request=request,
            headers=headers,
            body=body,
        )
    response = await _client_or_create().request(
        request.method,
        f"{upstream}{path}",
        params=request.query_params,
        content=body,
        headers=headers,
        timeout=_timeout_for(path),
    )
    return Response(
        content=response.content,
        status_code=response.status_code,
        headers=_filter_headers(response.headers),
    )
