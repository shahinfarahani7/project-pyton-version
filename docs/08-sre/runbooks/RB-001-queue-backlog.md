# RB-001: Queue Backlog

## Trigger
Queue age P95 breaches SLO.

## Severity and ownership
Incident Commander owns coordination. Domain owner executes changes. Finance or Security approval is mandatory where money, token, evidence, or access is affected.

## Immediate procedure
Freeze nonessential batch intake; inspect consumer lag; scale router and consumers; verify database and broker; enable cloud fallback within budget; communicate; drain oldest first without reordering priority; confirm no duplicate assignments.

## Exit criteria
The customer journey is healthy, stale work is fenced, financial and task invariants pass, monitoring is stable for one full evaluation window, and evidence is attached to the incident.

## Forbidden actions
Never edit immutable task revisions, delete financial evidence, accept stale fence tokens, manually change balances, or retry ambiguous external settlement without reconciliation.
