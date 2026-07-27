from __future__ import annotations

from functools import lru_cache
from pathlib import Path
from typing import Any

import yaml

SUPPORTED_PAYOUT_COUNTRIES = frozenset({"DE", "FR", "NL", "BE", "AT", "IE", "ES", "IT", "PT", "FI"})
SANCTIONS_BLOCKED_COUNTRIES = frozenset({"KP", "IR", "SY", "CU"})


@lru_cache
def load_payments_policy() -> dict[str, Any]:
    path = Path(__file__).resolve().parents[4] / "production" / "canonical-decisions.yaml"
    document = yaml.safe_load(path.read_text(encoding="utf-8"))
    return document["spec"]["payments"]


def country_allows_payout(country_code: str) -> bool:
    normalized = country_code.upper()
    if normalized in SANCTIONS_BLOCKED_COUNTRIES:
        return False
    return normalized in SUPPORTED_PAYOUT_COUNTRIES
