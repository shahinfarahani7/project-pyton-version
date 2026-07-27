from __future__ import annotations

import ipaddress
from urllib.parse import urlparse

BLOCKED_HOSTNAMES = frozenset(
    {
        "localhost",
        "metadata.google.internal",
        "metadata.google",
        "169.254.169.254",
    }
)


def _is_blocked_ip(value: ipaddress.IPv4Address | ipaddress.IPv6Address) -> bool:
    return (
        value.is_private
        or value.is_loopback
        or value.is_link_local
        or value.is_multicast
        or value.is_reserved
        or value.is_unspecified
    )


def validate_webhook_url(url: str) -> None:
    parsed = urlparse(url)
    if parsed.scheme not in {"https"}:
        raise ValueError("WEBHOOK_URL_SCHEME_FORBIDDEN")
    if parsed.username or parsed.password:
        raise ValueError("WEBHOOK_URL_CREDENTIALS_FORBIDDEN")
    hostname = parsed.hostname
    if not hostname:
        raise ValueError("WEBHOOK_URL_HOST_INVALID")
    lowered = hostname.lower()
    if lowered in BLOCKED_HOSTNAMES or lowered.endswith(".local"):
        raise ValueError("WEBHOOK_URL_HOST_FORBIDDEN")
    try:
        ip = ipaddress.ip_address(lowered)
    except ValueError:
        if lowered.endswith(".internal"):
            raise ValueError("WEBHOOK_URL_HOST_FORBIDDEN") from None
        return
    if _is_blocked_ip(ip):
        raise ValueError("WEBHOOK_URL_PRIVATE_ADDRESS")
