# RB-004: Token Claim Ambiguous

## Trigger
Provider or chain submission has unknown outcome.

## Severity and ownership
Incident Commander owns coordination. Domain owner executes changes. Finance or Security approval is mandatory where money, token, evidence, or access is affected.

## Immediate procedure
Move claim to reconciling; never resubmit blindly; query destination and provider using idempotency reference; hold worker balance; require finance approval.

## Exit criteria
The customer journey is healthy, stale work is fenced, financial and task invariants pass, monitoring is stable for one full evaluation window, and evidence is attached to the incident.

## Forbidden actions
Never edit immutable task revisions, delete financial evidence, accept stale fence tokens, manually change balances, or retry ambiguous external settlement without reconciliation.
