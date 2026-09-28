from __future__ import annotations

import os
from urllib.parse import urlparse

_EMULATOR_API_GATEWAY_BASE = "http://10.0.2.2:8080"
_EXPLICIT_BASE_ENV_VARS = (
    "EDGEMINT_DEV_PUBLIC_BASE_URL",
    "EDGEMINT_DEV_API_PUBLIC_URL",
)


def _normalized_base_url(raw: str) -> str:
    return raw.strip().rstrip("/")


def _explicit_dev_public_base() -> str | None:
    for name in _EXPLICIT_BASE_ENV_VARS:
        raw = os.environ.get(name, "").strip()
        if raw:
            return _normalized_base_url(raw)
    return None


def dev_api_public_base() -> str:
    """Host-reachable api-gateway base URL embedded in dev worker assignments."""
    explicit = _explicit_dev_public_base()
    if explicit:
        return explicit

    worker_public = os.environ.get("EDGEMINT_WORKER_PUBLIC_URL", "").strip().rstrip("/")
    if worker_public:
        parsed = urlparse(worker_public if "://" in worker_public else f"http://{worker_public}")
        host = parsed.hostname or "10.0.2.2"
        return f"http://{host}:8080"

    # Android Studio emulator alias to the host PC (api-gateway on :8080).
    return _EMULATOR_API_GATEWAY_BASE
