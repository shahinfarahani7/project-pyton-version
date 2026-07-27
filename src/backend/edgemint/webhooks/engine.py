from __future__ import annotations

from typing import Any

from edgemint.webhooks.policy import load_webhook_policy


def _is_success_status(status: int, ranges: list[str]) -> bool:
    for item in ranges:
        if "-" in item:
            start_text, end_text = item.split("-", 1)
            if int(start_text) <= status <= int(end_text):
                return True
        elif status == int(item):
            return True
    return False


def evaluate_delivery(raw_input: dict[str, Any]) -> dict[str, Any]:
    policy = load_webhook_policy().spec
    status = int(raw_input["httpStatus"])
    attempt = int(raw_input["attempt"])
    success = _is_success_status(status, policy["successStatusRanges"])
    retry_codes = set(policy["retryStatusCodes"])
    maximum_attempts = int(policy["retry"]["maximumAttempts"])
    retry = not success and status in retry_codes and attempt < maximum_attempts
    delays = policy["retry"]["delaysSeconds"]
    delay = delays[min(attempt - 1, len(delays) - 1)] if retry else 0
    terminal = not success and not retry
    return {"success": success, "retry": retry, "baseDelaySeconds": delay, "terminal": terminal}
