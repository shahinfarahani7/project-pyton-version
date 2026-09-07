# EdgeMint Target Architecture v1

> **Status:** SUPERSEDED — retained for historical reference only  
> **Superseded by:** [EDGE-MINT-TARGET-ARCHITECTURE-v2.md](./EDGE-MINT-TARGET-ARCHITECTURE-v2.md) (v2.0, 2026-09-05)  
> **v1 SHA-256:** `1f129782f6f8efc1274c14b3654b6cde5aefacfa7af82aa9da0b423ccf60abe5`  
> **Do not use for new implementation decisions.**

> **Original status:** FROZEN ARCHITECTURE  
> **Document Type:** Canonical Target Architecture / Implementation Authority  
> **Version:** 1.0  
> **Date:** 2026-09-01  
> **Repository:** `https://github.com/shahinfarahani7/project-pyton-version`

---

## 0. Purpose

This document is the canonical frozen architecture for EdgeMint. It defines the approved target state for the Control Plane, Worker Runtime, resource scheduling, model lifecycle, long-context execution, failure handling, validation, reward, and production proof.

It does **not** claim that every item is already implemented in the current repository. A feature is considered closed only when implementation evidence exists in source code, SQL, contracts, events, tests, and the real production path.

---

# 1. Core Goal

EdgeMint is a distributed AI execution platform where AI tasks run on worker devices such as Android phones, emulators, and future edge nodes.

Supported workload families include:

- text processing,
- OCR,
- document processing,
- lightweight image classification,
- vision,
- VLM,
- segmentation,
- PDF processing,
- structured extraction,
- moderation,
- summarization,
- other task types in the Task Catalog.

The architecture MUST optimize for:

1. Server-controlled scheduling.
2. Safe device resource usage.
3. User-controlled compute contribution.
4. Low device storage usage.
5. Model locality.
6. Multi-task execution where safe.
7. Deterministic retry and reassignment.
8. Strong lease and fencing semantics.
9. Checkpoint/resume for long tasks.
10. Server-side result validation.
11. Exactly-once accepted completion and reward.
12. Full auditability.
13. Runtime/model replaceability.
14. No worker-side scheduling authority.

---

# 2. Non-Negotiable Decisions

## 2.1 Server Is the Only Scheduling Authority

Only the Server Scheduler may decide:

- which task is scheduled,
- which worker receives the task,
- how many tasks may run concurrently,
- resource budgets,
- retry,
- reassignment,
- cooldown,
- cloud fallback,
- priority,
- assignment expiry,
- reservation release.

The Worker MUST NOT independently decide:

- to fetch arbitrary tasks,
- which task to execute,
- to move a task to another worker,
- to retry a task,
- to reassign a task,
- to choose cloud fallback,
- to increase resource contribution,
- to schedule additional heavy tasks.

## 2.2 Worker Role

The Worker is limited to:

- capability reporting,
- telemetry,
- installed-model reporting,
- assignment receipt,
- assignment validation,
- execution,
- progress,
- checkpointing,
- result submission,
- failure evidence,
- local machine-safety enforcement.

The Worker may stop/defer only for unavoidable safety conditions such as OOM risk, thermal critical, OS pressure, consent mismatch, runtime incompatibility, or corrupted runtime/model state. The next scheduling action remains a Server decision.

## 2.3 No Local Scheduler

Do not implement:

```text
LocalTaskSelector
LocalRetryOrchestrator
LocalReassignmentManager
LocalCloudFallbackDecision
```

Allowed worker components include:

```text
RuntimeSafetyController
WorkerResourceEnforcer
ExecutionPlanRunner
ModelRuntimeManager
ContextBudgetManager
CheckpointManager
```

---

# 3. Repository Structure

Major areas:

```text
src/backend
database/sql
contracts
dsl
docs

src/apps/customer-portal
src/apps/operations-portal
src/apps/worker
```

Expected backend routing/worker areas:

```text
src/backend/edgemint/routing
src/backend/edgemint/workers
src/backend/edgemint/services/router.py
src/backend/edgemint/services/worker_gateway.py
src/backend/edgemint/services/worker_registry.py
```

Worker stack:

```text
Flutter
Dart
Material 3
flutter_gemma
flutter_gemma_mediapipe
PaddleOCR
```

---

# 4. Current Primary On-Device LLM Baseline

```text
Profile ID:       qwen2.5-0.5b
Model Version ID: mdv_qwen2_5_0_5b
Display Name:     Qwen2.5 0.5B
Artifact:         Qwen2.5-0.5B-Instruct_multi-prefill-seq_q8_ekv1280.task
Approx Size:      ~547 MB
```

Current runtime path:

```text
flutter_gemma
    ↓
flutter_gemma_mediapipe
    ↓
MediaPipe LLM
    ↓
CPU
```

Current context/KV profile:

```text
ekv1280
```

Approved current baseline:

```text
maxTokens ≈ 1280
```

The prior 4096-token configuration is not the approved baseline. Long inputs MUST be handled before reaching native runtime.

---

# 5. Model Strategy

## 5.1 One Heavy Model per Device by Default

A normal EdgeMint worker should not store several large LLM/VLM artifacts.

Default:

