# RB-011: Mobile Crash Loop

## Trigger
Worker app crash-free metric falls.

## Severity and ownership
Incident Commander owns coordination. Domain owner executes changes. Finance or Security approval is mandatory where money, token, evidence, or access is affected.

## Immediate procedure
Disable affected model or runtime via remote policy; prevent assignment; preserve crash evidence without payload; publish hotfix; re-benchmark before ready.

## Exit criteria
The customer journey is healthy, stale work is fenced, financial and task invariants pass, monitoring is stable for one full evaluation window, and evidence is attached to the incident.

## Forbidden actions
Never edit immutable task revisions, delete financial evidence, accept stale fence tokens, manually change balances, or retry ambiguous external settlement without reconciliation.
