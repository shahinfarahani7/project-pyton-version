from __future__ import annotations

import httpx
import pytest
from edgemint.dev import model_artifact_proxy


def test_upstream_artifact_url_for_qwen3_profile() -> None:
    url = model_artifact_proxy.upstream_artifact_url("mdv_qwen3_0_6b")
    assert url.endswith("Qwen3-0.6B.litertlm")
    assert "litert-community/Qwen3-0.6B" in url


def test_upstream_artifact_url_for_gemma_profile() -> None:
    url = model_artifact_proxy.upstream_artifact_url("mdv_gemma_3n_e2b_int4")
    assert url.endswith("gemma-3n-E2B-it-int4.litertlm")


def test_upstream_artifact_url_unknown_model() -> None:
    with pytest.raises(Exception) as exc_info:
        model_artifact_proxy.upstream_artifact_url("mdv_unknown")
    assert exc_info.value.status_code == 404


def test_qwen3_artifact_does_not_require_auth() -> None:
    spec = model_artifact_proxy._SUPPORTED_ARTIFACTS["mdv_qwen3_0_6b"]
    assert spec.requires_auth is False


def test_current_gemma_artifact_matches_worker_pin() -> None:
    spec = model_artifact_proxy._SUPPORTED_ARTIFACTS["mdv_gemma_4_e4b_it"]
    assert spec.file_name == "gemma-4-E4B-it.litertlm"
    assert spec.size_bytes == 3659530240
    assert spec.sha256 == "0b2a8980ce155fd97673d8e820b4d29d9c7d99b8fa6806f425d969b145bd52e0"


def test_artifact_delivery_payload_for_gemma() -> None:
    body = model_artifact_proxy.artifact_delivery_payload("mdv_gemma_4_e4b_it")
    assert body["downloadPath"] == "/models/mdv_gemma_4_e4b_it/files/gemma-4-E4B-it.litertlm"
    assert body["artifactSha256"] == "0b2a8980ce155fd97673d8e820b4d29d9c7d99b8fa6806f425d969b145bd52e0"
    assert body["sizeBytes"] == 3659530240


class _Body(httpx.AsyncByteStream):
    closed = False

    async def __aiter__(self):
        yield b"remaining-model-bytes"

    async def aclose(self):
        self.closed = True


@pytest.mark.asyncio
@pytest.mark.parametrize("status", [200, 206, 416])
async def test_proxy_preserves_range_semantics_and_closes_upstream(monkeypatch, status) -> None:
    body = _Body()
    clients = []
    original_client = httpx.AsyncClient

    def upstream(request):
        assert request.headers["range"] == "bytes=8192-"
        assert request.headers["if-range"] == '"model-v1"'
        assert request.headers["accept-encoding"] == "identity"
        return httpx.Response(
            status,
            headers={
                "Content-Range": "bytes 8192-9999/10000" if status != 416 else "bytes */10000",
                "Accept-Ranges": "bytes",
                "ETag": '"model-v1"',
                "Content-Type": "application/octet-stream",
            },
            stream=body,
        )

    def create_client(**kwargs):
        client = original_client(transport=httpx.MockTransport(upstream), **kwargs)
        clients.append(client)
        return client

    monkeypatch.setattr(model_artifact_proxy.httpx, "AsyncClient", create_client)
    response = await model_artifact_proxy.stream_model_artifact(
        "mdv_gemma_4_e4b_it", range_header="bytes=8192-", if_range='"model-v1"',
    )
    assert response.status_code == status
    assert response.headers["accept-ranges"] == "bytes"
    assert response.headers["etag"] == '"model-v1"'
    assert response.headers["content-range"] == (
        "bytes */10000" if status == 416 else "bytes 8192-9999/10000"
    )
    assert b"".join([chunk async for chunk in response.body_iterator]) == b"remaining-model-bytes"
    assert body.closed
    assert clients[0].is_closed


@pytest.mark.asyncio
async def test_proxy_connect_failure_closes_client(monkeypatch) -> None:
    clients = []
    original_client = httpx.AsyncClient

    def upstream(request):
        raise httpx.ConnectError("offline", request=request)

    def create_client(**kwargs):
        client = original_client(transport=httpx.MockTransport(upstream), **kwargs)
        clients.append(client)
        return client

    monkeypatch.setattr(model_artifact_proxy.httpx, "AsyncClient", create_client)
    with pytest.raises(Exception) as exc:
        await model_artifact_proxy.stream_model_artifact("mdv_gemma_4_e4b_it")
    assert exc.value.status_code == 502
    assert clients[0].is_closed


@pytest.mark.asyncio
@pytest.mark.parametrize("use_file_route", [False, True])
async def test_public_routes_forward_resume_headers(monkeypatch, use_file_route) -> None:
    from edgemint.services import model_registry
    from fastapi import Request

    captured = []

    async def stream(model_version_id, **kwargs):
        captured.append((model_version_id, kwargs))
        return "stream-result"

    monkeypatch.setattr(model_artifact_proxy, "stream_model_artifact", stream)
    request = Request({
        "type": "http",
        "headers": [(b"range", b"bytes=8192-"), (b"if-range", b'"version-1"')],
    })
    if use_file_route:
        result = await model_registry.download_model_file(
            request, "mdv_gemma_4_e4b_it", "gemma-4-E4B-it.litertlm",
        )
    else:
        result = await model_registry.download_model_artifact(request, "mdv_gemma_4_e4b_it")
    assert result == "stream-result"
    assert captured == [(
        "mdv_gemma_4_e4b_it", {"range_header": "bytes=8192-", "if_range": '"version-1"'},
    )]
