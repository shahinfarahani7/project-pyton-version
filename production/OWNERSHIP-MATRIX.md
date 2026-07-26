# Service and Contract Ownership Matrix

| Service | Primary responsibility | Authoritative data | Public/internal surfaces | Primary emitted events | Team owner |
|---|---|---|---|---|---|
| API Gateway | Public edge, authentication handoff, throttling, request identity | No domain tables | Public OpenAPI routing | Request/security telemetry only | Platform API |
| Identity | Principals, credentials, sessions, permission context | principals, api_credentials | Identity and API-key operations | principal and api-key events | Identity & Security |
| Customer | Organizations, workspaces, membership, subscriptions | organizations, workspaces, workspace_members, workspace_invitations, subscriptions | Customer administration | organization/workspace/subscription events | Customer Platform |
| File | Secure upload, scan, retention, object metadata | files, file_upload_sessions | File operations | file lifecycle events | Data Intake |
| Task Intake | Task drafts, immutable revisions, admission, submission | tasks, task_revisions, task_state_history | Task operations | task/revision events | Task Platform |
| Pricing | Pricebooks, quotes, margin admission | price_books, quotes, promotion_reservations | Quote operations | quote/promotion events | Pricing & Finance |
| Router | Eligibility, queue fairness, scoring, attempts, atomic auto-leases and fencing | task_attempts, assignments, assignment_checkpoints | Internal routing/lease API | attempt/assignment/lease events | Routing |
| Worker Gateway | Device protocol, heartbeat, targeted lease delivery, automatic-start reporting and signed result transport | worker_sessions, worker_heartbeats | Worker Protobuf/API | connection/progress transport events | Worker Platform |
| Worker Registry | Worker/device identity, consent, preference, benchmark, trust | workers, worker_devices, worker_consents, worker_preferences, worker_benchmarks, device_challenges | Worker enrollment operations | worker lifecycle events | Worker Platform |
| Model Registry | Model profiles, versions, rollout, device install state | models, model_versions, model_rollouts, model_downloads, device_model_installs | Model administration and delivery | model lifecycle events | ML Platform |
| Result | Signed result intake and immutable result lineage | results | Result internal API | result-submitted events | Result Platform |
| Verification | Automatic, consensus, golden, and human-review decisions | verifications, verification_votes | Verification operations | verification events | Quality Platform |
| Billing | Usage capture, invoices, provider billing adapter | usage_events, invoices, credit_reservations | Billing and balance operations | usage/credit/invoice events | Finance Platform |
| Ledger | Double-entry accounting and reconciliation | ledger_accounts, ledger_transactions, ledger_entries, reconciliation_runs | Ledger/reconciliation operations | ledger/reconciliation events | Finance Platform |
| Reward | Worker/verifier accrual, hold, reversal, expiry | reward_accruals | Earnings operations | reward events | Worker Economy |
| Claim | Payout eligibility, reservation, batch, settlement | reward_claims, claim_batches, claim_batch_items, token_conversion_epochs | Claim operations | claim events | Worker Economy |
| Fraud | Fraud cases, risk actions, quarantine recommendations | fraud_cases | Fraud operations | fraud events | Trust & Safety |
| Webhook | Endpoint ownership, signed delivery, retry, replay, DLQ | webhook_endpoints, webhook_deliveries | Webhook operations | delivery events | Integration Platform |
| Notification | Email/push/in-app notification orchestration | Outbox-derived delivery metadata only | Internal notification API | delivery telemetry | Communications |
| Operations | Audited administrative workflows, incidents, policy controls | security_incidents, policy_documents, policy_activations, feature_flags, audit_events | Operations OpenAPI | incident/policy/kill-switch events | Operations Platform |

A service may read another service's data only through an approved contract or a documented read model. Direct cross-service table writes are forbidden. Shared database deployment does not imply shared ownership.
