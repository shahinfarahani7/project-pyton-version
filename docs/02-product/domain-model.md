# Domain Model

The canonical chain is Organization → Workspace → Task → immutable TaskRevision → TaskAttempt → server-created AssignmentLease → Result → Verification → UsageEvent → LedgerTransaction → RewardAccrual. Files, quotes, reservations, policies, models, webhooks, disputes, and claims are separate aggregates with explicit ownership and immutable historical evidence.
