# RB-024 Identity Loop and Native Crash Evidence

## Purpose

Document how EdgeMint traces active-model identity mutations and reconciles Native crashes without depending on Dart after SIGSEGV (Architecture v2 §24, §41, §53, §75, §76, A22/T22).

## Policy

`dsl/policies/worker/active-identity-native-lifecycle-v1.yaml`

Key rules:

- Every identity/install/verify mutation records caller, reason, before/after state and monotonic event sequence.
- Native model create/close and inference session create/close are counted separately from registration logs.
- Overlapping bootstrap paths (`ensureModelReady`, `verifyActive`, `ensureReady`) serialize through a bootstrap guard.
- Server infers grant loss from lease/connection/heartbeat evidence plus authenticated restart metadata; it does not require a Dart exception handler after SIGSEGV.

Worker tracer: `src/apps/worker/lib/runtime/identity_lifecycle_tracer.dart`

Backend reconciliation: `src/backend/edgemint/workers/identity_native_lifecycle.py`

Heartbeat field: `identityLifecycleView` on worker heartbeats (stored in `telemetry_json`).

## Required T22 matrix

| Scenario ID | Physical device required |
| --- | --- |
| `idle_identity_loop` | Yes |
| `native_crash_regression` | Yes |
| `missing_model_recovery` | No (unit/dev) |

Emulator success alone **cannot** certify production identity-loop closure.

## Harness procedure (ops)

1. Install a named release build on a representative T3/T4 arm64 device.
2. Enroll worker; confirm heartbeats include `identityLifecycleView.nativeHandleCounters`.
3. Leave worker idle for longer than lifecycle/timer periods (≥15 minutes per policy); verify no idle churn (`idleChurnDetected=false`, identity clears ≤ policy limit).
4. Run assignment + poll overlap while model verify runs; confirm bootstrap guard prevents concurrent activation (`bootstrapInFlight` transitions bounded).
5. Delete physical model file while registration remains; verify stale-registration branch clears identity once and does not delete unknown paths.
6. Reproduce or regression-test historical Native crash (SIGSEGV/GATHER_ND); capture handle counters before/after and server reconciliation outcome.
7. Compare with emulator smoke only; do **not** promote emulator-only results to production certification.

## Evidence artifacts

- Backend: `src/backend/tests/workers/test_identity_native_lifecycle.py`
- Worker tests: `src/apps/worker/test/runtime/identity_lifecycle_tracer_test.dart`
- Source investigation (upstream): `plan/evidence/phase-08-p8-t06-identity-loop-investigation.json`
- Validator: `tools/verify_identity_loop_native_crash.py`
- Phase evidence: `plan/evidence/phase-08-p8-a22-identity-loop-native-crash.json`

## Current certification status

Until physical-device idle soak and Native crash regression harnesses are executed, classification remains **IMPLEMENTED_DEV_ONLY** with T22 integration **NOT_RUN**.
