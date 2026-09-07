# RB-026 Policy Readiness and Mixed-Version Gate

## Purpose

Document fail-closed §73 policy readiness activation and mixed-version rollout controls (Architecture v2 A23 / T23).

## Policy

`dsl/policies/governance/policy-readiness-gate-v1.yaml`

Key rules:

- Missing or partial §73 policy values block production activation fail-closed.
- `PolicyReadinessRecord` binds architecture version, policy hash, evidence, compatibility and feature flags.
- Dependency gates require pinned checkout and section-3 path inventory evidence before enablement.
- Mixed worker/server architecture pairs outside the compatibility matrix are rejected; rollback precedes forward adoption.
- Storage restore requires ownership dedup recovery without destructive database downgrade.

Backend gate: `src/backend/edgemint/governance/policy_readiness_gate.py`

SQL: `database/sql/036_policy_readiness_records.sql`

Schema: `dsl/schemas/policyreadinessrecord.schema.json`

Upstream analysis: `plan/evidence/phase-08-p8-t04-policy-readiness-gap.json`

## T23 scenarios

| Scenario | Expected result |
| --- | --- |
| Missing policy/evidence | Activation gate CLOSED; enable path blocked |
| Mixed-version rollout | Incompatible pair rejected; compatible v2.0/v2.0 admitted |
| Storage restore | Ownership dedup recovered; destructive downgrade forbidden |

## Current certification status

Production activation gate remains **CLOSED** until all §73 areas are CONFIGURED with bound evidence. T23 integration harness **NOT_RUN**.
