from __future__ import annotations

import os
from collections.abc import AsyncIterator
from dataclasses import dataclass

import httpx
from fastapi import HTTPException
from fastapi.responses import StreamingResponse


@dataclass(frozen=True)
class _ArtifactSpec:
    hf_repo: str
    file_name: str
    requires_auth: bool
    sha256: str | None = None
    size_bytes: int | None = None


_SUPPORTED_ARTIFACTS: dict[str, _ArtifactSpec] = {
    "mdv_qwen3_0_6b": _ArtifactSpec(
        hf_repo="litert-community/Qwen3-0.6B",
        file_name="Qwen3-0.6B.litertlm",
        requires_auth=False,
        sha256="555579ff2f4fd13379abe69c1c3ab5200f7338bc92471557f1d6614a6e5ab0b4",
    ),
    "mdv_gemma_3n_e2b_int4": _ArtifactSpec(
        hf_repo="google/gemma-3n-E2B-it-litert-lm",
        file_name="gemma-3n-E2B-it-int4.litertlm",
        requires_auth=True,
    ),
}


def huggingface_token() -> str | None:
    token = os.environ.get("EDGEMINT_HUGGINGFACE_TOKEN") or os.environ.get("HUGGINGFACE_TOKEN")
    if token:
        token = token.strip()
    return token or None


def upstream_artifact_url(model_version_id: str) -> str:
    spec = _SUPPORTED_ARTIFACTS.get(model_version_id)
    if spec is None:
        raise HTTPException(status_code=404, detail="MODEL_ARTIFACT_NOT_FOUND")
    return f"https://huggingface.co/{spec.hf_repo}/resolve/main/{spec.file_name}"


async def stream_model_artifact(model_version_id: str) -> StreamingResponse:
    spec = _SUPPORTED_ARTIFACTS.get(model_version_id)
    if spec is None:
        raise HTTPException(status_code=404, detail="MODEL_ARTIFACT_NOT_FOUND")

    headers: dict[str, str] = {}
    if spec.requires_auth:
        token = huggingface_token()
        if token is None:
            raise HTTPException(status_code=503, detail="HUGGINGFACE_TOKEN_NOT_CONFIGURED")
        headers["Authorization"] = f"Bearer {token}"

    url = upstream_artifact_url(model_version_id)
    client = httpx.AsyncClient(timeout=httpx.Timeout(600.0), follow_redirects=True)
    upstream = client.build_request("GET", url, headers=headers)
    response = await client.send(upstream, stream=True)
    if response.status_code != 200:
        body = await response.aread()
        await response.aclose()
        await client.aclose()
        raise HTTPException(
            status_code=502,
            detail=f"UPSTREAM_DOWNLOAD_FAILED:{response.status_code}:{body[:200]!r}",
        )

    async def body() -> AsyncIterator[bytes]:
        try:
            async for chunk in response.aiter_bytes():
                yield chunk
        finally:
            await response.aclose()
            await client.aclose()

    response_headers = {
        "Content-Disposition": f'attachment; filename="{spec.file_name}"',
        **({"X-Artifact-SHA256": spec.sha256} if spec.sha256 else {}),
        **({"X-Artifact-Size": str(spec.size_bytes)} if spec.size_bytes else {}),
    }
    content_length = response.headers.get("content-length")
    if content_length:
        response_headers["Content-Length"] = content_length
    media_type = response.headers.get("content-type", "application/octet-stream")
    return StreamingResponse(body(), media_type=media_type, headers=response_headers)
