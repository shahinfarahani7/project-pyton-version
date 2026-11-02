from __future__ import annotations

import hashlib
import os
from pathlib import Path
from urllib.parse import parse_qs, urlsplit

import pytest
from edgemint.dev import model_artifact_proxy
from edgemint.models import artifact_store
from fastapi.testclient import TestClient

_MODEL = "mdv_test_model"
_FILE = "test-model.litertlm"
_PAYLOAD = b"model-bytes-" * 1000
_SHA = hashlib.sha256(_PAYLOAD).hexdigest()
_KEY = "k" * 48


@pytest.fixture
def store(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Path:
    root = tmp_path / "store"
    monkeypatch.setenv("EDGEMINT_MODEL_STORE_DIR", str(root))
    monkeypatch.setenv("EDGEMINT_MODEL_DOWNLOAD_SIGNING_KEY", _KEY)
    monkeypatch.delenv("EDGEMINT_MODEL_DOWNLOAD_URL_TTL_SECONDS", raising=False)
    monkeypatch.setitem(
        model_artifact_proxy._SUPPORTED_ARTIFACTS,
        _MODEL,
        model_artifact_proxy._ArtifactSpec(
            hf_repo="example/test",
            file_name=_FILE,
            requires_auth=False,
            sha256=_SHA,
            size_bytes=len(_PAYLOAD),
        ),
    )
    return root


def _stage(store: Path, tmp_path: Path) -> artifact_store.StoredArtifact:
    source = tmp_path / "download.bin"
    source.write_bytes(_PAYLOAD)
    return artifact_store.stage(
        _MODEL, source, file_name=_FILE, sha256=_SHA, size_bytes=len(_PAYLOAD), root=store
    )


def test_stage_rejects_wrong_hash(store: Path, tmp_path: Path) -> None:
    source = tmp_path / "bad.bin"
    source.write_bytes(b"x" * len(_PAYLOAD))
    with pytest.raises(artifact_store.ArtifactStoreError, match="MODEL_ARTIFACT_SHA256_MISMATCH"):
        artifact_store.stage(
            _MODEL, source, file_name=_FILE, sha256=_SHA, size_bytes=len(_PAYLOAD), root=store
        )
    assert model_artifact_proxy.local_artifact(_MODEL) is None


def test_delivery_uses_huggingface_proxy_until_staged(store: Path, tmp_path: Path) -> None:
    before = model_artifact_proxy.artifact_delivery_payload(_MODEL)
    assert before["source"] == "huggingface-proxy"
    assert "signature" not in str(before["downloadPath"])

    _stage(store, tmp_path)
    after = model_artifact_proxy.artifact_delivery_payload(_MODEL)
    assert after["source"] == "self-hosted"
    assert after["artifactSha256"] == _SHA
    assert after["sizeBytes"] == len(_PAYLOAD)
    parsed = urlsplit(str(after["downloadPath"]))
    assert parsed.path == f"/models/{_MODEL}/files/{_FILE}"
    assert set(parse_qs(parsed.query)) == {"expires", "signature"}


def test_delivery_without_signing_key_stays_on_proxy(store: Path, tmp_path: Path, monkeypatch) -> None:
    _stage(store, tmp_path)
    monkeypatch.setenv("EDGEMINT_MODEL_DOWNLOAD_SIGNING_KEY", "too-short")
    assert model_artifact_proxy.artifact_delivery_payload(_MODEL)["source"] == "huggingface-proxy"


def test_replaced_file_is_not_served_until_restaged(store: Path, tmp_path: Path) -> None:
    staged = _stage(store, tmp_path)
    staged.path.write_bytes(b"y" * len(_PAYLOAD))
    os.utime(staged.path, ns=(1, 1))
    assert model_artifact_proxy.local_artifact(_MODEL) is None


def test_signature_checks(store: Path, tmp_path: Path) -> None:
    staged = _stage(store, tmp_path)
    path = artifact_store.signed_download_path(staged, now=1_000)
    assert path is not None
    query = parse_qs(urlsplit(path).query)
    expires, signature = query["expires"][0], query["signature"][0]

    artifact_store.verify_signature(_MODEL, _FILE, expires=expires, signature=signature, now=1_000)
    with pytest.raises(artifact_store.ArtifactStoreError, match="MODEL_DOWNLOAD_LINK_EXPIRED"):
        artifact_store.verify_signature(_MODEL, _FILE, expires=expires, signature=signature, now=10**9)
    with pytest.raises(artifact_store.ArtifactStoreError, match="MODEL_DOWNLOAD_SIGNATURE_INVALID"):
        artifact_store.verify_signature(
            _MODEL, _FILE, expires=str(int(expires) + 1), signature=signature, now=1_000
        )
    with pytest.raises(artifact_store.ArtifactStoreError, match="MODEL_DOWNLOAD_SIGNATURE_INVALID"):
        artifact_store.verify_signature("mdv_other", _FILE, expires=expires, signature=signature, now=1_000)


def test_path_traversal_ids_are_rejected(store: Path) -> None:
    assert artifact_store.find_artifact("../etc") is None
    assert artifact_store.find_artifact("..") is None


def test_file_route_serves_signed_range_and_rejects_bad_links(store: Path, tmp_path: Path) -> None:
    from edgemint.services import model_registry

    _stage(store, tmp_path)
    path = str(model_artifact_proxy.artifact_delivery_payload(_MODEL)["downloadPath"])
    client = TestClient(model_registry.app)

    full = client.get(path, headers={"Accept-Encoding": "identity"})
    assert full.status_code == 200
    assert full.content == _PAYLOAD
    assert full.headers["x-artifact-sha256"] == _SHA

    resumed = client.get(path, headers={"Range": "bytes=100-", "Accept-Encoding": "identity"})
    assert resumed.status_code == 206
    assert resumed.headers["content-range"] == f"bytes 100-{len(_PAYLOAD) - 1}/{len(_PAYLOAD)}"
    assert resumed.content == _PAYLOAD[100:]

    tampered = path.replace("signature=", "signature=0")
    assert client.get(tampered).status_code == 403
    assert client.get(f"/models/{_MODEL}/files/other.bin?signature=x&expires=1").status_code == 404
