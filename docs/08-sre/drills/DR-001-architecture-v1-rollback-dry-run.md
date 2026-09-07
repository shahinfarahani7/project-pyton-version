# DR-001: Architecture Rollback Dry-Run

> **Architecture:** v2 (supersedes v1 rollback drill scope)  
> **Task:** P7-T01 (historical); ongoing rollback per RB-025 applies to v2 deployments

> **Task:** P7-T01  
> **Runbook:** [RB-025-release-rollback](../runbooks/RB-025-release-rollback.md)  
> **Classification:** IMPLEMENTED_DEV_ONLY (staging/live drill deferred until deploy pipeline)

## Objective

Exercise rollback procedure without destructive database downgrade. Validates that release rollback invariants are documented and enforced in source.

## Preconditions

- Phase 6 complete (adaptive execution)
- `tools/run_rollback_drill_dry_run.py` available
- RB-025 reviewed

## Dry-run steps

1. **Stop rollout** — Confirm canary/production gate blocks further promotion (`tools/production_gate.py`).
2. **Pin immutable digest** — Verify deployment manifests reference image digest, not floating tag.
3. **Forward-compatible migration check** — Confirm no destructive downgrade scripts in `database/sql/`.
4. **Stale fence invariant** — Run `tools/verify_production_completion_source.py` (lease secret destroyed on complete).
5. **Financial invariant** — Run billing idempotency test via chaos harness (`P7-CHAOS-reward-exactly-once`).
6. **Health validation** — Run `bash tools/validate_all.sh` (or subset on Windows: DSL + pytest chaos suite).
7. **Attach evidence** — Record output to `plan/evidence/phase-07-p7-t01-rollout-rollback-drill.json`.

## Pass criteria

- All RB-025 forbidden actions remain absent in rollback path
- Lease credentials destroyed on successful completion
- Idempotent reward finalize rejects duplicate completion
- Drill script exits 0

## Evidence

- `plan/evidence/phase-07-p7-t01-rollout-rollback-drill.json`
- This drill document

## Rollback of this drill

N/A — read-only source verification.
