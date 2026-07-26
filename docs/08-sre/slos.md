# Service Level Objectives

Initial internal SLOs, subject to load validation:
- public task intake availability 99.95% monthly.
- accepted request durability 99.999%.
- quote p95 < 500 ms excluding external tax provider.
- standard task assignment p95 < 30 s when eligible supply exists.
- webhook first delivery p95 < 10 s after terminal event.
- financial reconciliation completes by 02:00 UTC daily with zero unresolved imbalance.
- worker gateway heartbeat ingestion p99 < 2 s.

Customer SLA plans may be lower than internal SLOs. Error budgets and exclusions are defined per service, not globally.
