# Deterministic Pricing Calculation Order

All values below are integer micro-EUR unless stated otherwise.

1. Measure input with the TaskType billing extractor.
2. Convert measurement to billable quanta using the TaskType rounding rule.
3. `base = quanta × unitPriceMicros`.
4. Add fixed feature fees.
5. Apply ordered basis-point multipliers: plan, priority, verification, region, execution policy and retention.
6. Apply contractual discounts.
7. Apply promotion discount. The promotion ledger records the subsidy separately.
8. Apply customer minimum charge. A free-trial promotion may bypass this only when `fundsFloorDifference=true`.
9. Estimate variable cost from CostModel and selected routing strategy.
10. Enforce contribution-margin floor. If it fails: select a cheaper valid route, consume approved subsidy, require approval, or reject quote.
11. Calculate tax through the tax adapter and record the tax decision code.
12. Reserve the total customer amount and persist the complete rule trace and policy hashes.

Rounding occurs only where the DSL explicitly states it. The reference implementation uses decimal arithmetic and rounds to one micro-EUR with `HALF_UP`.
