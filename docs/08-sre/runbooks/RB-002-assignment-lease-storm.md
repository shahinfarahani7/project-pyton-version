# RB-002: Assignment Lease Storm

## Trigger
Lease expiry or renewal errors spike.

## Severity and ownership
Incident Commander owns coordination. Domain owner executes changes. Finance or Security approval is mandatory where money, token, evidence, or access is affected.

## Immediate procedure
Stop new automatic lease creation; compare heartbeat clock skew; inspect fence-token counter; revoke stale leases; requeue attempts with a new fence token; never accept stale completion; reconcile rewards.

## Exit criteria
The customer journey is healthy, stale work is fenced, financial and task invariants pass, monitoring is stable for one full evaluation window, and evidence is attached to the incident.

## Forbidden actions
Never edit immutable task revisions, delete financial evidence, accept stale fence tokens, manually change balances, or retry ambiguous external settlement without reconciliation.
