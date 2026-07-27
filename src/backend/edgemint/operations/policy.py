from __future__ import annotations

HIGH_RISK_ACTIONS = frozenset(
    {
        "economy.kill_switch.activate",
        "worker.quarantine",
        "model.revoke",
        "task.force_verify",
        "ledger.reconcile.override",
    }
)

REASON_CODES = frozenset(
    {
        "customer_report",
        "fraud_investigation",
        "incident_response",
        "manual_reconciliation",
        "policy_exception",
        "security_review",
    }
)

ROLE_PERMISSIONS: dict[str, frozenset[str]] = {
    "operator.readonly": frozenset({"operations.read"}),
    "operator.standard": frozenset({"operations.read", "operations.mutate.low"}),
    "operator.approver": frozenset({"operations.read", "operations.mutate.low", "operations.approve"}),
    "operator.break_glass": frozenset(
        {"operations.read", "operations.mutate.low", "operations.approve", "operations.break_glass"}
    ),
}

BREAK_GLASS_TTL_MINUTES = 60
