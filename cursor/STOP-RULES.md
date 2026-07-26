# Cursor Stop Rules

Stop and write a blocker report when any of the following is true:

- Two authoritative contracts conflict.
- A required external input, credential, approval, signature, digest, or environment identifier is absent or unverified.
- A requested change would add a database other than Microsoft PostgreSQL.
- A requested change would add an external message broker, secondary database, or distributed cache.
- A service attempts to acknowledge an event before its local transaction and inbox record commit.
- A migration is destructive without an approved expand-migrate-contract plan and tested restore point.
- Workspace identity is missing or a cross-workspace reference cannot be prevented.
- Money would use floating-point or locale-sensitive types.
- A ledger transaction is unbalanced, mutable, or bypasses the canonical posting procedure.
- A Worker result lacks a valid assignment fence token, signature, or attestation evidence.
- Any verification command fails.
- Any evidence would have to be invented, copied from a different commit, expired, or manually asserted without cryptographic or provider proof.
