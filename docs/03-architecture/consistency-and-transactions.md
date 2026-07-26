# Consistency and Transaction Model

Strong consistency is required for tenant authorization, idempotency, credit reservation, lease ownership, financial posting and claim reservation. Eventual consistency is acceptable for dashboards, search, analytics, notifications and worker availability projections.

No distributed transaction spans the database and providers. The system uses transactional outbox, idempotent provider commands, inbox deduplication and explicit reconciliation states.