```text
One primary heavy model
+
OCR runtime
+
optional tiny specialist models
```

Avoid installing Qwen + Gemma + embeddings + Function model + VLM + another LLM on every device.

## 5.2 Move Tasks Toward Models

Principle:

> Move the Task toward the Model, not the Model toward every Task.

Worker telemetry must report:

```text
installedModels
loadedModels
modelVersion
artifactDigest
runtimeCompatibility
```

Model locality is a routing feature.

## 5.3 Fleet Model Pools

Example:

```text
GENERAL TEXT POOL → Qwen2.5 0.5B
LIGHT POOL        → tiny specialist runtimes
OCR POOL          → PaddleOCR
VISION POOL       → VLM / detection / segmentation
```

A worker does not need all model families installed.

---

# 6. Task-Centric Architecture

EdgeMint MUST be task-centric, not model-centric.

Wrong:

```text
Task → Qwen
```

Correct:

```text
Task
  ↓
Task Requirement Resolution
  ↓
Execution Plan
  ↓
Cost Estimation
  ↓
Capability Match
  ↓
Worker Selection
  ↓
Runtime Selection
  ↓
Execution
```

Task contracts declare capabilities such as:

```text
text.summarize
document.extract
document.ocr
image.classify
vision.analyze
```

They MUST NOT hardcode implementation names such as `runQwenTask()`.

---

# 7. Canonical Control Plane Architecture

```text
                         EDGE MINT CONTROL PLANE

┌─────────────────────────────────────────────────────────────────────┐
│ Task Catalog                                                        │
│      ↓                                                              │
│ Task Revision                                                       │
│      ↓                                                              │
│ Input Contract Validation                                           │
│      ↓                                                              │
│ Task Requirement Resolver                                           │
│      ↓                                                              │
│ Execution Plan Resolver                                             │
│      ↓                                                              │
│ Task Cost Estimator                                                 │
│      ↓                                                              │
│ Workspace Fair Queue                                                │
│      ↓                                                              │
│ Hard Eligibility Filter                                             │
│      ↓                                                              │
│ Model / Runtime / Resource Feasibility                              │
│      ↓                                                              │
│ Failure Affinity / Compatibility                                    │
│      ↓                                                              │
│ Worker Scoring                                                      │
│      ↓                                                              │
│ Atomic Capacity Reservation                                         │
│      ↓                                                              │
│ Assignment + Lease + Fence                                          │
│      ↓                                                              │
│ Outbox / WebSocket Delivery                                         │
└──────────────────────────────┬──────────────────────────────────────┘
                               │
                               ▼
                          ANDROID WORKER
                               │
                               ▼
                       Server Validation
                               │
                ┌──────────────┼──────────────┐
                ▼              ▼              ▼
             Complete        Retry          Reward
```

---

# 8. Canonical Worker Runtime Architecture

```text
Assignment Receiver
        ↓
Contract Verify
        ↓
Fence Verify
        ↓
Consent Verify
        ↓
Runtime Safety Verify
        ↓
ExecutionPlanRunner
        │
        ├── RuntimeSafetyController
        ├── WorkerResourceEnforcer
        ├── ModelRuntimeManager
        ├── ContextBudgetManager
        ├── ChunkEngine
        ├── CheckpointManager
        ├── OCR Runtime
        ├── LLM Runtime
        ├── Vision Runtime
        └── Tiny/Specialist Runtime
        ↓
Progress / Checkpoint
        ↓
Result or Failure Evidence
        ↓
Server
```

---

# 9. Queue Selection

Approved ordering:

```text
Workspace Deficit Round Robin
→ Priority
→ Deadline
→ Submission Time
→ Task ID
```

Starvation protection baseline:

```text
300 seconds
```

Priority order:

```text
critical
high
standard
batch
```

Priority MUST be server-derived from trusted sources such as entitlement, execution mode, operations override, and SLA policy. Client-provided priority is not authoritative.

---

# 10. Worker Hard Eligibility

Before scoring, a worker must pass hard filters:

- heartbeat freshness,
- worker availability,
- trust,
- attestation,
- user consent,
- battery policy,
- thermal policy,
- region policy,
- network policy,
- model availability,
- model digest,
- runtime compatibility,
- ABI compatibility,
- Android/runtime compatibility,
- required free storage,
- failure cooldown,
- assignment safety state.

---

# 11. Resource Vector Scheduling

Simple assignment count is not sufficient.

Legacy-style logic such as:

```sql
CASE
    WHEN device_tier = 'T4' THEN 2
    ELSE 1
END
```

MUST NOT be the primary capacity model.

Scheduling MUST use a resource vector.

---

# 12. Task Resource Envelope

Each immutable Task Revision must have a server-derived resource envelope.

Example:

```json
{
  "taskType": "text.summarize",
  "runtimeClass": "mediapipe_llm",
  "requiredModelIds": ["qwen2.5-0.5b"],
  "cpuUnits": 40,
  "memoryReservationBytes": 1610612736,
  "storageReservationBytes": 104857600,
  "acceleratorUnits": 0,
  "modelSessionUnits": 1,
  "estimatedDurationMs": 180000,
  "maximumParallelPerDevice": 1,
  "exclusiveGroup": "llm_inference"
}
```

