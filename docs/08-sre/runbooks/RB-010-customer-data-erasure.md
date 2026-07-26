# RB-010: Customer Data Erasure

## Trigger
Validated erasure request.

## Severity and ownership
Incident Commander owns coordination. Domain owner executes changes. Finance or Security approval is mandatory where money, token, evidence, or access is affected.

## Immediate procedure
Authenticate requester; resolve legal retention exceptions; tombstone searchable metadata; cryptographically erase payload keys; preserve minimal financial and audit evidence; issue completion record.

## Exit criteria
The customer journey is healthy, stale work is fenced, financial and task invariants pass, monitoring is stable for one full evaluation window, and evidence is attached to the incident.

## Forbidden actions
Never edit immutable task revisions, delete financial evidence, accept stale fence tokens, manually change balances, or retry ambiguous external settlement without reconciliation.
