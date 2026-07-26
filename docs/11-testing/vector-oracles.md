# Vector Oracle Rules

A vector file is evidence only when an independent function recomputes its expected result. `verify_vectors_semantics.py` loads active policies and invokes the pricing, reward, routing, lifecycle, ledger, webhook, claim and resume oracles. Case IDs are unique. Any policy version change requires regeneration and review of the diff.
