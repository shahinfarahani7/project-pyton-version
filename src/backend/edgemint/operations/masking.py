from __future__ import annotations

from typing import Any

SENSITIVE_KEYS = frozenset({"email", "phone", "iban", "accountNumber", "secret", "token"})


def mask_sensitive_payload(payload: dict[str, Any]) -> dict[str, Any]:
    masked: dict[str, Any] = {}
    for key, value in payload.items():
        if key in SENSITIVE_KEYS and isinstance(value, str):
            masked[key] = _mask_value(value)
        elif isinstance(value, dict):
            masked[key] = mask_sensitive_payload(value)
        else:
            masked[key] = value
    return masked


def _mask_value(value: str) -> str:
    if len(value) <= 4:
        return "****"
    return f"{value[:2]}***{value[-2:]}"
