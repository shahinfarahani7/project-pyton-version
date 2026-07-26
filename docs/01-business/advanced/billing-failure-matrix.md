# Billing and Reward Failure Matrix

| Failure owner | Customer charge | Worker reward | Retry |
|---|---|---|---|
| invalid customer input detected before assignment | validation fee only if plan permits; otherwise zero | zero | customer revision required |
| customer cancellation before lease | zero; release reservation | zero | no |
| customer cancellation after valid execution started | configured cancellation charge | work-proportional or full per policy | no |
| worker rejects/assignment expires | zero incremental charge | zero | new assignment |
| worker device/network failure before valid result | zero execution charge | zero, except approved partial checkpoint policy | new attempt |
| worker submits invalid result | zero or minimum verification charge | zero and trust review | new attempt |
| platform loses valid acknowledged result | customer not double charged | worker paid | platform recovery/new attempt |
| verification disagreement | verification charge according to plan | valid participants paid; collusion excluded | consensus/escalation |
| cloud fallback | customer charge follows quote | no mobile reward; cloud COGS | automatic |
| platform outage/SLA breach | charge per completed usage; service credit separately | valid worker reward retained | controlled replay |
