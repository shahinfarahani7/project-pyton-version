from __future__ import annotations

import os

import pytest

from edgemint.dev.dev_public_urls import dev_api_public_base


def test_dev_api_public_base_defaults_to_emulator_host(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("EDGEMINT_DEV_API_PUBLIC_URL", raising=False)
    monkeypatch.delenv("EDGEMINT_WORKER_PUBLIC_URL", raising=False)
    assert dev_api_public_base() == "http://10.0.2.2:8080"


def test_dev_api_public_base_honors_explicit_override(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("EDGEMINT_DEV_API_PUBLIC_URL", "http://172.20.34.71:8080/")
    assert dev_api_public_base() == "http://172.20.34.71:8080"


def test_dev_api_public_base_derives_from_worker_public_url(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("EDGEMINT_DEV_API_PUBLIC_URL", raising=False)
    monkeypatch.setenv("EDGEMINT_WORKER_PUBLIC_URL", "http://172.20.34.71:8081")
    assert dev_api_public_base() == "http://172.20.34.71:8080"
