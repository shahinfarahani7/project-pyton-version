# Task Status Projections

A Task exposes three independent status fields. Implementations must not collapse them into one enum.

## `lifecycleStatus`

Authoritative state of customer intent, owned by the Task aggregate and governed by `dsl/workflows/task-lifecycle.yaml`:

`draft → submitted → active → completed|failed|cancelled|expired → disputed where explicitly allowed`.

## `executionStatus`

Read projection of the current TaskAttempt. It is derived from `dsl/workflows/attempt-lifecycle.yaml` and is never written directly on Task:

`not_scheduled`, `queued`, `matching`, `leased`, `running`, `result_submitted`, `verifying`, `succeeded`, `failed`, `abandoned`, `expired`.

When no current attempt exists, the value is `not_scheduled`. A retry creates a new attempt and changes this projection without mutating prior attempts.

## `billingStatus`

Read projection of Quote, CreditReservation and final ledger evidence:

`not_reserved`, `reserving`, `reserved`, `charged`, `released`, `failed`, `disputed`.

Billing state never determines execution authority and execution failure never implies a charge without the financial failure matrix.

## API rule

The public `Task` schema requires all three fields. A generic `status` field is forbidden. Clients must render them separately, for example:

- lifecycle: **Active**
- execution: **Verifying**
- billing: **Reserved**

This separation prevents the former ambiguity where values such as `credit_reserved`, `running` and `completed` were mixed in one state machine.
