# Implementation Contract

This document resolves terminology and ownership. Where another document conflicts, this contract and active DSL win.

## Aggregate ownership

- **Task**: customer intent and current revision pointer. It does not own execution-attempt state.
- **TaskRevision**: immutable input, configuration, server-derived execution requirements, policy references and payload hash.
- **Quote**: immutable price, cost and tax estimate with expiry and policy hashes.
- **CreditReservation**: customer balance hold for one revision and quote.
- **TaskAttempt**: one logical execution attempt for one revision.
- **AssignmentLease**: server-created exclusive execution authority for one Worker device, identified by a secret lease token and monotonic fencing token. No assignment-offer aggregate or per-task Worker acceptance exists.
- **Result**: immutable Worker submission identified by checksum, assignment, attempt, fence and Worker signature.
- **Verification**: decision over one or more results.
- **UsageEvent**: billable measurement accepted after verification.
- **RewardAccrual**: Worker liability denominated in integer micro-EUR.
- **Claim/Payout**: regulated fiat payout workflow. Public token sale and on-chain per-task settlement are outside GA1 and remain disabled.

## Numeric conventions

- `*Micros` fields are signed 64-bit integers representing 1/1,000,000 of a currency unit.
- `*Bps` fields are integer basis points where 10,000 = 100%.
- JSON APIs represent 64-bit integers as decimal strings when JavaScript precision could be exceeded.
- No financial calculation uses binary floating point.

## Time and identifiers

- Internal PostgreSQL primary keys are `uniqueidentifier` values generated with `gen_random_uuid()` where database-generated.
- Public IDs are opaque type-prefixed ULIDs and must never encode tenant information or database sequence values.
- Stored timestamps are UTC `datetime2(7)` values; API timestamps are RFC3339 with milliseconds and `Z`.
- Deadlines use absolute server-authoritative timestamps, never client-derived clocks.

## Transaction boundaries

1. Creating a task revision, quote, credit reservation and outbox evidence follows the documented admission orchestration and idempotency boundary.
2. Router queue claim, final eligibility revalidation, capacity reservation, assignment lease creation, fence allocation, attempt transition and outbox insertion are server-controlled and fail closed. No Worker confirmation is requested.
3. Worker delivery acknowledgement is transport receipt only. The Agent validates the signed lease and automatically reports `started`; it cannot Accept or Reject the task.
4. Completing an assignment accepts a result only when its assignment, attempt, device, lease and fencing token are current.
5. Verification finalization, usage creation, customer charge, reward accrual and outbox evidence are idempotent and ledger-safe.
6. GA1 payout is fiat through the approved payout rail. Token settlement paths remain disabled until a separately approved release scope enables them.

## Retry, reassignment and edit

- Transport retry: same idempotency key and same canonical payload returns the original response.
- Worker reassignment: same `TaskAttempt`, new exclusive lease and higher fence token, within the configured reassignment budget.
- Execution retry: new `TaskAttempt` for the same immutable revision.
- Customer edit: new `TaskRevision`; prior attempts and financial evidence remain immutable.
- Policy re-evaluation: new quote; an active reservation is released before its replacement is created.
- Reassignment-budget exhaustion terminally expires that attempt and hands control to retry or policy-controlled Cloud fallback; it never spins indefinitely in `matching`.

## Failure ownership

The failure taxonomy in `docs/04-api/error-catalog.md` determines who pays and whether the Worker is rewarded. No implementation may infer financial behavior from HTTP status alone. Machine-only unavailability must match the latest persisted health snapshot or immutable revision requirements; otherwise no reassignment occurs.
