# RB-018: Slo Burn Rate

## Trigger
Fast or slow burn alert fires.

## Severity and ownership
Incident Commander owns coordination. Domain owner executes changes. Finance or Security approval is mandatory where money, token, evidence, or access is affected.

## Immediate procedure
Assign incident commander; identify affected journey; reduce load; scale or fallback; post status; track error budget; require review before risky releases.

## Exit criteria
The customer journey is healthy, stale work is fenced, financial and task invariants pass, monitoring is stable for one full evaluation window, and evidence is attached to the incident.

## Forbidden actions
Never edit immutable task revisions, delete financial evidence, accept stale fence tokens, manually change balances, or retry ambiguous external settlement without reconciliation.
