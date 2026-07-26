# Token Conversion and Claim

A claim is a settlement operation, not task execution.

1. Reward must be `verified` and outside all holds.
2. Worker identity, jurisdiction and destination must satisfy the claim policy snapshot.
3. Claim epoch must be open, funded and not paused.
4. Eligible EUR reward micros are reserved atomically.
5. EDGE atomic units are calculated using the epoch rate and token decimals.
6. A signed claim batch is submitted by the treasury adapter.
7. Chain/provider confirmation changes claim to `settled`.
8. Failed batches release the reward reservation; ambiguous batches enter `reconciling` and cannot be resubmitted until resolved.

No screen or API promises a future token value. Public sale and transfer features remain separate compliance-gated capabilities.

## Exact conversion arithmetic

A ClaimEpoch stores a rational rate as two positive integers:

- `reward_micros_per_rate_unit`
- `token_base_units_per_rate_unit`

The only permitted conversion is:

`tokenBaseUnits = floor(verifiedRewardMicros × tokenBaseUnitsPerRateUnit ÷ rewardMicrosPerRateUnit)`

The residual reward micros remain in the worker balance. Decimal or binary floating-point conversion is forbidden. The epoch record, operands and result are retained with claim evidence.
