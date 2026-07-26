# Ledger Posting Catalog

Reservations are subledger holds and do not recognize revenue. General-ledger postings occur on monetary events.

| Event | Debit | Credit |
|---|---|---|
| customer funds settled | Cash/Processor Receivable | Customer Credit Liability |
| task usage finalized | Customer Credit Liability | Compute/Verification Revenue |
| worker reward verified | Worker Compute Expense | Worker Reward Payable |
| reward converted for claim | Worker Reward Payable | Token Settlement Clearing |
| token/network settlement | Token Settlement Clearing + Network Fee Expense | Cash/Token Treasury Asset |
| customer refund to balance | Contra Revenue | Customer Credit Liability |
| cash refund | Customer Credit Liability/Refund Payable | Cash/Processor Clearing |
| service credit | Service Credit Expense | Customer Credit Liability |

Tax, processor fees and foreign-exchange postings are separate lines linked to the same business reference. Every transaction balances in one currency; cross-currency conversion uses paired transactions and an FX clearing account.
