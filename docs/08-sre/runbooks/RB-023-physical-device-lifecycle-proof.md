# RB-023 Physical-Device Process Lifecycle Proof

## Purpose

Document how EdgeMint certifies Android process lifecycle behavior for production (Architecture v2 §24, §32, §39, A17/T17).

## Platform profile

Policy: `dsl/policies/worker/android-process-lifecycle-v1.yaml`

Key rules:

- Model/native handles are valid only within a healthy process/runtime generation.
- Process death and device reboot invalidate native handles even when the verified artifact remains installed.
- Foreground execution uses `ExecutionForegroundService` with a user-visible notification (`dataSync` type).
- Local checkpoint resume is blocked until fresh server authorization after process restart.

Worker coordinator: `src/apps/worker/lib/runtime/process_lifecycle_coordinator.dart`

Assignment integration: `AssignmentCoordinator.inspectResume` rejects stale local resume when `requiresFreshGrantReconciliation` is true; fresh server assignment clears reconciliation.

## Required physical-device matrix (T17)

| Scenario ID | Physical device required |
| --- | --- |
| `background_fgs` | Yes |
| `app_suspend` | Yes |
| `process_death` | Yes |
| `device_reboot` | Yes |
| `os_memory_pressure` | Yes |
| `emulator_smoke_comparison` | No (smoke only) |

Emulator success alone **cannot** certify production per v2 §65 and MediaPipe guidance.

## Harness procedure (ops)

1. Install a named release build on representative T3/T4 arm64 devices from the policy matrix.
2. Enroll worker; confirm attestation rejects emulator in staging/production.
3. Start a long-running assignment; background the app — verify FGS notification remains and assignment continues or fails safely per policy.
4. Force-stop the app mid-assignment — verify native handles invalidated, no stale resume without new server grant/fence.
5. Reboot device — verify cold start reconciles installed artifact vs runtime generation; next assignment requires fresh authorization.
6. Induce memory pressure (developer options or heavy parallel apps) — verify lifecycle shutdown without artifact corruption.
7. Run the same smoke on emulator and record divergence; do **not** promote emulator-only results to production certification.

## Evidence artifacts

- Backend matrix evaluator: `src/backend/edgemint/workers/physical_device_proof.py`
- Tests: `src/backend/tests/workers/test_physical_device_lifecycle.py`
- Worker tests: `src/apps/worker/test/runtime/process_lifecycle_coordinator_test.dart`
- Validator: `tools/verify_physical_device_lifecycle_proof.py`
- Phase evidence: `plan/evidence/phase-08-p8-a17-physical-device-lifecycle-proof.json`

## Relationship to P7 load sim

P7-CHAOS-20-workers proves dev/staging load invariants. T17 complements it with named physical-device lifecycle scenarios; it does not replace the 20-worker load test.

## Current certification status

Until the physical-device harness above is executed and recorded, classification remains **IMPLEMENTED_DEV_ONLY** with T17 integration **NOT_RUN**.
