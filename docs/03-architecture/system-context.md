# System Context

Actors: Customer User, Customer System/API, Mobile Worker, Operations Agent, Finance/Compliance Agent, Payment Provider, KYC/Payout Provider, Object Storage, Cloud Inference Provider and optional Blockchain Network.

Trust boundaries:
- customer input is untrusted.
- mobile worker and result are untrusted.
- third-party provider callbacks are authenticated but still idempotently validated.
- policy documents are trusted only after signature/hash activation.
- operations users are privileged but all changes remain auditable.