Resource envelopes MUST be server-generated, immutable per revision, versioned, auditable, and not modifiable by client or worker.

---

# 13. Input-Aware Task Cost Estimation

Task type alone is not enough.

```text
text.summarize with 300 tokens
≠
text.summarize with 30,000 tokens
```

A server-side `TaskCostEstimator` MUST estimate cost using:

```text
taskType
inputBytes
estimatedInputTokens
pageCount
imageDimensions
chunkCountEstimate
runtimeClass
modelVersion
executionPlan
```

Expected output:

```text
predictedDurationMs
predictedPeakMemoryBytes
predictedCpuUnits
predictedEnergyClass
predictedStageCount
predictedInferenceCalls
```

---

# 14. Execution Plan

Complex tasks MUST be represented as stage plans.

Example:

```text
document.summarize

Stage 1 → PDF Decode
Stage 2 → OCR
Stage 3 → Text Normalize
Stage 4 → Chunk
Stage 5 → LLM Map
Stage 6 → LLM Reduce
Stage 7 → Validate
Stage 8 → Submit
```

Canonical entity:

```text
TaskExecutionPlan
```

Each stage may have its own runtime class, resource estimate, checkpoint behavior, model requirement, retry semantics, and validation rule.

The Worker executes only the Server-approved plan.

---

# 15. Device Capacity and User Consent

Initial approved modes:

```text
Balanced:    30%
Performance: 50%
```

Changing 30% to 50% MUST NOT change the architecture. It only changes policy budgets.

---

# 16. Resource Budgets Are Per Resource Class

Do not calculate every resource as `Physical Capacity × User Percentage`.

## CPU

```text
EffectiveCpuBudget =
min(
    UserApprovedCpuBudget,
    ServerPolicyLimit,
    ThermalBudget,
    PowerBudget
)
```

## Memory

```text
EffectiveMemoryBudget =
min(
    UserMemoryPolicyLimit,
    CurrentAvailableMemory - SafetyReserve
)
```

## Storage

Storage uses separate limits:

```text
MaxAIStorage
MinimumFreeStorage
ModelCacheBudget
```

30% / 50% are maximum user-approved contribution levels, not guaranteed utilization.

---

# 17. Consent Changes During Execution

## Increase: 30% → 50%

Apply to new reservations/assignments. The current stage does not need restart.

## Decrease: 50% → 30%

Worker MUST:

1. stop admitting new local stages above the new limit,
2. safely finish the current atomic stage when possible,
3. checkpoint,
4. report policy change,
5. let Server decide the next action.

## Full Revocation

Worker MUST:

1. stop accepting new work,
2. checkpoint if possible,
3. report `CONSENT_REVOKED`,
4. not independently retry or reassign.

---

# 18. Worker Resource Enforcer

The worker-side safety component is:

```text
WorkerResourceEnforcer
```

or equivalently:

```text
RuntimeSafetyController
```

It MUST NOT be a scheduler.

Allowed decisions:

```text
EXECUTE
DEFER_FOR_SAFETY
PAUSE_FOR_SAFETY
ABORT_FOR_SAFETY
```

It may enforce user consent, thermal limit, memory safety, OS pressure, battery policy, and runtime safety.

---

# 19. Resource Reservation Ledger

Canonical table:

```text
worker_resource_reservations
```

Suggested fields:

```text
id
assignment_id
worker_device_id
task_revision_id
cpu_units
memory_bytes
storage_bytes
accelerator_units
model_session_units
exclusive_group
status
reserved_at_utc
activated_at_utc
released_at_utc
expires_at_utc
fence_token
```

States:

```text
reserved
active
released
expired
revoked
```

Remaining capacity:

```text
Remaining =
    EffectiveApprovedCapacity
    - Sum(ReservedAndActiveResources)
    - SafetyReserve
```

---

# 20. Atomic Assignment Transaction

Required sequence:

1. Lock Task Attempt.
2. Lock Worker Capacity.
3. Re-check heartbeat freshness.
4. Re-check consent.
5. Re-check worker availability.
6. Re-check model/runtime compatibility.
7. Recalculate remaining capacity.
8. Re-check exclusive groups.
9. Create Resource Reservation.
10. Create Assignment.
11. Generate Fence Token.
12. Persist lease-token security material as required.
13. Create Outbox Event.
14. Commit.

If any step fails:

```text
No partial Assignment
No leaked Reservation
```

Approved policy:

```yaml
reservationMode: compare_and_swap
overbookingAllowed: false
assignmentMode: server_auto_lease
perTaskWorkerConfirmation: false
```

---

# 21. Delivery ACK vs Scheduling Decision

`perTaskWorkerConfirmation: false` remains correct.

Worker still sends delivery acknowledgement:

```text
Assignment Received
```

ACK is not scheduling acceptance authority.

---

# 22. Lease and Fence

Fence-aware writes include at least:

```text
Progress
Checkpoint
Lease Renewal
Failure Evidence
Result Submission
Completion
```

Required identity:

```text
attemptId
assignmentId
fenceToken
```

Stale writes MUST be rejected.

---

# 23. Assignment State Machine

