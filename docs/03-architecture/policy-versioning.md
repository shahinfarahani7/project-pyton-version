# Policy Versioning and Activation

Policies are immutable after publication. Activation creates a separate record containing environment, scope, effective time, approvers and canonical SHA-256. A task revision pins all policy references used for quote, routing, verification, data and rewards. Rollback activates a previous version; it does not modify historical tasks. Draft policies never affect production.
