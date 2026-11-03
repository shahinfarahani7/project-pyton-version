from __future__ import annotations

import hashlib
from collections.abc import Iterator

import pytest
from edgemint.building_blocks.settings import get_settings
from edgemint.services import worker_gateway
from edgemint.services.worker_registry import app
from edgemint.workers.app_release import clear_worker_app_release_cache
from fastapi.testclient import TestClient


@pytest.fixture(autouse=True)
def _clear_release_state() -> Iterator[None]:
    clear_worker_app_release_cache()
    get_settings.cache_clear()
    yield
    clear_worker_app_release_cache()
    get_settings.cache_clear()


def _clear_release_env(monkeypatch: pytest.MonkeyPatch) -> None:
    for name in (
        "EDGEMINT_WORKER_APP_RELEASE_VERSION_NAME",
        "EDGEMINT_WORKER_APP_RELEASE_VERSION_CODE",
        "EDGEMINT_WORKER_APP_RELEASE_APK_PATH",
        "EDGEMINT_WORKER_APP_RELEASE_SHA256",
        "EDGEMINT_WORKER_APP_RELEASE_NOTES",
        "EDGEMINT_WORKER_APP_RELEASE_MANDATORY",
        "EDGEMINT_WORKER_MODEL_RELEASE_VERSION_ID",
        "EDGEMINT_WORKER_MODEL_RELEASE_SHA256",
        "EDGEMINT_WORKER_MODEL_RELEASE_FILE_NAME",
        "EDGEMINT_WORKER_MODEL_RELEASE_NOTES",
    ):
        monkeypatch.delenv(name, raising=False)


def test_blank_release_env_stays_unconfigured(monkeypatch: pytest.MonkeyPatch) -> None:
    _clear_release_env(monkeypatch)
    monkeypatch.setenv("EDGEMINT_WORKER_APP_RELEASE_VERSION_CODE", "")
    monkeypatch.setenv("EDGEMINT_WORKER_APP_RELEASE_MANDATORY", "")
    get_settings.cache_clear()
    settings = get_settings()
    assert settings.worker_app_release_version_code is None
    assert settings.worker_app_release_mandatory is False
    assert settings.worker_app_release_version_name is None


def test_unconfigured_release_is_hidden(monkeypatch: pytest.MonkeyPatch) -> None:
    _clear_release_env(monkeypatch)
    get_settings.cache_clear()
    response = TestClient(app).get("/worker-app/release")
    assert response.status_code == 404
    assert response.json()["code"] == "WORKER_APP_RELEASE_UNCONFIGURED"


def test_partial_release_configuration_is_rejected(monkeypatch: pytest.MonkeyPatch) -> None:
    _clear_release_env(monkeypatch)
    monkeypatch.setenv("EDGEMINT_WORKER_APP_RELEASE_VERSION_NAME", "5.1.0")
    get_settings.cache_clear()
    response = TestClient(app).get("/worker-app/release")
    assert response.status_code == 503
    assert response.json()["code"] == "WORKER_APP_RELEASE_INVALID"


