from __future__ import annotations

from collections import defaultdict
from typing import Any


def compute_ledger(raw_input: dict[str, Any]) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    charge = int(raw_input["chargeMicros"])
    worker_reward = int(raw_input["rewardMicros"])
    refund = int(raw_input["refundMicros"])
    entries: list[dict[str, Any]] = [
        {"account": "2000", "direction": "debit", "amount": charge, "currency": "EUR_MICROS"},
        {"account": "4000", "direction": "credit", "amount": charge, "currency": "EUR_MICROS"},
    ]
    if worker_reward:
        entries += [
            {
                "account": "5000",
                "direction": "debit",
                "amount": worker_reward,
                "currency": "EUR_REWARD_MICROS",
            },
            {
                "account": "2100",
                "direction": "credit",
                "amount": worker_reward,
                "currency": "EUR_REWARD_MICROS",
            },
        ]
    if refund:
        entries += [
            {"account": "4400", "direction": "debit", "amount": refund, "currency": "EUR_MICROS"},
            {"account": "2000", "direction": "credit", "amount": refund, "currency": "EUR_MICROS"},
        ]
    sums: dict[str, int] = defaultdict(int)
    for entry in entries:
        signed = entry["amount"] if entry["direction"] == "debit" else -entry["amount"]
        sums[entry["currency"]] += signed
    expected = {"balancedByCurrency": all(value == 0 for value in sums.values()), "currencies": sorted(sums)}
    return entries, expected
