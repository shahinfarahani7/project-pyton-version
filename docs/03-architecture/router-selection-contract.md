# Router Selection Contract

## Queue selection

The router does not use plain FIFO and does not allow a busy workspace to starve others. It selects a bounded window of eligible queued attempts using workspace deficit round robin. Within the fairness order it sorts by effective priority, absolute deadline, submission time, and task ID. Waiting time adds a bounded aging boost. A passed deadline expires without assignment. All ties are deterministic.

## Worker selection

Workers first pass hard eligibility, including current consent and explicit `Available` status. Every score feature is generated only by the formulas in `smart-router-v2`; implementations may not invent alternate normalization. The weighted score and HMAC tie breaker then rank candidates.

## Automatic assignment

The selected attempt and worker are committed through one atomic PostgreSQL auto-lease transaction. No task offer or per-task confirmation exists.


## Availability scope

`worker_preferences.availability` is the account-wide opt-in for new automatic work. A particular device is still eligible only when its own device state, heartbeat, attestation, model inventory, thermal state, network policy, schedule and free capacity pass the hard filters. Setting the worker account to Unavailable blocks new leases for every device but does not silently cancel an active lease.


## Two-phase eligibility and atomic capacity reservation

The Router first evaluates the complete routing snapshot and ranks candidates. The PostgreSQL `AcquireAssignmentLease` transaction then acquires both the attempt lock and a per-device capacity lock and revalidates the safety-critical subset: account Available status, worker/device lifecycle, current attestation, current consent policy, trust floor, fresh sequenced heartbeat, battery, thermal state, network and charging policy, exact verified model digest, and tier concurrency. A stale Router decision therefore fails closed and returns to matching instead of overbooking or leasing to an ineligible device. Schedule, runtime ABI and resource preflight are evaluated by the Router and rechecked by the Worker Agent before automatic start; any local drift is reported through the closed machine-only unavailable reason set.


## Queue claim and fairness persistence

PostgreSQL stores one `workspace_routing_fairness` row per workspace and short-lived claim ownership directly on `task_attempts`. `SelectNextRoutableAttempt` is serialized with an application lock, applies deficit credit, maximum-consecutive protection, priority, aging, deadline and deterministic tie-break ordering, then claims exactly one attempt for one Router instance. `AcquireAssignmentLease` accepts only the Router instance that owns the unexpired claim and clears the claim in the same lease transaction. A Router that finds no eligible Worker explicitly releases the claim; a crashed Router loses it automatically at expiry. Assignment history enforces the initial assignment plus at most `maxWorkerReassignments`.

## Priority authority and hard starvation bound

Clients cannot directly set `priority_bps`. The admission service derives `priority_class` and `priority_bps` from the active entitlement, execution mode and an audited operations override. `critical` is restricted to enterprise entitlement or an authorized operations override; `high` is for business/enterprise SLA work; `standard` is the interactive default; and `batch` requires batch execution mode. Persisted values are therefore server-authoritative.

The 300-second starvation limit is a hard queue override. Once a matching attempt reaches the limit, the oldest starved attempt is selected before normal deficit, priority and deadline ordering. The SQL procedure captures one selection timestamp and one exact claim-expiry timestamp so ranking, expiry and the returned claim cannot disagree. Deadline expiry changes the attempt and task in the same transaction and writes both lifecycle events to the SQL outbox before commit.

## Machine-only unavailability evidence

`reportAssignmentUnavailable` is not a Worker rejection mechanism. The gateway must pass the exact `observedAt` and monotonic `healthSnapshotSequence` from the Worker Agent. PostgreSQL accepts the report only when that snapshot is the latest snapshot for the assigned device, is no older than 90 seconds, and the selected reason is proven by persisted telemetry or immutable task-revision requirements. Battery, thermal and network reasons are checked against the snapshot and Worker policy; model, runtime ABI, RAM and storage reasons are checked against the exact assigned model and server-derived revision requirements. A mismatch changes no assignment state and causes no reassignment.

Each submitted task revision carries immutable server-derived requirements: minimum device tier, required runtime ABI, minimum free RAM, minimum free storage and allowed Worker regions. The atomic lease transaction compares those fields with the selected device and its latest heartbeat. Worker schedule eligibility is also persisted as an effective UTC window and rechecked during lease acquisition. This prevents a Router pre-check from becoming stale before commit.

The automatic-start deadline is the delivery deadline plus the configured start grace. The delivery window and start grace are sequential, not competing timers; transport acknowledgement remains receipt evidence only.

## Reassignment budget exhaustion

The initial lease plus `maxWorkerReassignments` is a hard per-attempt budget. Queue selection expires a still-matching attempt once its assignment history reaches that budget and emits `attempt-lifecycle.matching_to_expired` with reason `worker_reassignment_limit`. It does not expire the parent task. The retry orchestrator then creates a new attempt when retry budget remains, evaluates policy-controlled Cloud fallback, or fails the task explicitly. Exhausted attempts are excluded from queue claims, so they cannot spin forever.
