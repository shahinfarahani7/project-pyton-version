from __future__ import annotations

import hashlib
import hmac
import time


def sign_payload(*, secret: str, timestamp: str, raw_body: bytes) -> str:
    signed_input = f"{timestamp}.".encode("ascii") + raw_body
    return hmac.new(secret.encode("utf-8"), signed_input, hashlib.sha256).hexdigest()


def verify_signature(
    *,
    secrets: list[str],
    timestamp: str,
    raw_body: bytes,
    signature: str,
    tolerance_seconds: int,
    now_epoch: int | None = None,
) -> bool:
    now = now_epoch if now_epoch is not None else int(time.time())
    try:
        ts = int(timestamp)
    except ValueError:
        return False
    if abs(now - ts) > tolerance_seconds:
        return False
    for secret in secrets:
        if not secret:
            continue
        expected = sign_payload(secret=secret, timestamp=timestamp, raw_body=raw_body)
        if hmac.compare_digest(expected, signature):
            return True
    return False
