from __future__ import annotations

import os
from urllib.parse import urlparse


def dev_api_public_base() -> str:
    """Host-reachable api-gateway base URL embedded in dev worker assignments."""
    explicit = os.environ.get("EDGEMINT_DEV_API_PUBLIC_URL", "").strip().rstrip("/")
    if explicit:
        return explicit

    worker_public = os.environ.get("EDGEMINT_WORKER_PUBLIC_URL", "").strip().rstrip("/")
    if worker_public:
        parsed = urlparse(worker_public if "://" in worker_public else f"http://{worker_public}")
        host = parsed.hostname or "10.0.2.2"
        return f"http://{host}:8080"

    # Android Studio emulator alias to the host PC (api-gateway on :8080).
    return "http://10.0.2.2:8080"
