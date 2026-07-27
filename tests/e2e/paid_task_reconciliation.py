from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "src" / "backend"))

from edgemint.billing.errors import FinanceServiceError  # noqa: E402
from edgemint.billing.service import FinanceService  # noqa: E402
from edgemint.ledger.engine import compute_ledger  # noqa: E402
from edgemint.pricing.engine import PriceInput, PricingEngine  # noqa: E402
from edgemint.rewards.engine import compute_reward  # noqa: E402

PRICE_INPUT = {
    "taskType": "document.ocr",
    "quantity": 100,
    "plan": "startup",
    "priority": "standard",
    "verification": "standard",
    "region": "eu-central",
    "executionPolicy": "edge_only",
    "retention": "default",
}

REWARD_INPUT = {
    "taskType": "document.ocr",
    "quanta": 1,
    "tier": "T2",
    "qualityMilli": 950,
    "urgency": "standard",
    "scarcityBps": 10000,
    "reliabilityBps": 10000,
}


def contract_checks() -> list[str]:
    errors: list[str] = []
    billing_src = (ROOT / "src/backend/edgemint/services/billing.py").read_text(encoding="utf-8")
    ledger_src = (ROOT / "src/backend/edgemint/services/ledger.py").read_text(encoding="utf-8")
    reward_src = (ROOT / "src/backend/edgemint/services/reward.py").read_text(encoding="utf-8")
    for route in [
        '"/internal/billing/reservations:capture"',
        '"/internal/billing/tasks:finalize"',
        '"/internal/billing/reconciliation:daily"',
    ]:
        if route not in billing_src:
            errors.append(f"billing api missing route {route}")
    if '"/internal/ledger/post"' not in ledger_src:
        errors.append("ledger api missing post route")
    if '"/internal/reward/compute"' not in reward_src:
        errors.append("reward api missing compute route")
    return errors


def semantic_checks() -> list[str]:
    errors: list[str] = []
    entries, expected = compute_ledger({"chargeMicros": 500, "rewardMicros": 100, "refundMicros": 0})
    if not expected["balancedByCurrency"]:
        errors.append("ledger not balanced")
    reward = compute_reward(REWARD_INPUT)
    if reward["rewardMicros"] <= 0:
        errors.append("reward should be positive for eligible input")

    service = FinanceService()
    price = PricingEngine().quote(PriceInput.from_vector(PRICE_INPUT))
    service.capture_reservation(
        task_id="tsk_e2e",
        quote_id="qte_e2e",
        amount_micro_eur=price.charge_micros,
        available_micro_eur=price.charge_micros,
    )
    body = service.finalize_paid_task(
        idempotency_key="idem-e2e",
        task_id="tsk_e2e",
        task_revision_id="rev_e2e",
        result_id="res_e2e",
        verification_id="ver_e2e",
        price_input=PRICE_INPUT,
        reward_input=REWARD_INPUT,
    )
    if body["chargedMicros"] != price.charge_micros:
        errors.append("charged amount mismatch")
    report = service.run_daily_reconciliation()
    if report["unexplainedDifferenceMicros"] != 0:
        errors.append("daily reconciliation has unexplained difference")
    try:
        service.finalize_paid_task(
            idempotency_key="idem-e2e",
            task_id="tsk_e2e",
            task_revision_id="rev_e2e",
            result_id="res_e2e",
            verification_id="ver_e2e",
            price_input=PRICE_INPUT,
            reward_input=REWARD_INPUT,
        )
        errors.append("duplicate finalize should fail")
    except FinanceServiceError as exc:
        if exc.code != "IDEMPOTENCY_CONFLICT":
            errors.append("duplicate finalize unexpected error")
    close = service.financial_close_report()
    if not close["immutableEvidence"]:
        errors.append("financial close evidence not immutable")
    return errors


def main() -> int:
    errors = contract_checks() + semantic_checks()
    if errors:
        for item in errors:
            print(item)
        return 1
    print("paid task reconciliation e2e checks passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
