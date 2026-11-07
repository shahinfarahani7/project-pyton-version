# Token Supply and Emission

Token settlement stays outside the first production release. No task creates tokens, and the EUR reward ledger is unchanged. The figures below are the FibonAI accounting policy in `dsl/economy/fibonai-token-v1.yaml`.

- Maximum supply is 21,000,000,000 FIBON. The policy does not mint.
- 16,000,000,000 is the participant pool. 5,000,000,000 is the parent-company and token-holder pool.
- Both pools use the infinite Fibonacci power emission model with exponent 1/4. Year `n` weighs `G_n^(-1/4)`, with `G` starting `1, 2, 3, 5, ...`.
- Year-1 participant emission is 1,879,797,899 tokens. Whitepaper v0.5 rounds that to about 1.88 billion.
- Three or more agreeing participants share 75 percent of a task release and the treasury receives 25 percent. Exactly two agreeing participants each receive 25 percent and the treasury receives 50 percent. No agreement pays nobody.
- Unused emission for that year moves to the treasury at year end. The whitepaper illustration of 1.88 billion planned and 1.6 billion consumed leaves 680 million in the treasury.
- One accepted treasury vote returns 75 percent of the voted balance to participants and keeps 25 percent. Spending the retained part takes another vote.
- One accepted task on the current single-result path charges 1 FIBON (10,000 atomic units) at difficulty grade 1. The worker who completed it receives 0.75 FIBON and the treasury receives 0.25 FIBON. Grade `K` multiplies both amounts. Cancelled and failed tasks return the charge.
- The stated device floor is 4 GiB of RAM and 4 GiB of free storage.
- Whitepaper v0.5 says each requester has a monthly free-request allowance and does not give the number, so the cap is unset.

Enabling on-chain settlement still requires the gates in `docs/01-business/token-launch-gates.md`.
