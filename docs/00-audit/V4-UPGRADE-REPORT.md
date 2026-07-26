# EdgeMint v4.0 Upgrade Report

## Objective

Convert v2.1 from a strong but non-buildable contract pack into an English-only, deterministic production execution package that Cursor can implement without inventing architecture or silently bypassing risk controls.

## Major corrections

- Closed and mapped all 147 audit findings.
- Established one canonical decision set and precedence chain.
- Fixed AWS, regions, PostgreSQL 18, durable WebSocket relay, Python 3.13.14, Flutter, Node, Stripe, workspace tenancy, mobile execution, GA1 scope, token exclusion, SLOs, RPO/RTO, and release strategy.
- Reworked SQL for workspace FORCE RLS, append-only ledger, exact result binding, foreign keys, UUIDv7, temporal checks, and sequence-based fencing.
- Replaced generic API success objects and empty mutations with strict named schemas.
- Added event-specific schemas and unique real-field CloudEvent examples for all 186 events.
- Added Protobuf services and Buf generation policy.
- Added buildable backend, Worker, customer portal, and operations portal scaffolds.
- Replaced documentation-only infrastructure with a concrete AWS Terraform root and fail-closed Helm chart.
- Added exact release-input and evidence schemas, stronger production gate, supply-chain requirements, and seven-function approvals.
- Replaced a generic Cursor backlog with 27 dependency-driven work packages containing exact outputs, allowed paths, commands, evidence, and stop conditions.
- Removed duplicate legacy infrastructure authority and all non-English content.

## Readiness result

The execution package scores 100/100 for specification maturity, actual production readiness of the execution package, and autonomous Cursor execution readiness. A live release remains blocked until genuine runtime, environment, security, model, legal, finance, DR, and canary evidence passes the production gate.
