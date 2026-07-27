from __future__ import annotations

from collections import defaultdict
from typing import Any


def detect_collusion(*, links: list[dict[str, str]]) -> dict[str, Any]:
    device_accounts: dict[str, set[str]] = defaultdict(set)
    for link in links:
        device_accounts[link["deviceId"]].add(link["accountId"])
    colluding_accounts: set[str] = set()
    for accounts in device_accounts.values():
        if len(accounts) >= 2:
            colluding_accounts.update(accounts)
    return {
        "collusionDetected": bool(colluding_accounts),
        "linkedAccounts": sorted(colluding_accounts),
        "signal": "linkedAccounts" if colluding_accounts else None,
    }


def graph_signals(*, links: list[dict[str, str]]) -> dict[str, bool]:
    collusion = detect_collusion(links=links)
    return {
        "linkedAccounts": collusion["collusionDetected"],
        "impossibleSpeed": False,
        "goldenFailure": False,
        "invalidModelDigest": False,
        "replayNonce": False,
    }
