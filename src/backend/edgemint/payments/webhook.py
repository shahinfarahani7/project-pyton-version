from __future__ import annotations

import hashlib
import hmac
import time


def compute_stripe_signature(*, secret: str, payload: bytes, timestamp: int) -> str:
    signed = f"{timestamp}.".encode("ascii") + payload
    digest = hmac.new(secret.encode("utf-8"), signed, hashlib.sha256).hexdigest()
    return f"t={timestamp},v1={digest}"


def verify_stripe_webhook(
    *,
    payload: bytes,
    signature_header: str,
    secret: str,
    tolerance_seconds: int = 300,
    now_epoch: int | None = None,
) -> bool:
    now = now_epoch if now_epoch is not None else int(time.time())
    parts = dict(item.split("=", 1) for item in signature_header.split(",") if "=" in item)
    timestamp = int(parts.get("t", "0"))
    signature = parts.get("v1", "")
    if abs(now - timestamp) > tolerance_seconds:
        return False
    expected = compute_stripe_signature(secret=secret, payload=payload, timestamp=timestamp)
    expected_sig = expected.split("v1=", 1)[1]
    return hmac.compare_digest(expected_sig, signature)
