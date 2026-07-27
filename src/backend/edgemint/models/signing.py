from __future__ import annotations

import hashlib
import hmac
import json
from dataclasses import dataclass
from typing import Any

from edgemint.building_blocks.settings import Settings, get_settings
from edgemint.models.errors import model_error


def canonical_manifest_bytes(manifest: dict[str, Any]) -> bytes:
    return json.dumps(manifest, separators=(",", ":"), sort_keys=True).encode("utf-8")


def manifest_digest(manifest: dict[str, Any]) -> str:
    return hashlib.sha256(canonical_manifest_bytes(manifest)).hexdigest()


def sign_manifest(manifest: dict[str, Any], *, settings: Settings | None = None) -> str:
    active = settings or get_settings()
    secret = active.model_signing_secret or "edgemint-development-model-signing-secret"
    unsigned = {key: value for key, value in manifest.items() if key != "signatureSha256"}
    digest = hmac.new(secret.encode("utf-8"), canonical_manifest_bytes(unsigned), hashlib.sha256).digest()
    return hashlib.sha256(digest).hexdigest()


def verify_manifest_signature(
    manifest: dict[str, Any],
    *,
    signature_sha256: str,
    settings: Settings | None = None,
) -> None:
    expected = sign_manifest(manifest, settings=settings)
    if not hmac.compare_digest(expected, signature_sha256):
        raise model_error("MODEL_SIGNATURE_INVALID")


@dataclass(frozen=True, slots=True)
class ManifestChunk:
    index: int
    offset: int
    size_bytes: int
    sha256: str


def build_digest_pinned_manifest(
    *,
    model_version_public_id: str,
    artifact_sha256: str,
    artifact_size_bytes: int,
    runtime_abi: str,
    license_spdx: str,
    chunk_size_bytes: int,
    settings: Settings | None = None,
) -> tuple[dict[str, Any], str]:
    chunks: list[dict[str, Any]] = []
    offset = 0
    index = 0
    remaining = artifact_size_bytes
    while remaining > 0:
        size = min(chunk_size_bytes, remaining)
        chunk_digest = hashlib.sha256(f"{artifact_sha256}:{index}:{size}".encode()).hexdigest()
        chunks.append(
            {
                "index": index,
                "offset": offset,
                "sizeBytes": size,
                "sha256": chunk_digest,
            }
        )
        offset += size
        remaining -= size
        index += 1
    manifest: dict[str, Any] = {
        "modelVersionId": model_version_public_id,
        "artifactSha256": artifact_sha256,
        "artifactSizeBytes": artifact_size_bytes,
        "runtimeAbi": runtime_abi,
        "licenseSpdx": license_spdx,
        "encrypted": True,
        "resumable": True,
        "atomicInstall": True,
        "chunks": chunks,
    }
    signature = sign_manifest(manifest, settings=settings)
    manifest["signatureSha256"] = signature
    return manifest, signature
