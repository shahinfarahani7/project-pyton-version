#!/usr/bin/env python3
"""Validate progressive canary release evidence for WP-250."""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

REQUIRED_STAGES = ("internal", "1-percent", "5-percent", "25-percent", "100-percent")
REQUIRED_FILES = (
    "summary.json",
    "e2e-paid-ocr-journey.json",
    "worker-payout-journey.json",
    "rollback-test.json",
)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("canary_dir", nargs="?", default="evidence/actual/canary")
    args = parser.parse_args()

    canary_dir = Path(args.canary_dir)
    if not canary_dir.is_absolute():
        canary_dir = ROOT / canary_dir

    errors: list[str] = []
    if not canary_dir.is_dir():
        errors.append(f"canary evidence directory missing: {canary_dir}")

    for name in REQUIRED_FILES:
        if not (canary_dir / name).is_file():
            errors.append(f"missing canary evidence: {name}")

    if errors:
        print(json.dumps({"status": "failed", "errors": errors}, indent=2))
        return 1

    summary = json.loads((canary_dir / "summary.json").read_text(encoding="utf-8"))
    e2e = json.loads((canary_dir / "e2e-paid-ocr-journey.json").read_text(encoding="utf-8"))
    payout = json.loads((canary_dir / "worker-payout-journey.json").read_text(encoding="utf-8"))
    rollback = json.loads((canary_dir / "rollback-test.json").read_text(encoding="utf-8"))

    if summary.get("status") != "passed":
        errors.append("canary summary status is not passed")

    stages = summary.get("stages", {})
    for stage in REQUIRED_STAGES:
        entry = stages.get(stage)
        if not entry:
            errors.append(f"missing canary stage summary: {stage}")
            continue
        if entry.get("status") != "passed":
            errors.append(f"canary stage not passed: {stage}")
        if not entry.get("rollbackReady"):
            errors.append(f"canary stage rollback not ready: {stage}")
        if entry.get("automaticRollbackTriggered"):
            errors.append(f"canary stage triggered automatic rollback: {stage}")
        for metric in ("sloMet", "errorBudgetMet", "securityGateMet", "marginMet", "reconciliationMet"):
            if not entry.get(metric):
                errors.append(f"canary stage missing {metric}: {stage}")

    if not e2e.get("customerChargeCompleted"):
        errors.append("paid OCR journey missing customer charge")
    if not e2e.get("taskVerified"):
        errors.append("paid OCR journey missing verified task")
    if not payout.get("workerRewardAccrued"):
        errors.append("worker payout journey missing reward accrual")
    if not payout.get("payoutCompleted"):
        errors.append("worker payout journey missing payout completion")
    if not payout.get("ledgerReconciled"):
        errors.append("worker payout journey missing ledger reconciliation")
    if not rollback.get("rollbackExecuted"):
        errors.append("rollback test not executed")
    if not rollback.get("rollbackVerified"):
        errors.append("rollback test not verified")

    result = {
        "status": "passed" if not errors else "failed",
        "canaryDir": str(canary_dir.relative_to(ROOT)),
        "stagesPassed": len([s for s in stages.values() if s.get("status") == "passed"]),
        "errors": errors,
    }
    print(json.dumps(result, indent=2))
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
