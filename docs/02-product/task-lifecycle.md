# Task Lifecycle

Task states are draft, submitted, active, completed, failed, cancelled, expired, and disputed. Customer edits create a new immutable revision. Execution retries create a new attempt. State transitions use compare-and-swap, version checks, idempotency keys, and domain events. Historical revisions, attempts, results, charges, and rewards are never overwritten.
