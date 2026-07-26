# Operations Console Specification

Authorized operators can inspect but not silently mutate evidence.

Modules: live operations, task recovery, worker health, fraud cases, model rollouts, policy registry, pricing approvals, ledger reconciliation, reward claims, webhook delivery, incidents and audit.

Sensitive actions require reason, ticket reference, short-lived elevated permission and dual approval where defined. A manual correction creates a compensating event/ledger transaction; it never edits the original row.
