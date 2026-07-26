# Service Boundaries

| Service | Owns | Must not own |
|---|---|---|
| Identity | users, sessions, OAuth | task/ledger data |
| Tenant | organizations, workspaces, memberships, API keys | billing calculations |
| File | upload sessions, assets, scanning, retention | task state |
| Task | tasks, revisions, attempts | worker device truth, ledger balances |
| Quote/Pricing | deterministic quotes and rule trace | charging ledger |
| Scheduler/Router | automatic leases and deterministic selection decisions | final verification |
| Worker Gateway | sessions, heartbeat and protocol transport | business source of truth |
| Result | immutable result artifacts | customer charge |
| Verification | quality decision and consensus | payment settlement |
| Billing | usage, subscription, invoice, reservation | token transfer |
| Ledger | financial postings and balances | pricing rules |
| Reward | accrual and holds | token exchange rate |
| Claim | epochs, conversion and settlement | task reward calculation |
| Model Registry | signed model/policy artifacts | worker selection |
| Webhook | endpoint and delivery | domain transaction state |
| Fraud | signals/cases/actions | silent ledger edits |
