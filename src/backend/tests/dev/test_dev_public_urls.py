from __future__ import annotations

import pytest

from edgemint.dev.dev_public_urls import dev_api_public_base


def _clear_dev_public_env(monkeypatch: pytest.MonkeyPatch) -> None:
    for name in (
        "EDGEMINT_DEV_PUBLIC_BASE_URL",
        "EDGEMINT_DEV_API_PUBLIC_URL",
        "EDGEMINT_WORKER_PUBLIC_URL",
    ):
        monkeypatch.delenv(name, raising=False)


def test_dev_api_public_base_defaults_to_emulator_host(monkeypatch: pytest.MonkeyPatch) -> None:
    _clear_dev_public_env(monkeypatch)
    assert dev_api_public_base() == "http://10.0.2.2:8080"


def test_dev_api_public_base_honors_dev_public_base_url(monkeypatch: pytest.MonkeyPatch) -> None:
    _clear_dev_public_env(monkeypatch)
    monkeypatch.setenv("EDGEMINT_DEV_PUBLIC_BASE_URL", "http://172.20.34.71:8080/")
    assert dev_api_public_base() == "http://172.20.34.71:8080"


def test_dev_api_public_base_honors_legacy_api_public_url(monkeypatch: pytest.MonkeyPatch) -> None:
    _clear_dev_public_env(monkeypatch)
    monkeypatch.setenv("EDGEMINT_DEV_API_PUBLIC_URL", "http://172.20.34.71:8080/")
    assert dev_api_public_base() == "http://172.20.34.71:8080"


def test_dev_public_base_url_takes_precedence_over_legacy_api_url(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    _clear_dev_public_env(monkeypatch)
    monkeypatch.setenv("EDGEMINT_DEV_PUBLIC_BASE_URL", "http://192.168.1.10:8080")
    monkeypatch.setenv("EDGEMINT_DEV_API_PUBLIC_URL", "http://172.20.34.71:8080")
    assert dev_api_public_base() == "http://192.168.1.10:8080"


def test_dev_api_public_base_derives_from_worker_public_url(monkeypatch: pytest.MonkeyPatch) -> None:
    _clear_dev_public_env(monkeypatch)
    monkeypatch.setenv("EDGEMINT_WORKER_PUBLIC_URL", "http://172.20.34.71:8081")
    assert dev_api_public_base() == "http://172.20.34.71:8080"
