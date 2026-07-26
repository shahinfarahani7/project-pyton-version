# RB-012: Api Idempotency Outage

## Trigger
Idempotency store unavailable.

## Severity and ownership
Incident Commander owns coordination. Domain owner executes changes. Finance or Security approval is mandatory where money, token, evidence, or access is affected.

## Immediate procedure
Fail closed for money and task mutations; allow safe GET; do not bypass key checks; restore store; verify no duplicate task or charge.

## Exit criteria
The customer journey is healthy, stale work is fenced, financial and task invariants pass, monitoring is stable for one full evaluation window, and evidence is attached to the incident.

## Forbidden actions
Never edit immutable task revisions, delete financial evidence, accept stale fence tokens, manually change balances, or retry ambiguous external settlement without reconciliation.
