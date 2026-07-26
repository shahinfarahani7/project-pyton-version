# Worker Earnings UI Rules

Display three balances separately:
1. Estimated — current task estimate; not earned.
2. Pending — completed work under verification/hold.
3. Verified — EUR-denominated reward micros eligible for configured payout/claim paths.

An EDGE equivalent may be shown only when a current claim epoch exists and must include rate timestamp, expiry and `estimated` label. Idle availability rewards show daily cap and campaign budget status. The UI never displays guaranteed daily income.
