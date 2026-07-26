# RB-005: Model Rollout Regression

## Trigger
Canary quality, crash, or thermal metrics breach threshold.

## Severity and ownership
Incident Commander owns coordination. Domain owner executes changes. Finance or Security approval is mandatory where money, token, evidence, or access is affected.

## Immediate procedure
Pause rollout; prevent new downloads; retain previous signed artifact; command rollback; verify artifact digest; invalidate incompatible checkpoints; monitor recovery.

## Exit criteria
The customer journey is healthy, stale work is fenced, financial and task invariants pass, monitoring is stable for one full evaluation window, and evidence is attached to the incident.

## Forbidden actions
Never edit immutable task revisions, delete financial evidence, accept stale fence tokens, manually change balances, or retry ambiguous external settlement without reconciliation.
