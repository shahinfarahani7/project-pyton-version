from __future__ import annotations

import os
from urllib.parse import urlparse

_EXPLICIT_BASE_ENV_VARS = (
    "EDGEMINT_DEV_PUBLIC_BASE_URL",
    "EDGEMINT_DEV_API_PUBLIC_URL",
)
_UNCONFIGURED_BASE = "http://127.0.0.1:8080"


def _normalized_base_url(raw: str) -> str:
    return raw.strip().rstrip("/")


def _explicit_dev_public_base() -> str | None:
    for name in _EXPLICIT_BASE_ENV_VARS:
        raw = os.environ.get(name, "").strip()
        if raw:
            return _normalized_base_url(raw)
    return None


def dev_api_public_base() -> str:
    """Worker-reachable api-gateway base embedded in dev task URLs.

    Set ``EDGEMINT_DEV_PUBLIC_BASE_URL`` to the host a physical worker can
    reach (api-gateway, port 8080). One configured base is used for the
    input manifest, input content, and output upload URLs.
    """
    explicit = _explicit_dev_public_base()
    if explicit:
        return explicit

    worker_public = os.environ.get("EDGEMINT_WORKER_PUBLIC_URL", "").strip().rstrip("/")
    if worker_public:
        parsed = urlparse(worker_public if "://" in worker_public else f"http://{worker_public}")
        if parsed.hostname:
            return f"http://{parsed.hostname}:8080"

    return _UNCONFIGURED_BASE
