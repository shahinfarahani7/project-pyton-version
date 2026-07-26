# Assumptions and Default Decisions

Defaults are implementation decisions, not silent assumptions.

| Area | Default | Change mechanism |
|---|---|---|
| billing currency | EUR | new PriceBook and accounting review |
| internal precision | micro-EUR | breaking architecture decision |
| API mode | asynchronous | explicit sync endpoint only for bounded tasks |
| edge policy | edge preferred, cloud fallback allowed by customer policy | per-task execution policy |
| customer data region | workspace policy | DataPolicy version |
| worker reward | EUR micros | RewardPolicy version |
| token claim | disabled | Compliance gate + TokenPolicy activation |
| task retention | task-type/DataPolicy minimum | workspace override within legal limits |
| worker temp data | delete within 15 minutes after acknowledgement | DataPolicy |
| consensus independence | different worker account and device; network cluster separation when possible | VerificationPolicy |
| mobile execution | explicit availability mode and visible processing state | ConsentPolicy |