```text
PENDING
   ↓
ROUTING
   ↓
RESERVED
   ↓
ASSIGNED
   ↓
DELIVERED
   ↓
STARTED
   ↓
RUNNING
   ↓
RESULT_SUBMITTED
   ↓
VALIDATING
   ├───────────────┐
   ↓               ↓
SUCCEEDED        REJECTED
                   ↓
              RETRY DECISION
```

Additional states:

```text
EXPIRED
REVOKED
SAFETY_STOPPED
STALE
FAILED
```

---

# 24. Model and Session Lifecycle

This is a critical frozen decision.

## Model Lifetime

```text
Load model once
Reuse model across tasks
Unload only on:
- memory pressure,
- explicit lifecycle shutdown,
- model replacement,
- corruption,
- long idle policy.
```

## Session Lifetime

```text
One inference stage
→ one session
→ close session
```

Canonical rule:

> Model lifetime != Session lifetime.

---

# 25. Long-Context Processing

Native runtime MUST NOT be the first overflow detector.

```text
Prompt Builder
      ↓
Token Estimator / Tokenizer
      ↓
ContextBudgetManager
      ↓
Direct Inference OR Chunk Pipeline
```

For the current Qwen baseline:

```text
Total context budget ≈ 1280 tokens
```

Initial conservative budget:

```text
System / Template      ~ 200
Input                   ~ 600
Output Reserve          ~ 300
Safety Margin           ~ 180
--------------------------------
Total                  ~ 1280
```

Exact values must be calibrated with runtime measurements.

---

# 26. Hierarchical Summarization

Do NOT keep one session open and append all chunks.

Wrong:

```text
One Session
  ↓
Chunk 1
  ↓
Chunk 2
  ↓
Chunk 3
  ↓
Context overflow
```

Correct:

```text
Input
  ↓
ContextBudgetManager
  │
  ├── Fits
  │     ↓
  │   Fresh Session
  │     ↓
  │   Result
  │
  └── Too Long
        ↓
   Semantic Chunker
        ↓
 ┌──────┼──────┐
 ↓      ↓      ↓
C1     C2     C3
 ↓      ↓      ↓
S1     S2     S3
 ↓      ↓      ↓
close  close  close
session session session
 └──────┬──────┘
        ↓
Reduce Budget
        ↓
Fresh Reduce Session
        ↓
Final Summary
```

If intermediate summaries remain too large, recursive reduce is allowed.

---

# 27. Chunking Rules

Chunking MUST:

- preserve sentence boundaries,
- prefer paragraph boundaries,
- avoid cutting words,
- support controlled overlap,
- deduplicate overlap content,
- respect token budget,
- support deterministic chunk IDs,
- support checkpoint/resume.

Naive fixed-character slicing is not the production strategy.

---

# 28. Chunk Checkpoints

Each chunk checkpoint should include:

```text
chunkIndex
inputHash
summaryHash
modelVersion
runtimeVersion
promptVersion
processedRange
fenceToken
```

Already validated chunks may be reused only when Server authorizes resume.

---

# 29. Concurrency Model

Initial production-safe concurrency:

```text
LLM Heavy = 1
VLM Heavy = 1
```

Default:

```text
Qwen + Qwen           ❌
Qwen + VLM            ❌
VLM + VLM             ❌
```

OCR baseline:

```text
Default OCR concurrency = 1
```

Higher OCR concurrency is allowed only for certified device/runtime profiles.

```yaml
paddle_ocr:
  defaultMaximumSessionsPerDevice: 1
  certifiedMaximumSessionsPerDevice: 2
```

---

# 30. Qwen + OCR Concurrency

Do not globally enable Qwen + OCR parallel execution in v1.

Default:

```text
Qwen running
→ OCR waits
```

Enable concurrent execution only when the calibration/compatibility profile certifies:

```text
mediapipe_llm + paddle_ocr = safe
```

Certification must consider CPU, RAM, memory bandwidth, thermal, battery, latency, crash rate, and 30%/50% policy compliance.

---

# 31. Light Work During Heavy Inference

Light/system work may run concurrently with heavy inference.

Examples:

```text
Result Upload
Telemetry
Checkpoint upload
JSON parsing
Hashing
Network I/O
```

Recommended execution classes:

```text
HEAVY_COMPUTE
MEDIUM_COMPUTE
LIGHT_CPU
NETWORK_IO
SYSTEM
```

---

# 32. Runtime Compatibility Profiles

Compatibility may depend on:

```text
Runtime A
Runtime B
Model A
Model B
ABI
Android version
Page size
Accelerator
Plugin version
Artifact type
Certified concurrency
```

Canonical entity:

```text
RuntimeCompatibilityProfile
```

This is required because native compatibility may differ across Android versions, x86_64/arm64, 4KB/16KB pages, plugin versions, artifact types, and delegates.

---

# 33. Device Calibration

Do not rely only on RAM or static tiers.

Workers SHOULD run a controlled benchmark measuring:

```text
LLM warmup time
LLM prefill tokens/sec
LLM decode tokens/sec
Peak LLM memory
OCR page latency
OCR throughput
CPU average
Thermal delta
Runtime stability
```

Canonical entity:

```text
WorkerCalibrationProfile
```

---

# 34. Cost Prediction Feedback

