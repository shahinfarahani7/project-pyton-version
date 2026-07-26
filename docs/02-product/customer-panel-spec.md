# Customer Panel Specification

## Navigation
Dashboard, Tasks, Files, Models, API Keys, Webhooks, Usage, Billing, Team, Workspaces, Security, Audit and Support.

## Task creation
1. select task type and model/execution policy.
2. upload or reference input.
3. configure priority, verification, region, retention and callback.
4. request a quote.
5. show price, expiry, SLA and data policy.
6. submit with an idempotency key.

## Task detail tabs
Overview, Input, Revisions, Attempts, Results, Verification, Cost, Events and Audit.

## Failed result actions
- `Retry same revision` creates an attempt.
- `Edit and create revision` clones the configuration into a new draft revision.
- `Open dispute` creates a dispute and freezes only policy-defined financial amounts.

Every mutation requires optimistic concurrency through `If-Match` where the API declares an ETag.
