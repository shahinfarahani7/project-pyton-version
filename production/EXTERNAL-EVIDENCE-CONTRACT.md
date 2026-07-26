# External Evidence Contract

External facts cannot be fabricated inside a static package. They are not open architecture decisions; their exact evidence format and fail-closed behavior are defined here.

Required evidence is stored under `evidence/actual/` and validated by JSON Schema:

- cloud account and region ownership;
- DNS and certificate ownership;
- Stripe account, supported-country, tax, and payout configuration;
- platform-attestation production credentials;
- model license approvals, digests, signatures, and device benchmarks;
- container digests, SBOMs, signatures, and provenance;
- security assessment and penetration-test closure;
- backup/restore and disaster-recovery test results;
- privacy, tax, finance, legal, and release approvals.

Missing or expired evidence blocks production promotion. Development and test environments may use documented emulators, but their evidence cannot satisfy a production gate.