Prediction should combine:

```text
BaseTaskCost
× InputSizeFactor
× DeviceCalibrationFactor
× RuntimeFactor
```

Store:

```text
Predicted:
- CPU
- memory
- duration
- energy class

Observed:
- CPU
- peak memory
- duration
- thermal delta
- tokens/sec or pages/sec
```

Prediction error should improve future calibration.

---

# 35. Adaptive Concurrency

Concurrency SHOULD eventually be device-certified.

Example:

```text
Device A
Heavy=1
Medium alongside Heavy=0

Device B
Heavy=1
Medium alongside Heavy=1

Device C
Heavy=1
Medium=2
```

Do not hardcode one concurrency profile for all devices.

---

# 36. Worker Scoring

Hard eligibility and feasibility happen before scoring.

Recommended dimensions:

| Feature | Suggested Weight |
|---|---:|
| Model Locality | 20% |
| Trust | 18% |
| Predicted Completion Time | 16% |
| Resource Fit | 14% |
| Regional Compliance | 10% |
| Price Efficiency | 8% |
| Network | 5% |
| Reliability | 5% |
| Battery / Charging | 2% |
| Fragmentation / Scarcity Cost | 2% |

Exact weights remain policy-controlled.

---

# 37. Resource Fit and Scarcity Cost

Resource Fit measures whether the worker remains healthy after assignment.

Possible dimensions:

```text
remainingMemoryHeadroom
remainingCpuHeadroom
remainingModelSessionCapacity
remainingAcceleratorCapacity
thermalHeadroom
```

Scarcity/fragmentation cost prevents cheap tasks from consuming scarce high-capability workers unnecessarily.

---

# 38. Deterministic Tie-Breaking

Approved tie-breaker:

```text
HMAC-SHA256(taskId, workerId, routerEpoch)
```

Routing decisions MUST be auditable.

---

# 39. Heartbeat and Telemetry

Heartbeat should include at least:

```json
{
  "sequence": 1842,
  "observedAt": "2026-09-01T10:00:00Z",
  "cpuUsageBps": 2100,
  "availableMemoryBytes": 3221225472,
  "availableStorageBytes": 21474836480,
  "thermalState": "nominal",
  "batteryBps": 7800,
  "charging": true,
  "networkType": "wifi",
  "activeAssignmentIds": ["asg-1"],
  "installedModelIds": ["qwen2.5-0.5b"],
  "loadedModelIds": ["qwen2.5-0.5b"],
  "runtimeSessions": {
    "mediapipe_llm": 1,
    "paddle_ocr": 0
  }
}
```

---

# 40. Reservation vs Telemetry Reconciliation

```text
Expected Usage = Active Server Reservations
Observed Usage = Worker Telemetry
Variance = Observed - Expected
```

Large persistent variance should cause:

1. no new heavy assignments,
2. `capacity_uncertain`,
3. fresh snapshot request,
4. recalibration or quarantine if persistent.

---

# 41. Failure Handling

Worker never decides retry. Worker submits failure evidence.

## Before Execution

```text
MODEL_UNAVAILABLE
INSUFFICIENT_MEMORY
INSUFFICIENT_STORAGE
RUNTIME_INCOMPATIBLE
THERMAL_BLOCK
NETWORK_POLICY_MISMATCH
DELIVERY_TIMEOUT
START_TIMEOUT
CONSENT_MISMATCH
```

## During Execution

```text
RUNTIME_OUT_OF_MEMORY
RUNTIME_CRASH
INFERENCE_TIMEOUT
MODEL_EXECUTION_FAILED
OS_PROCESS_TERMINATED
INPUT_RUNTIME_UNSUPPORTED
CONTEXT_BUDGET_EXCEEDED
```

## After Execution

```text
RESULT_INVALID_JSON
RESULT_SCHEMA_MISMATCH
RESULT_EMPTY
RESULT_LOW_CONFIDENCE
RESULT_SIGNATURE_INVALID
GOLDEN_VALIDATION_FAILED
```

Frozen rule:

> Execution Success != Task Success.

---

# 42. Failure Evidence

Example:

```json
{
  "assignmentId": "asg-123",
  "attemptId": "att-123",
  "fenceToken": 4,
  "healthSnapshotSequence": 1872,
  "observedAt": "2026-09-01T10:15:00Z",
  "failureCode": "RUNTIME_OUT_OF_MEMORY",
  "metrics": {
    "peakMemoryBytes": 1835008000,
    "executionTimeMs": 64000
  },
  "checkpointId": "chk-45"
}
```

---

# 43. Retry Classification

## Immediate Retry on Another Worker

```text
RESOURCE_PRESSURE
MODEL_UNAVAILABLE
RUNTIME_INCOMPATIBLE
THERMAL_BLOCK
WORKER_DISCONNECTED
LEASE_EXPIRED
DELIVERY_TIMEOUT
START_TIMEOUT
```

## Retry on Stronger Worker / Runtime

```text
RUNTIME_OUT_OF_MEMORY
INFERENCE_TIMEOUT
MODEL_EXECUTION_FAILED
RESULT_VALIDATION_FAILED
OCR_EMPTY_RESULT
VISION_LOW_CONFIDENCE
```

