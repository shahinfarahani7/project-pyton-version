# RB-007: Webhook Provider Failure

## Trigger
Webhook 5xx or timeout rate spikes.

## Severity and ownership
Incident Commander owns coordination. Domain owner executes changes. Finance or Security approval is mandatory where money, token, evidence, or access is affected.

## Immediate procedure
Continue durable queue; respect endpoint retry policy; do not duplicate event IDs; expose delivery status; pause only abusive endpoints; replay after recovery.

## Exit criteria
The customer journey is healthy, stale work is fenced, financial and task invariants pass, monitoring is stable for one full evaluation window, and evidence is attached to the incident.

## Forbidden actions
Never edit immutable task revisions, delete financial evidence, accept stale fence tokens, manually change balances, or retry ambiguous external settlement without reconciliation.
