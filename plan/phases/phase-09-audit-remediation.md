# Phase 9 — Audit Remediation (F01–F19)

> **Authority:** [docs/EdgeMint-Repository-Audit-47608d5.md](../../docs/EdgeMint-Repository-Audit-47608d5.md)
> **Last updated:** 2026-09-13

## Summary

| Task | Status | Evidence |
|------|--------|----------|
| P9-AUDIT-01 Baseline | done | `plan/evidence/audit-remediation-p9-phase1.json` |
| P9-AUDIT-02 Safety/Lease | done | `plan/evidence/audit-remediation-p9-phase2.json` |
| P9-AUDIT-03 Acceptance | done | `database/sql/038_acceptance_terminal_guard.sql`, tests |
| P9-AUDIT-04 Durable recovery | done | `src/apps/worker/lib/runtime/encrypted_store.dart` |
| P9-AUDIT-05 Control plane | done | `src/backend/edgemint/routing/scheduler_consumer.py` |
| P9-AUDIT-06 Tests/catalog | done | updated backend tests, verifier |
| P9-AUDIT-07 Final gates | done | `plan/evidence/audit-remediation-p9-phase7.json` (source complete; runtime NOT_RUN) |

### P9-AUDIT-01 — Baseline (F04,F05,F06,F07,F02,F16)

**Status:** done

**Scope:** Token provider, manifest/output routes, portal multipart, model fetch scripts, cold-start load, single model owner.

**Evidence:** `plan/evidence/audit-remediation-p9-phase1.json`

### P9-AUDIT-02 — Device safety and lease (F03,F08)

**Status:** done

**Evidence:** `plan/evidence/audit-remediation-p9-phase2.json`

### P9-AUDIT-03 — Acceptance integrity (F01,F15)

**Status:** done

**Evidence:** `database/sql/038_acceptance_terminal_guard.sql`, `src/backend/edgemint/results/validator.py`

### P9-AUDIT-04 — Durable recovery (F09,F17,F12,F13)

**Status:** done

**Evidence:** `database/sql/039_atomic_reservation_recheck.sql`, `database/sql/040_task_run_fence_budget.sql`

### P9-AUDIT-05 — Control plane (F10,F11)

**Status:** done

**Evidence:** `src/backend/edgemint/routing/scheduler_consumer.py`, bootstrap grant fields

### P9-AUDIT-06 — Tests and catalog hygiene (F14,F18,F19)

**Status:** done

**Evidence:** backend test updates, `tools/verify_production_auto_assignment_source.py`

### P9-AUDIT-07 — Production gates (closure)

**Status:** done

**Evidence:** `plan/evidence/audit-remediation-p9-phase7.json` — implementation complete; Flutter E2E / physical / 20-worker marked NOT_RUN pending hardware environment