## No Retry

```text
INPUT_SCHEMA_INVALID
PERMISSION_DENIED
CONSENT_REVOKED
POLICY_BLOCKED
UNRECOVERABLE_FILE
TASK_CANCELLED
DEADLINE_EXPIRED
```

Retry mapping is server-side and machine-readable.

---

# 44. Reassignment Budget

Initial policy:

```yaml
maxWorkerReassignments: 2
```

Meaning:

```text
Initial Assignment
+ Reassignment 1
+ Reassignment 2
= maximum 3 workers per attempt
```

After exhaustion the Attempt expires, then the Retry Orchestrator chooses:

```text
Create New Attempt
Cloud Fallback
Verification Flow
Permanent Failure
```

---

# 45. Failure Affinity and Cooldown

Canonical entity/table:

```text
attempt_worker_failures
```

Suggested fields:

```text
task_attempt_id
worker_device_id
runtime_class
model_version_id
failure_code
observed_at_utc
cooldown_until_utc
```

Examples:

```text
Thermal failure → worker-wide temporary cooldown
Qwen OOM       → restrict similar Qwen tasks
Model corrupt  → block tasks using same model
Network issue  → restrict network-sensitive assignments
```

---

# 46. Checkpoint and Resume

Checkpoint support is required for long-running tasks such as multi-page PDF, batch OCR, chunking, embeddings, transcription, and long summarization.

Checkpoint identity:

```text
taskRevisionId
attemptId
assignmentId
modelVersionId
runtimeVersion
fenceToken
processedRange
resultHash
```

Resume is Server-authorized only.

---

# 47. Stale Fence Behavior

When a worker disconnects:

1. lease stops renewing,
2. assignment expires,
3. reservation releases,
4. task may be reassigned,
5. fence token advances.

Old result after reassignment:

```text
ASSIGNMENT_STALE_FENCE
```

Old result:

- does not complete task,
- gets no reward,
- may remain as audit evidence.

---

# 48. Result Validation

Every result MUST be validated server-side.

## Summarization

```text
valid schema
summary non-empty
within requested length
no malformed output
required fields present
```

## OCR

```text
minimum page coverage
confidence threshold
non-empty result when expected
```

## Structured Extraction

```text
JSON Schema
required fields
domain validation
```

Reward is not issued until validation succeeds.

---

# 49. Quality-Aware Escalation

Runtime execution may succeed while quality validation fails.

Server may choose:

```text
retry same profile
retry stronger worker
retry stronger model pool
cloud fallback
permanent failure
```

Worker never decides escalation.

---

# 50. Exactly-Once Semantics

Do not promise exactly-once physical execution.

Target guarantees:

```text
At-least-once physical execution may occur
Exactly-once accepted completion
Exactly-once reward
```

Use:

```text
Fence
CAS
Idempotency Keys
Unique Constraints
Transaction Boundaries
```

---

# 51. Reward

| State | Reward |
|---|---|
| Validated Completed Result | Full |
| Contract-approved Partial Result | Partial |
| Assignment Failed | None |
| Invalid Result | None |
| Stale Fence Result | None |
| Valid External Failure | No direct penalty |
| Repeated Worker-caused Failure | Reliability decrease |
| Fraud / Manipulation | Quarantine |

Reward happens only after Server-side Result Validation.

---

# 52. Cloud Fallback

Baseline:

```yaml
defaultPolicy: edge_preferred
cloudAfterSeconds: 45
maxWorkerReassignments: 2
```

Cloud fallback may occur only when customer policy, SLA, region/data policy, model compatibility, output contract, and cost cap allow it.

Worker never chooses cloud fallback.

---

# 53. Model Download and Lifecycle

Model lifecycle manager must support:

```text
resumable download
SHA256 verification
signature verification
atomic activation
corruption detection
previous-version fallback
staged rollout
rollback
cache eviction
disk budget
minimum free disk
```

Model download should not unexpectedly compete with heavy inference.

---

# 54. Model Storage Policy

Suggested organization:

```text
models/
├── permanent/
│   └── required small runtimes
└── cache/
    └── primary heavy model
```

Policy controls:

```text
MaxAIStorage
MinimumFreeStorage
PinnedModels
LRU Eviction
ModelVersionRetention
```

---

# 55. Task Catalog Requirements

Every executable task must have:

```text
Task ID
Task Type
Task Revision
Input Contract
Output Contract
Execution Plan
Runtime Class
Required Models
Resource Envelope
Cost Model
Result Validation
Retry Class
Checkpoint Support
Golden Tests
```

Tasks without complete contracts MUST NOT enter the executable queue.

---

# 56. Current Catalog Gap

Previously reported:

```text
25 Qwen tasks
9 Flex tasks
14 Vision tasks
```

Total:

```text
48
```

Reported catalog total:

```text
56
```

Therefore 8 task classifications remain unresolved in the handoff data. This is a P0 audit gap.

Do not claim Task Catalog closure until all 56 tasks are individually classified and evidenced.

---

# 57. Flex Tasks

The 9 Flex tasks without Input Contracts:

```text
MUST NOT ENTER EXECUTION QUEUE
```

until their contracts are complete.

---

# 58. Vision Taxonomy

