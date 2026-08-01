from __future__ import annotations

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
