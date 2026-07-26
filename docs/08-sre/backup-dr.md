# Backup and Disaster Recovery

- PostgreSQL automated backups, point-in-time restore, encrypted snapshots, transaction-log protection, and quarterly restore drills.
- object storage versioning and lifecycle; model artifacts replicated separately from customer payload retention.
- policy registry and signing keys have offline recovery procedures.
- target baseline: control-plane RPO <= 5 minutes, RTO <= 60 minutes; financial ledger RPO approaches zero through synchronous database durability and provider reconciliation.
- region failover never bypasses customer data-region policy.