Vision workloads should at minimum be separated into:

```text
OCR
Image Classification
Object Detection
Embedding / Similarity
VLM
Segmentation
```

Each category gets separate runtime, resource envelope, compatibility profile, concurrency policy, and validation rules.

---

# 59. Recommended Runtime Classes

```text
paddle_ocr
mediapipe_llm
image_classifier
object_detector
embedding_runtime
vlm_runtime
segmentation_runtime
network_io
system
```

---

# 60. Recommended Core Data Model

```text
TaskDefinition
TaskRevision
TaskInputContract
TaskResultContract

TaskExecutionPlan
TaskStageDefinition
TaskResourceEnvelope

ModelDefinition
ModelVersion
ModelArtifact
RuntimeCompatibilityProfile

WorkerDevice
WorkerCapabilitySnapshot
WorkerCalibrationProfile
WorkerModelResidency

TaskAttempt
Assignment
Lease
ResourceReservation

Checkpoint
ExecutionResult
FailureEvidence

WorkerFailureAffinity

RoutingDecisionAudit
ResultValidation

RewardLedger
```

---

# 61. Security Requirements

Minimum production requirements:

```text
signed assignments
lease token protection
fence validation
replay protection
model artifact integrity
model signature verification
task data encryption at rest
temporary file cleanup
log redaction
result signing
audit trail
```

Verbose prompt/output logging MUST NOT be enabled in production by default. Sensitive task content MUST NOT leak to logcat.

---

# 62. UI/UX Boundary

UI/UX redesign is presentation-only and MUST NOT change:

```text
Structure
Flow
Functionality
API Contracts
Validation
Routes
State Management
Business Logic
Scheduling Logic
Worker Runtime Semantics
```

Worker tabs remain:

```text
Home
Missions
Models
Earnings
Profile
```

Their ordering, indexes, callbacks, and behavior remain unchanged unless separately approved.

---

# 63. Production Scheduling Flow

```text
Task Submitted
      ↓
Input Contract Validation
      ↓
Task Revision Resolution
      ↓
Execution Plan Resolution
      ↓
Input Size Analysis
      ↓
Task Cost Prediction
      ↓
Workspace DRR
      ↓
Priority / Deadline / Age
      ↓
Hard Eligibility
      ↓
Model Residency
      ↓
Runtime Compatibility
      ↓
Resource Feasibility
      ↓
Failure Affinity
      ↓
Concurrency Compatibility
      ↓
Worker Scoring
      ↓
Atomic Reservation
      ↓
Assignment
      ↓
Lease + Fence
      ↓
Outbox
      ↓
Worker
```

---

# 64. Initial Production Resource Policy

```yaml
resourcePolicy:
  defaultApprovedPercent: 30
  maximumApprovedPercent: 50
  safetyReservePercent: 15
  heartbeatMaximumAgeSeconds: 30
  overbookingAllowed: false

runtimeLimits:
  mediapipe_llm:
    maximumSessionsPerDevice: 1

  paddle_ocr:
    defaultMaximumSessionsPerDevice: 1
    certifiedMaximumSessionsPerDevice: 2

  heavy_vision:
    maximumSessionsPerDevice: 1
    exclusive: true

assignmentLimits:
  absoluteMaximumPerDevice: 3
```

`absoluteMaximumPerDevice` is only a safety cap. Primary scheduling uses Resource Vector feasibility.

---

# 65. Implementation Phases

## Phase 0 — Baseline Correction

1. Verify current Qwen runtime path.
2. Verify model lifecycle.
3. Close active-model identity loop.
4. Confirm context/maxTokens behavior.
5. Inventory all 56 Task Catalog entries.
6. Identify production path vs dev/test paths.

## Phase 1 — Assignment Integrity

1. Auto Lease Credential Bootstrap.
2. Outbox delivery.
3. WebSocket delivery.
4. Replay.
5. Lease renewal.
6. Start deadline.
7. Stale fence rejection.
8. Reservation release.
9. Delivery ACK.

## Phase 2 — Resource Foundation

1. Device Capability Contract.
2. Worker Calibration Profile.
3. Task Resource Envelope.
4. Task Cost Estimator.
5. Execution Plan.
6. User Consent Policy.
7. Reservation Ledger.
8. Runtime Compatibility Matrix.
9. Exclusive Groups.
10. Atomic Reservation SQL.

## Phase 3 — Worker Runtime Foundation

1. RuntimeSafetyController.
2. WorkerResourceEnforcer.
3. ModelRuntimeManager.
4. ContextBudgetManager.
5. Session lifecycle.
6. Semantic ChunkEngine.
7. Hierarchical Reduce.
8. Checkpoint Manager.
9. Predicted vs Observed telemetry.

## Phase 4 — Scheduler Upgrade

1. Hard feasibility.
2. Model locality.
3. Resource fit.
4. Fragmentation/scarcity cost.
5. Failure affinity.
6. Cooldown.
7. Deterministic scoring.
8. Routing Decision Audit.
9. Atomic reservation.

## Phase 5 — Task Catalog Closure

