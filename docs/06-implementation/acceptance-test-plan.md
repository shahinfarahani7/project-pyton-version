# Acceptance Test Plan

Critical tests:
- replay every mutating API with same and changed idempotency payload.
- submit, quote, reserve, queue, assign, execute, verify, charge and reward end-to-end.
- close app during download, model load, execution, upload and verification wait.
- expire an undelivered or not-started automatic lease, reassign it, and reject a late result with the stale fencing token.
- edit a failed task and prove previous revision hash/result/ledger remain unchanged.
- run consensus with same account/device/network cluster and verify anti-affinity.
- force cloud fallback and verify price/region/policy.
- inject ledger imbalance and ensure financial finalization fails closed.
- simulate payment callback duplication and ambiguous token transfer.
- test cross-tenant IDs against every read/write endpoint.
