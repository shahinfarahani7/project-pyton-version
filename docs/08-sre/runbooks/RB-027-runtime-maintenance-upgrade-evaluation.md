# RB-027 Runtime Maintenance and Upgrade Evaluation

## Purpose

Document pinned runtime maintenance status and evaluated upgrade/rollback controls (Architecture v2 §4, §32.1, §70, §77, A24/T24).

## Policy

`dsl/policies/runtime/runtime-maintenance-upgrade-v1.yaml`

Key rules:

- MediaPipe LLM baseline remains **pinned** until a separate versioned evaluation passes.
- Silent dependency upgrade and global model replacement are forbidden.
- Candidate upgrades require rollback version, benchmark evidence, and compatibility matrix pass.
- Upgrade during open inference sessions or concurrent install is blocked.
- Rollback must be proven before forward adoption.

Worker coordinator: `src/apps/worker/lib/runtime/runtime_upgrade_coordinator.dart`

Backend evaluator: `src/backend/edgemint/runtime/runtime_upgrade_policy.py`

SQL: `database/sql/037_runtime_upgrade_evaluations.sql`

## T24 scenarios

| Scenario | Expected result |
| --- | --- |
| Candidate runtime upgrade | All evaluation dimensions pass; adoption allowed |
| Rollback proven | Rollback version + benchmark evidence required before forward adoption |
| Upgrade during session | Rejected while inference sessions are open |

## Current certification status

Until candidate runtime evaluation and rollback are executed on a named device build, classification remains **IMPLEMENTED_DEV_ONLY** with T24 integration **NOT_RUN**.
