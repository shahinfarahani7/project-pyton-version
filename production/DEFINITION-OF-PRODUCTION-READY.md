# Definition of Production Ready

A release is production ready only when all conditions below are machine-verifiable and approved:

1. Every repository validation, build, test, lint, schema-compatibility, migration, and security job passes.
2. Every deployable image has an immutable digest, SBOM, vulnerability report, SLSA provenance, and Cosign signature.
3. Every production model artifact has an approved license, immutable digest, signature, benchmark, resource profile, and rollback version.
4. Database migrations pass clean-install, upgrade, rollback-simulation, concurrency, RLS, invariant, backup, and restore tests.
5. The end-to-end paid-task journey passes through customer charge and worker reward reconciliation.
6. SLO dashboards and paging alerts are active and tested.
7. Load, soak, chaos, penetration, mobile-device, and disaster-recovery tests meet their thresholds.
8. Privacy, data-residency, tax, payment, payout, KYC, and customer terms evidence is attached.
9. Canary promotion completes without error-budget, security, reconciliation, or margin breach.
10. Product, Engineering, Security, SRE, Finance, Legal, and Operations sign the release manifest.

No operator or Cursor instruction may replace missing evidence with a placeholder, mock approval, disabled test, or reduced threshold.
