# Worker Reward Unit

Worker COGS must not depend on an exchange-traded token price.

- Every verified assignment creates `RewardAccrual.amountMicros` denominated in EUR.
- The app may display an **estimated** EDGE equivalent, clearly labelled as non-final.
- A claim epoch publishes `microsEurPerEdgeAtomicUnit`, source, timestamp, expiry and treasury cap.
- Conversion uses integer floor division; unconverted dust remains in the worker reward balance.
- Reversals after fraud review debit the worker payable only while funds remain on hold. Post-settlement clawback requires a separate legal and operational process.
- A valid worker result is paid when platform infrastructure fails after result acknowledgement, unless fraud or protocol violation is proven.