def test_published_release_is_checksummed_before_download(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path,
) -> None:
    payload = b"worker-apk-bytes"
    digest = hashlib.sha256(payload).hexdigest()
    apk = tmp_path / "app-release.apk"
    apk.write_bytes(payload)
    _clear_release_env(monkeypatch)
    monkeypatch.setenv("EDGEMINT_WORKER_APP_RELEASE_VERSION_NAME", "5.1.0")
    monkeypatch.setenv("EDGEMINT_WORKER_APP_RELEASE_VERSION_CODE", "40200")
    monkeypatch.setenv("EDGEMINT_WORKER_APP_RELEASE_APK_PATH", str(apk))
    monkeypatch.setenv("EDGEMINT_WORKER_APP_RELEASE_SHA256", digest)
    monkeypatch.setenv("EDGEMINT_WORKER_APP_RELEASE_NOTES", "Fixes startup")
    monkeypatch.setenv("EDGEMINT_WORKER_APP_RELEASE_MANDATORY", "true")
    get_settings.cache_clear()

    client = TestClient(app)
    response = client.get("/worker-app/release")
    assert response.status_code == 200
    body = response.json()
    assert body == {
        "versionName": "5.1.0",
        "versionCode": 40200,
        "downloadPath": "/worker-app/release/apk",
        "sha256": digest,
        "sizeBytes": len(payload),
        "mandatory": True,
        "target": "application",
        "notes": "Fixes startup",
    }
    download = client.get("/worker-app/release/apk")
    assert download.status_code == 200
    assert download.content == payload

    monkeypatch.setenv("EDGEMINT_WORKER_APP_RELEASE_SHA256", "0" * 64)
    get_settings.cache_clear()
    clear_worker_app_release_cache()
    mismatch = client.get("/worker-app/release/apk")
    assert mismatch.status_code == 503
    assert mismatch.json()["code"] == "WORKER_APP_RELEASE_HASH_MISMATCH"


def test_model_release_is_not_an_application_package(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    _clear_release_env(monkeypatch)
    monkeypatch.setenv("EDGEMINT_WORKER_MODEL_RELEASE_VERSION_ID", "mdv_gemma_4_e4b_it")
    monkeypatch.setenv("EDGEMINT_WORKER_MODEL_RELEASE_SHA256", "ab" * 32)
    monkeypatch.setenv("EDGEMINT_WORKER_MODEL_RELEASE_FILE_NAME", "gemma-4-E4B-it.litertlm")
    monkeypatch.setenv("EDGEMINT_WORKER_MODEL_RELEASE_NOTES", "Refresh Gemma")
    get_settings.cache_clear()

    client = TestClient(app)
    response = client.get("/worker-app/release")
    assert response.status_code == 200
    assert response.json() == {
        "target": "model",
        "modelVersionId": "mdv_gemma_4_e4b_it",
        "artifactSha256": "ab" * 32,
        "fileName": "gemma-4-E4B-it.litertlm",
        "notes": "Refresh Gemma",
    }
    apk = client.get("/worker-app/release/apk")
    assert apk.status_code == 404
    assert apk.json()["code"] == "WORKER_APP_RELEASE_UNCONFIGURED"


def test_app_and_model_updates_are_published_together(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path,
) -> None:
    payload = b"worker-apk-bytes"
    digest = hashlib.sha256(payload).hexdigest()
    apk = tmp_path / "app-release.apk"
    apk.write_bytes(payload)
    _clear_release_env(monkeypatch)
    monkeypatch.setenv("EDGEMINT_WORKER_APP_RELEASE_VERSION_NAME", "5.1.0")
    monkeypatch.setenv("EDGEMINT_WORKER_APP_RELEASE_VERSION_CODE", "40200")
    monkeypatch.setenv("EDGEMINT_WORKER_APP_RELEASE_APK_PATH", str(apk))
    monkeypatch.setenv("EDGEMINT_WORKER_APP_RELEASE_SHA256", digest)
    monkeypatch.setenv("EDGEMINT_WORKER_MODEL_RELEASE_VERSION_ID", "mdv_gemma_4_e4b_it")
    monkeypatch.setenv("EDGEMINT_WORKER_MODEL_RELEASE_SHA256", "cd" * 32)
    monkeypatch.setenv("EDGEMINT_WORKER_MODEL_RELEASE_FILE_NAME", "gemma-4-E4B-it.litertlm")
    get_settings.cache_clear()

    response = TestClient(app).get("/worker-app/release")
    assert response.status_code == 200
    body = response.json()
    assert [item["target"] for item in body["updates"]] == ["application", "model"]


def test_worker_gateway_streams_the_apk() -> None:
    assert worker_gateway.response_should_stream("/worker-app/release/apk") is True
    assert worker_gateway.response_should_stream("/worker-app/release") is False
    assert worker_gateway.response_should_stream("/models/mdv/artifact") is True