1. 25 Qwen tasks.
2. 9 Flex Input Contracts.
3. 14 Vision classifications.
4. Resolve remaining 8-task taxonomy gap.
5. Resource profile for all 56 tasks.
6. Result Schema Validation.
7. Retry policy for all 56 tasks.
8. Checkpoint policy where applicable.
9. Golden Tests for all tasks.

## Phase 6 — Adaptive Execution

1. 30% profile.
2. 50% opt-in profile.
3. Device calibration.
4. Certified OCR concurrency.
5. Runtime-pair compatibility.
6. Dynamic resource prediction.
7. Prediction feedback loop.
8. Consent transition handling.

## Phase 7 — Production Proof

Required tests:

```text
20 workers
56-task catalog
multi-assignment
resource exhaustion
worker disconnect
lease expiry
stale result
runtime crash
OOM
thermal failure
retry exhaustion
cloud fallback
reward exactly-once
long-context summarize
chunk resume
recursive reduce
model corruption
model update
storage pressure
30% → 50%
50% → 30%
consent revoke
thermal transition
WebSocket replay
stale fence writes
duplicate delivery
```

---

# 66. Source Audit Rules

Architecture closure and implementation closure are separate.

For every claimed completed item, audit:

```text
Source Code
SQL
Contracts
DSL
Events
Tests
Production Path
```

Classify each feature as:

```text
IMPLEMENTED_PRODUCTION
IMPLEMENTED_DEV_ONLY
TEST_ONLY
DOC_ONLY
DSL_ONLY
PARTIAL
MISSING
```

Never claim closure without evidence.

---

# 67. File-by-File Change Planning Rule

Before implementation of each phase:

1. identify impacted files,
2. identify current behavior,
3. identify target behavior,
4. list exact change,
5. list database migration,
6. list API/contract changes,
7. list event changes,
8. list tests,
9. list rollback path.

No parallel alternative architecture should be introduced.

---

# 68. Frozen Architectural Summary

The frozen EdgeMint architecture is:

```text
Server-controlled
Task-centric
Resource-vector scheduled
Model-aware
Input-cost-aware
Lease-and-fence protected
Reservation-backed
Checkpoint-capable
Quality-validated
Reward-protected
Device-calibrated
Runtime-compatible
Consent-aware
Storage-efficient
Long-context capable through chunk/map/reduce
```

Worker policy:

```text
One primary heavy model
+
OCR
+
small specialists where justified
```

Qwen policy:

```text
Qwen2.5 0.5B
Model resident
Fresh short-lived session per inference stage
Context budget before native runtime
Hierarchical chunking for long input
```

Concurrency policy:

```text
Heavy inference concurrency = 1 initially
Adaptive concurrency only after certification
Light/system work may proceed concurrently
```

Authority policy:

```text
Server = Scheduling Authority
Worker = Executor + Telemetry + Safety Enforcer
```

Resource policy:

```text
30% = default user-approved contribution
50% = optional user-approved contribution

These are policy values, not architectural variants.
```

---

# 69. Final Closure Checklist

- [ ] Production Lease Bootstrap is verified.
- [ ] Outbox/WebSocket lease delivery is verified.
- [ ] Replay is duplicate-safe.
- [ ] Stale fence writes are rejected.
- [ ] Resource Reservation Ledger exists.
- [ ] Atomic reservation is verified.
- [ ] Task Resource Envelopes exist.
- [ ] Task Cost Estimator exists.
- [ ] Execution Plans exist where required.
- [ ] Runtime Compatibility Profiles exist.
- [ ] Device Calibration exists.
- [ ] Resource Fit is used.
- [ ] Fragmentation/Scarcity Cost is used.
- [ ] Failure Affinity exists.
- [ ] Closed Failure Codes exist.
- [ ] Checkpoint/Resume is fence-aware.
- [ ] Result Validation covers every executable task.
- [ ] Reward is validation-gated and idempotent.
- [ ] 30% and 50% are server policy values.
- [ ] Worker has no scheduling authority.
- [ ] Worker enforces local safety/consent only.
- [ ] Qwen model lifecycle is stable.
- [ ] Qwen context is guarded before native runtime.
- [ ] Long summarize uses map/reduce chunking.
- [ ] Model residency is scheduler-visible.
- [ ] All 56 tasks are individually classified.
- [ ] All Flex tasks have Input Contracts.
- [ ] Vision tasks have distinct runtime/resource profiles.
- [ ] 20-worker load test passes.
- [ ] Chaos tests pass.
- [ ] Exactly-once accepted completion passes.
- [ ] Exactly-once reward passes.
- [ ] Rollout and rollback procedures are proven.

---

# 70. Architecture Change Control

This document is the frozen v1 architectural baseline.

Changes to the following require an explicit architecture revision:

- scheduling authority,
- lease/fence semantics,
- resource reservation model,
- worker authority boundary,
- task execution state machine,
- model residency strategy,
- context/chunk execution strategy,
- reward acceptance semantics,
- consent ownership,
- server-side validation model.

Implementation details may evolve without changing the architecture if they preserve these constraints.

Future revisions must be published as a new version, for example:

```text
EDGE-MINT-TARGET-ARCHITECTURE-v2.md
```

Do not silently alter v1.

---

# 71. Canonical Principle

> **EdgeMint schedules centrally, executes locally, validates centrally, and protects the user locally.**
