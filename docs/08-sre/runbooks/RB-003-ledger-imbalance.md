# RB-003: Ledger Imbalance

## Trigger
Any transaction fails balance assertion.

## Severity and ownership
Incident Commander owns coordination. Domain owner executes changes. Finance or Security approval is mandatory where money, token, evidence, or access is affected.

## Immediate procedure
Activate finance kill switch; stop posting but continue evidence collection; isolate transaction; compare outbox and inbox; create compensating transaction only; require dual approval; rerun reconciliation.

## Exit criteria
The customer journey is healthy, stale work is fenced, financial and task invariants pass, monitoring is stable for one full evaluation window, and evidence is attached to the incident.

## Forbidden actions
Never edit immutable task revisions, delete financial evidence, accept stale fence tokens, manually change balances, or retry ambiguous external settlement without reconciliation.
