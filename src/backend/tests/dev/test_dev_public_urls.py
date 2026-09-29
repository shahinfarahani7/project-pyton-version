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


def test_dev_api_public_base_does_not_default_to_emulator_alias(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    _clear_dev_public_env(monkeypatch)
    base = dev_api_public_base()
    assert "10.0.2.2" not in base
    assert base == "http://127.0.0.1:8080"


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


def test_configured_base_is_used_for_task_urls_without_emulator_alias(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    from edgemint.dev import worker_assignments, worker_task_inputs

    _clear_dev_public_env(monkeypatch)
    base = "http://172.20.34.71:8080"
    monkeypatch.setenv("EDGEMINT_DEV_PUBLIC_BASE_URL", base)
    task_id = "tsk_lan_worker_url"
    try:
        assignment = worker_assignments.enqueue_dev_assignment(
            task_id=task_id,
            task_type="text.direct",
        )
        worker_task_inputs.register_task(
            task_id=task_id,
            task_type="document.ocr",
        )
        manifest = worker_task_inputs.input_manifest(task_id)
        assert manifest is not None
        urls = [
            assignment["inputManifestUrl"],
            assignment["outputUploadUrl"],
            manifest["inputContentUrl"],
        ]
        assert urls == [
            f"{base}/v1/dev/worker/tasks/{task_id}/input",
            f"{base}/v1/dev/worker/tasks/{task_id}/output",
            f"{base}/v1/dev/worker/tasks/{task_id}/input/content",
        ]
        rendered = "\n".join(urls)
        assert "10.0.2.2" not in rendered
        assert all(url.startswith(base) for url in urls)
    finally:
        worker_assignments.cancel_dev_assignment(task_id)
