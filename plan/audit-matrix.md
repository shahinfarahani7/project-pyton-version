# Architecture Audit Matrix

> **Authority:** [EDGE-MINT-TARGET-ARCHITECTURE-v2.md](../docs/EDGE-MINT-TARGET-ARCHITECTURE-v2.md) Section 66 (+ §72–77)  
> **Last audit:** 2026-09-06 (v2 adoption — Cursor agent)  
> **Reviewer:** Phase 0 automated audit + source inspection

Classify each feature using exactly one status:

```text
IMPLEMENTED_PRODUCTION
IMPLEMENTED_DEV_ONLY
TEST_ONLY
DOC_ONLY
DSL_ONLY
PARTIAL
MISSING
```

Never claim closure without evidence in: Source, SQL, Contracts, DSL, Events, Tests, Production Path.

---

## Executive summary (Phase 0 — P0-T09)

Top gaps ranked by owning phase:

| Rank | Gap | Status | Owner phase | Evidence |
|------|-----|--------|-------------|----------|
| Resource reservation ledger + atomic scheduler reservation | PARTIAL | Phase 4 | Atomic SQL + scheduler stack wired (P2-T20/T21, P4-T09); prod deploy proof **P7** |
| 2 | Task resource envelopes + cost estimator in scheduler | MISSING | Phase 2 | Catalog lacks envelope DSL binding |
| 3 | 35/56 catalog tasks without worker production handler | PARTIAL | Phase 5 | [phase-00-catalog-inventory.json](./evidence/phase-00-catalog-inventory.json) |
| 4 | Architecture taxonomy mismatch (25/9/14 vs 56 catalog) | PARTIAL | Phase 5 | 18 LLM + 9 flex + 29 vision heuristic; 8 partial OCR/extract |
| 5 | ContextBudgetManager / pre-runtime chunk guard | PARTIAL | Phase 3 | Guard + chunk + map/reduce (P3-T04–P3-T07); prod proof Phase 7 |
| 6 | Model residency not used in scheduler scoring | MISSING | Phase 4 | `installed_models_json` stored; routing ignores |
| 7 | RuntimeSafetyController / WorkerResourceEnforcer | PARTIAL | Phase 3 | P3-T01/T02 implemented; production proof Phase 7 |
| 8 | Production assignment path unverified E2E at scale | PARTIAL | Phase 1/7 | Code + tests exist; prod env gate on `environment` |
| 9 | WebSocket assignment delivery vs long-poll | PARTIAL | Phase 1 | Outbox exists; worker uses HTTP `assignments:next` poll |
| 10 | Consent 30%/50% server policy | P6-T01, P6-T02 | Y | Y | Y | — | Y | Dev | **IMPLEMENTED_DEV_ONLY** | Opt-in gate + audit events + canonical decisions 30/50 |

**Phase 0 sign-off (P0-T11):** Baseline documented. No false `IMPLEMENTED_PRODUCTION` claims for Phase 2–6 features. Phase 1 may proceed with verification of existing lease bootstrap code.

**Phase 1 sign-off (P1-T14):** Lease bootstrap, renewal, stale-fence, and completion invariants verified in dev/test via pytest + source scripts. WebSocket assignment delivery to workers remains HTTP poll (`assignments:next`). Reservation release deferred to Phase 2. E2E script blocked without `EDGEMINT_DATABASE_URL`. See [phase-01-assignment-integrity.json](./evidence/phase-01-assignment-integrity.json).

---

## Phase 0 baseline inventory

| Feature / Area | Task ID | Source | SQL | Contracts | DSL | Events | Tests | Prod Path | Status | Notes |
|--------------|---------|--------|-----|-----------|-----|--------|-------|-----------|--------|-------|
| Qwen2.5 0.5B runtime path | P0-T02 | Y | — | — | — | — | Y | Dev | **IMPLEMENTED_DEV_ONLY** | `WorkerModelCatalog` → `GemmaLiteRtInferenceAdapter` → `QwenTaskProcessor`; `tools/run_qwen_real_inference.py` |
| Model lifecycle | P0-T03, P3-T03 | Y | — | — | — | — | Y | Dev | **IMPLEMENTED_DEV_ONLY** | ModelRuntimeManager + Gemma adapter refactor; fresh session per stage |
| Active-model identity loop | P0-T04 | Y | Y | Y | — | — | Partial | Dev | **PARTIAL** | `enrollment.py` stores `installed_models_json`; scheduler/routing does not read for locality |
| Context / maxTokens guard | P0-T05, P3-T04 | Y | — | — | — | — | Y | Dev | **IMPLEMENTED_DEV_ONLY** | ContextBudgetManager pre-native guard; chunk pipeline P3-T06 |
| 56-task catalog inventory | P0-T06 | Y | — | — | Y | — | Y | Y | **IMPLEMENTED_PRODUCTION** | 56 types in `src/shared/task-types/catalog.json`; inventory artifact written |
| Production vs dev path map | P0-T07 | Y | Y | Y | — | Y | Y | Partial | **PARTIAL** | 6 pipeline + 15 vision worker paths; 27 missing handler; 8 partial OCR/extract; see inventory JSON |
| Worker scheduling authority | P0-T08 | Y | — | — | — | — | — | Y | **IMPLEMENTED_PRODUCTION** | Forbidden §2.3 classes absent; worker uses server `assignments:next` (no local selector) |
| Auto lease credential bootstrap | P1-T01 | Y | Y | Y | — | Y | Y | Dev | **IMPLEMENTED_DEV_ONLY** | Verified 2026-09-01: `validate_sql.py`, pytest bootstrap tests |
| Outbox delivery | P1-T03 | Y | Y | — | — | Y | Y | Dev | **PARTIAL** | `013_*.sql`, outbox on start/renew; full prod relay unverified |
| WebSocket delivery | P1-T04 | Y | — | Y | — | Y | Partial | Dev | **PARTIAL** | `event_relay.py` fanout; worker HTTP poll not WS push |
| Replay (duplicate-safe) | P1-T05 | Y | Y | — | — | Y | Y | Dev | **TEST_ONLY** | `verify_websocket_replay_source.py` exit 0 (2026-09-01) |
| Resource reservation ledger | P2-T13, P2-T14, P2-T20, P2-T21 | Y | Y | — | — | Y | Y | Y | **IMPLEMENTED_DEV_ONLY** | Atomic SQL + verify script; prod deploy proof deferred Phase 7 |
| Device capability contract | P2-T01 | Y | — | Y | Y | — | Y | Dev | **IMPLEMENTED_DEV_ONLY** | DSL schema + worker report builder + SQL 015 |
| Worker calibration profile | P2-T03 | — | Y | — | Y | — | Y | Dev | **IMPLEMENTED_DEV_ONLY** | SQL 016 + upsert on submitBenchmark + GET /calibration |
| Task resource envelope | P2-T05 | — | — | — | Y | — | — | — | **DSL_ONLY** | taskresourceenvelope.schema.json + OCR/Qwen fixtures |
| Task resource envelope bindings | P2-T06 | Y | — | — | Y | — | Y | Y | **IMPLEMENTED_PRODUCTION** | 56/56 resourceEnvelopeRef in catalog.json |
| Task cost estimator | P2-T07, P2-T08 | Y | — | — | Y | — | Y | Dev | **IMPLEMENTED_DEV_ONLY** | EnvelopeTaskCostEstimator + quote expectedCostMicros |
| Task execution plan | P2-T09, P2-T10 | Y | — | — | Y | — | Y | Dev | **IMPLEMENTED_DEV_ONLY** | TaskExecutionPlan DSL + execution_plan_resolver |
| RuntimeSafetyController | P3-T01 | Y | — | — | — | — | Y | Dev | **IMPLEMENTED_DEV_ONLY** | DEFER/PAUSE/ABORT decisions; wired in AssignmentCoordinator |
| WorkerResourceEnforcer | P3-T02 | Y | — | — | — | — | Y | Dev | **IMPLEMENTED_DEV_ONLY** | 30%/50% per-class budgets; telemetry payload on violation |
| ModelRuntimeManager | P3-T03 | Y | — | — | — | — | Y | Dev | **IMPLEMENTED_DEV_ONLY** | One primary heavy model; session scope via withFreshSession |
| ContextBudgetManager | P3-T04 | Y | — | — | — | — | Y | Dev | **IMPLEMENTED_DEV_ONLY** | Token estimator + 1280 baseline profile; chunk route before native |
| Hierarchical map/reduce summarize | P3-T07 | Y | — | — | — | — | Y | Dev | **IMPLEMENTED_DEV_ONLY** | Map per chunk + reduce/recursive reduce; text/document summarize handlers |
| SemanticChunkEngine | P3-T06 | Y | — | — | — | — | Y | Dev | **IMPLEMENTED_DEV_ONLY** | Paragraph/sentence chunking; deterministic IDs; map metadata |
| ExecutionPlanRunner (session lifecycle) | P3-T05 | Y | — | — | — | — | Y | Dev | **IMPLEMENTED_DEV_ONLY** | Fence on entry; per-stage sessions; leak guard on exit |
| Checkpoint / resume (fence-aware) | P3-T08 | Y | — | — | — | Y | Partial | Dev | **PARTIAL** | `CheckpointManager` chunk resume + `CheckpointStore` assignment resume; server stale-fence via P1-T08 credential verification |
| Failure evidence submission | P3-T13 | Y | — | Y | Y | Y | Partial | Dev | **IMPLEMENTED_DEV_ONLY** | Closed failure code registry; `:fail` command; worker mapper + coordinator wiring |
| Predicted vs observed telemetry | P3-T14 | Y | Y | Y | Y | — | Partial | Dev | **IMPLEMENTED_DEV_ONLY** | `costFeedback` on complete; `worker_execution_cost_feedback` table for Phase 6 loop |
| Assignment receiver hardening | P3-T15 | Y | — | — | — | — | Y | Dev | **IMPLEMENTED_DEV_ONLY** | Contract/fence/consent gate before ExecutionPlanRunner; pre-start `:fail` evidence |
| Model download verify hook | P3-T16 | Y | — | — | — | — | Y | Dev | **IMPLEMENTED_DEV_ONLY** | SHA256 + signature verifier; unsigned rejected; post-download hook |
| Storage pressure handling | P3-T17 | Y | — | — | — | — | Y | Dev | **IMPLEMENTED_DEV_ONLY** | LRU cache eviction; active fence protects models/checkpoints |
| Worker heartbeat telemetry (Section 39) | P3-T18 | Y | Y | Y | Y | — | Partial | Dev | **IMPLEMENTED_DEV_ONLY** | Extended heartbeat payload; `telemetry_json` column; consent/calibration/reservations view for §40 prep |
| Hard eligibility filter | P4-T01 | Y | — | — | — | — | Y | Dev | **IMPLEMENTED_DEV_ONLY** | Section 10 gates in `hard_eligibility.py`; ineligible workers score=0 |
| Model locality scoring | P4-T02 | Y | — | Y | — | — | Y | Dev | **IMPLEMENTED_DEV_ONLY** | loaded > installed > cold via `scoring_features.py` |
| Resource fit scoring | P4-T03 | Y | — | — | — | — | Y | Dev | **IMPLEMENTED_DEV_ONLY** | Budget hard-filter + headroom caps predictedLatency feature |
| Scarcity / fragmentation cost | P4-T04 | Y | — | Y | — | — | Y | Dev | **IMPLEMENTED_DEV_ONLY** | Formula v1 in `scarcity_cost.py`; golden vectors |
| Failure affinity + cooldown | P4-T05 | Y | Y | — | — | — | Y | Dev | **IMPLEMENTED_DEV_ONLY** | `attempt_worker_failures` table + FAILURE_AFFINITY gate |
| Queue selection ordering | P4-T06 | Y | — | — | — | — | Y | Dev | **IMPLEMENTED_DEV_ONLY** | `fair_queue.py` deficit→priority→deadline→age |
| Deterministic worker scoring | P4-T07 | Y | — | — | — | — | Y | Dev | **IMPLEMENTED_DEV_ONLY** | 100-iteration determinism test + HMAC tie-break |
| Routing decision audit | P4-T08 | Y | Y | — | — | Y | Partial | Dev | **IMPLEMENTED_DEV_ONLY** | `routing_decision_audit` table + policy hash |
| Atomic scheduler stack (rank + audit + reserve) | P4-T09 | Y | Y | — | — | Y | Partial | Dev | **IMPLEMENTED_DEV_ONLY** | `assign_attempt_with_scheduler_stack`; transient worker fallback |
| Cloud fallback (server-only) | P4-T10 | Y | — | Y | — | — | Partial | Dev | **IMPLEMENTED_DEV_ONLY** | `cloud_fallback.py`; Section 52 threshold gate |
| Reassignment budget enforcement | P4-T11 | Y | — | Y | — | — | Y | Dev | **IMPLEMENTED_DEV_ONLY** | `check_reassignment_budget` in scheduler stack |
| Retry classification (Section 43) | P4-T12 | Y | — | — | — | — | Y | Dev | **IMPLEMENTED_DEV_ONLY** | `retry_classifier.py`; all closed codes mapped |
| Quality-aware verification escalation | P4-T13 | Y | — | — | — | — | Y | Dev | **IMPLEMENTED_DEV_ONLY** | standard→high→premium ladder on quality failures |
| Workspace fair queue metrics | P4-T14 | Y | — | — | — | — | Y | Dev | **IMPLEMENTED_DEV_ONLY** | Deficit/wait/starvation aggregates per workspace |
| Scheduler integration smoke | P4-T15 | Y | — | — | — | — | Y | Dev | **IMPLEMENTED_DEV_ONLY** | 3 workers × 10 task types; `run_scheduler_integration_smoke.py` |
| Deterministic multi-factor worker scoring | P4-T07 | Y | — | — | — | — | Y | Dev | **IMPLEMENTED_DEV_ONLY** | 100-iteration determinism + HMAC tie-break |
| Result validation framework (Section 48) | P5-CROSS-01 | Y | — | Y | — | — | Partial | Dev | **IMPLEMENTED_DEV_ONLY** | Pluggable registry; document.ocr reference; wired to `:complete` |
| Retry policy matrix (56 tasks) | P5-CROSS-02 | Y | — | Y | — | — | Y | Dev | **IMPLEMENTED_DEV_ONLY** | `task-retry-matrix-v1.yaml`; 9 flex non-executable; catalog synced |
| Checkpoint policy matrix (56 tasks) | P5-CROSS-03 | Y | — | Y | — | — | Y | Dev | **IMPLEMENTED_DEV_ONLY** | 15 long-running enabled; 41 explicit `checkpointEnabled: false` |
| Golden test harness (Section 55) | P5-CROSS-04 | Y | — | — | — | — | Y | Dev | **IMPLEMENTED_DEV_ONLY** | Fixture schema + `run_golden_task_harness.py`; document.ocr reference |
| Catalog closure admission gate | P5-CROSS-05 | Y | — | Y | — | — | Y | Dev | **IMPLEMENTED_DEV_ONLY** | `catalog_closure.py`; flex blocked; metadata sync CI |
| text.summarize (Qwen closure #1) | P5-QWEN-01 | Y | — | Y | Y | — | Y | Dev | **IMPLEMENTED_DEV_ONLY** | TaskType DSL + validator + golden fixture PASS |
| text.classify (Qwen closure #2) | P5-QWEN-02 | Y | — | Y | Y | — | Y | Dev | **IMPLEMENTED_DEV_ONLY** | TaskType DSL + validator + golden fixture PASS |
| moderation.prompt_safety (Qwen closure #3) | P5-QWEN-03 | Y | — | Y | Y | — | Y | Dev | **IMPLEMENTED_DEV_ONLY** | TaskType DSL + validator + golden fixture PASS |
| moderation.text (Qwen closure #4) | P5-QWEN-04 | Y | — | Y | Y | — | Y | Dev | **IMPLEMENTED_DEV_ONLY** | TaskType DSL + validator + golden fixture PASS |
| moderation.profanity (Qwen closure #5) | P5-QWEN-05 | Y | — | Y | Y | — | Y | Dev | **IMPLEMENTED_DEV_ONLY** | TaskType DSL + validator + golden fixture PASS |
| moderation.spam_comment (Qwen closure #6) | P5-QWEN-06 | Y | — | Y | Y | — | Y | Dev | **IMPLEMENTED_DEV_ONLY** | TaskType DSL + validator + golden fixture PASS |
| review.fake_detection (Qwen closure #7) | P5-QWEN-07 | Y | — | Y | Y | — | Y | Dev | **IMPLEMENTED_DEV_ONLY** | TaskType DSL + validator + golden fixture PASS |
| review.sentiment (Qwen closure #8) | P5-QWEN-08 | Y | — | Y | Y | — | Y | Dev | **IMPLEMENTED_DEV_ONLY** | TaskType DSL + validator + golden fixture PASS |
| review.topic_tagging (Qwen closure #9) | P5-QWEN-09 | Y | — | Y | Y | — | Y | Dev | **IMPLEMENTED_DEV_ONLY** | TaskType DSL + validator + golden fixture PASS |
| llm.summary_verification (Qwen #10) | P5-QWEN-10 | Y | — | Y | Y | — | Y | Dev | **IMPLEMENTED_DEV_ONLY** | TaskType DSL + validator + golden fixture PASS |
| llm.hallucination_check (Qwen #11) | P5-QWEN-11 | Y | — | Y | Y | — | Y | Dev | **IMPLEMENTED_DEV_ONLY** | TaskType DSL + validator + golden fixture PASS |
| llm.ocr_output_validation (Qwen #12) | P5-QWEN-12 | Y | — | Y | Y | — | Y | Dev | **IMPLEMENTED_DEV_ONLY** | TaskType DSL + validator + golden fixture PASS |
| llm.policy_violation (Qwen #13) | P5-QWEN-13 | Y | — | Y | Y | — | Y | Dev | **IMPLEMENTED_DEV_ONLY** | TaskType DSL + validator + golden fixture PASS |
| llm.prompt_output_consistency (Qwen #14) | P5-QWEN-14 | Y | — | Y | Y | — | Y | Dev | **IMPLEMENTED_DEV_ONLY** | TaskType DSL + validator + golden fixture PASS |
| llm.answer_quality_score (Qwen #15) | P5-QWEN-15 | Y | — | Y | Y | — | Y | Dev | **IMPLEMENTED_DEV_ONLY** | TaskType DSL + validator + golden fixture PASS |
| llm.suspicious_output (Qwen #16) | P5-QWEN-16 | Y | — | Y | Y | — | Y | Dev | **IMPLEMENTED_DEV_ONLY** | TaskType DSL + validator + golden fixture PASS |
| nlp.language_detection (Qwen #17) | P5-QWEN-17 | Y | — | Y | Y | — | Y | Dev | **IMPLEMENTED_DEV_ONLY** | TaskType DSL + validator + golden fixture PASS |
| nlp.text_classification (Qwen #18) | P5-QWEN-18 | Y | — | Y | Y | — | Y | Dev | **IMPLEMENTED_DEV_ONLY** | TaskType DSL + validator + golden fixture PASS |
| nlp.spam_fraud_classification (Qwen #19) | P5-QWEN-19 | Y | — | Y | Y | — | Y | Dev | **IMPLEMENTED_DEV_ONLY** | TaskType DSL + validator + golden fixture PASS |
| ml.bot_abuse_risk (Qwen #20) | P5-QWEN-20 | Y | — | Y | Y | — | Y | Dev | **IMPLEMENTED_DEV_ONLY** | TaskType DSL + validator + golden fixture PASS |
| document.extract (Qwen #21) | P5-QWEN-21 | Y | — | Y | Y | — | Y | Dev | **IMPLEMENTED_DEV_ONLY** | OCR+extract envelope unwrap; golden PASS |
| extract.amount (Qwen #22) | P5-QWEN-22 | Y | — | Y | Y | — | Y | Dev | **IMPLEMENTED_DEV_ONLY** | TaskType DSL + validator + golden fixture PASS |
| extract.date (Qwen #23) | P5-QWEN-23 | Y | — | Y | Y | — | Y | Dev | **IMPLEMENTED_DEV_ONLY** | TaskType DSL + validator + golden fixture PASS |
| extract.order_number (Qwen #24) | P5-QWEN-24 | Y | — | Y | Y | — | Y | Dev | **IMPLEMENTED_DEV_ONLY** | TaskType DSL + validator + golden fixture PASS |
| extract.document_type (Qwen #25) | P5-QWEN-25 | Y | — | Y | Y | — | Y | Dev | **IMPLEMENTED_DEV_ONLY** | TaskType DSL + validator + golden fixture PASS |
| 56-task individual classification | P5-GAP-08 | Y | — | Y | Y | — | Y | Dev | **IMPLEMENTED_DEV_ONLY** | 56/56 contract+golden; signoff `phase-05-p5-gap-08-catalog-signoff.json` |
| 30% / 50% consent policy | P2-T11, P2-T12, P6-T01, P6-T02 | Y | Y | Y | — | Y | Dev | **IMPLEMENTED_DEV_ONLY** | Policy DSL + opt-in enforcement + calibration-adaptive scheduler wiring |
| 20-worker load test | P7-CHAOS-20-workers | Y | — | — | — | — | Y | Dev | **IMPLEMENTED_DEV_ONLY** | 20×56 crypto flows via `run_56_task_protocol_load.py`; evidence `phase-07-p7-chaos-20-workers.json` |
| Exactly-once reward | P7-CHAOS-reward-exactly-once | Y | — | — | — | — | Y | Dev | **IMPLEMENTED_DEV_ONLY** | Finance idempotency + chaos test; evidence `phase-07-p7-chaos-reward-exactly-once.json` |
| Device calibration in router scoring | post-plan | Y | Y | — | — | — | Y | Dev | **IMPLEMENTED_DEV_ONLY** | Scheduler stack loads `calibrationFactorBps`; scoring adjusts `predictedLatency`; evidence `post-plan-calibration-router-wiring.json` |
| Production chaos harness (26 scenarios) | P7-CHAOS-* | Y | — | — | — | — | Y | Dev | **IMPLEMENTED_DEV_ONLY** | `tools/run_production_chaos_harness.py`; 26/26 pytest pass 2026-09-02 |
| OpenAPI performance opt-in | P6-T02 | — | Y | — | — | — | Y | Dev | **IMPLEMENTED_DEV_ONLY** | `performanceOptInConfirmed` on `ReplaceWorkerPreferencesRequest` |
| Rollout / rollback drill | P7-T01 | Y | — | — | — | — | Y | Dev | **IMPLEMENTED_DEV_ONLY** | RB-025 + DR-001 dry-run; `phase-07-p7-t01-rollout-rollback-drill.json` |
| Architecture v1-plan closure sign-off | P7-T02 | Y | — | — | — | — | Y | Dev | **IMPLEMENTED_DEV_ONLY** | v1-plan scope; superseded by v2 §70 |
| v2 authority adoption | P8-T01 | Y | — | Y | — | — | Y | Y | **IMPLEMENTED_PRODUCTION** | Governance sync + `validate_architecture_v2_adoption.py` |
| v2 §73 policy readiness gap | P8-T04 | — | — | — | Y | — | Y | Dev | **IMPLEMENTED_DEV_ONLY** | 10/10 areas PARTIAL; PolicyReadinessRecord MISSING; gate CLOSED |
| v2 §75 current-state register | P8-T05 | Y | — | Y | — | — | Y | Dev | **IMPLEMENTED_DEV_ONLY** | Pinned checkout e47a340; 56 unique catalog IDs; Flex DSL 9/9 |
| v2 §76 identity loop (source) | P8-T06 | Y | — | — | — | — | Y | Dev | **PARTIAL** | Static symbol map; device repro NOT_RUN → P8-A22 |

---

## Catalog gap tracker (Section 56)

| Group | Expected (arch doc) | Catalog heuristic | Classified | Gap | Task IDs |
|-------|---------------------|-------------------|------------|-----|----------|
| Qwen / LLM tasks | 25 | 18 (+8 partial OCR/extract) | **25 closed** | 0 | P5-QWEN-01 … P5-QWEN-25 ✅ |
| Flex tasks | 9 | 9 (`inputMode: flex`) | **9 closed** | 0 | P5-FLEX-01 … P5-FLEX-09 ✅ |
| Vision tasks | 14 | 29 (image + safety + catalog) | **14 closed** | 0 | P5-VIS-01 … P5-VIS-14 ✅ |
| Unresolved taxonomy | 8 | 8 (OCR variants + quality + duplicate + canonical OCR) | **8 closed** | 0 | P5-GAP-01 … P5-GAP-08 ✅ |
| **Catalog total** | **56** | **56** | **56** | **0** | Full catalog closure sign-off 2026-09-02 |

**Note:** Architecture handoff (25+9+14=48) does not match catalog shape (56 types). Reconciliation required in Phase 5 — do not claim catalog closure until each of 56 has `taskTypeId`, envelope, contract, and golden test.

Detailed per-task rows: [evidence/phase-00-catalog-inventory.json](./evidence/phase-00-catalog-inventory.json)

---

## Forbidden worker components (Section 2.3)

Audit date: 2026-09-02 (P3-T20 re-run). Grep scope: `src/apps/worker/`

| Forbidden | Found? | Path / evidence | Task |
|-----------|--------|-----------------|------|
| LocalTaskSelector | **No** | zero matches in `lib/`; test-only string in `runtime_safety_controller_test.dart` | P0-T08 ✓, P3-T20 ✓ |
| LocalRetryOrchestrator | **No** | zero matches in `lib/` | P0-T08 ✓, P3-T20 ✓ |
| LocalReassignmentManager | **No** | zero matches in `lib/` | P0-T08 ✓, P3-T20 ✓ |
| LocalCloudFallbackDecision | **No** | zero matches in `lib/` | P0-T08 ✓, P3-T20 ✓ |

**Note:** Worker calls `AssignmentCoordinator.pollAssignment` → `WorkerApiClient.getNextAssignment` which hits server `GET /assignments:next`. Server selects assignment; worker does not choose among tasks locally. Compliant with §2.1.

---

## Work-package cross-reference (P0-T10)

| Plan task | Work package | WP title |
|-----------|--------------|----------|
| P0-T02, P0-T03 | WP-090 | Model release / device compatibility |
| P1-T01–P1-T14 | WP-030, WP-100 | PostgreSQL fencing; Router + auto-lease |
| P1-T03–P1-T05 | WP-045 | WebSocket event relay + outbox |
| P2-* | WP-100, WP-070 | Router; task submission |
| P3-* | WP-110 | Worker runtime hardening |
| P4-* | WP-100 | Router, scoring, fallback |
| P5-* | WP-080, WP-120 | Task catalog; validation |
| P6-* | WP-100 | Policy / routing |
| P7-* | WP-250 | Production canary + release |

---

## Phase 7 exit

- **Date:** 2026-09-02  
- **Result:** PASS — 26/26 chaos scenarios + rollback dry-run; **v1-plan scope** complete at dev level.  
- **Note:** Superseded for future work by v2 (2026-09-05). See Phase 8.

---

## v2 Audit Integration (§72)

Status at adoption (2026-09-06): **DOCUMENTED / NOT CLOSED**. Phase 0–7 provides partial upstream evidence only.

| Audit ID | Task ID | Case | v2 sections | Upstream phase evidence | Status | Notes |
|----------|---------|------|-------------|-------------------------|--------|-------|
| A01 | P8-A01 | T01 | 20, 22, 23, 50, 60 | P1 partial, P8-A01 | **IMPLEMENTED_DEV_ONLY** | `task_runs` + `commit_task_run_terminal` CAS; admission/assignment wiring; T01 integration race NOT_RUN |
| A02 | P8-A02 | T02 | 17–23, 40, 47 | P1, P7 chaos, P8-A02 | **IMPLEMENTED_DEV_ONLY** | `physical_release_state` + stop request/confirm; `:confirmStop` endpoint; stale fence/lease P7 evidence |
| A03 | P8-A03 | T03 | 7, 20–22, 39, 40 | P1-T05, P8-A03 | **IMPLEMENTED_DEV_ONLY** | Poll inbox + ACK + bootstrap; WS replay verifier; T03 integration NOT_RUN |
| A04 | P8-A04 | T04 | 12, 16, 19, 24, 40 | P2, P4, P8-A04 | **IMPLEMENTED_DEV_ONLY** | base/resident/task_peak commitments; resident dedup; warm model retained after task_peak release |
| A05 | P8-A05 | T05 | 12–14, 20, 60 | P2-T05/T06, P8-A05 | **IMPLEMENTED_DEV_ONLY** | `task_execution_allocations` immutable per TaskRun; admission derive + assignment reference; T05 integration NOT_RUN |
| A06 | P8-A06 | T06 | 2, 15–18, 64, 73 | P6, P7 chaos, P8-A06 | **IMPLEMENTED_DEV_ONLY** | CPU window/burst/stop profile in consent DSL; certification SQL + heartbeat sync; 30/50 opt-in; T06 integration NOT_RUN |
| A07 | P8-A07 | T07 | 10, 17, 52, 61 | P2-T12, P8-A07 | **IMPLEMENTED_DEV_ONLY** | DataPolicy DSL + tenant trust eval; cloud fallback data checks; session revoke; T07 integration NOT_RUN |
| A08 | P8-A08 | T08 | 22, 23, 48, 50, 51 | P7 reward chaos, P8-A08 | **IMPLEMENTED_DEV_ONLY** | `result_candidates` + `reward_entitlements` + external-effect receipts; acceptance CAS wiring; T08 crash boundary NOT_RUN |
| A09 | P8-A09 | T09 | 2.4, 8, 14, 21, 43 | P3, P0-T08, P8-A09 | **IMPLEMENTED_DEV_ONLY** | Transport receipt dedup + worker journal; forbidden scheduler absent; T09 E2E NOT_RUN |
| A10 | P8-A10 | T10 | 4, 25, 32 | P3-T04, P8-A10 | **IMPLEMENTED_DEV_ONLY** | Artifact-bound effective limit + formatted-prompt boundary tests; T10 native tokenizer E2E NOT_RUN |
| A11 | P8-A11 | T11 | 14, 26, 27, 48 | P3-T07, P7, P8-A11 | **IMPLEMENTED_DEV_ONLY** | reduceBounds in plan DSL; depth/calls/no-progress stop; T11 E2E NOT_RUN |
| A12 | P8-A12 | T12 | 28, 46, 49, 61 | P3-T08, P7 | **IMPLEMENTED_DEV_ONLY** | `checkpoint_manifests` + `resume_grants`; manifest publish on checkpoint; ResumeGrant validator; T12 cross-Worker E2E NOT_RUN |
| A13 | P8-A13 | T13 | 29–32, 35, 64 | P6, P2-T16 | **IMPLEMENTED_DEV_ONLY** | Runtime co-run matrix + exclusive groups + light work; T13 transfer load E2E NOT_RUN |
| A14 | P8-A14 | T14 | 9, 41–45, 52, 73 | P4 | **IMPLEMENTED_DEV_ONLY** | TaskRun budget counters + scoped retry resolver; artifact/failure affinity; T14 E2E NOT_RUN |
| A15 | P8-A15 | T15 | 55–59, 65, 75 | P5-GAP-08 | **IMPLEMENTED_DEV_ONLY** | 56 unique IDs reconciled; 9 flex dispatch-gated; 7 orphan DSL documented; T15 negative harness NOT_RUN |
| A16 | P8-A16 | T16 | 4, 24, 32, 53, 54 | P3-T16 | **IMPLEMENTED_DEV_ONLY** | Artifact identity manifest + install coordinator + upgrade guard; T16 device E2E NOT_RUN |
| A17 | P8-A17 | T17 | 24, 32, 39, 65 | P7 load sim | **IMPLEMENTED_DEV_ONLY** | Platform profile + fresh-grant guard; T17 physical harness NOT_RUN |
| A18 | P8-A18 | T18 | 48, 49, 51, 58 | P5 validators | **IMPLEMENTED_DEV_ONLY** | Semantic layer + quality/capacity escalation; T18 golden matrix NOT_RUN |
| A19 | P8-A19 | T19 | 9, 31, 36, 40, 73 | P4 fair queue | **IMPLEMENTED_DEV_ONLY** | DRR accounting + backpressure + operating signals; T19 saturation harness NOT_RUN |
| A20 | P8-A20 | T20 | 13, 33, 34, 73 | P6 calibration | **IMPLEMENTED_DEV_ONLY** | Versioned prediction + expiry/fallback; T20 E2E NOT_RUN |
| A21 | P8-A21 | T21 | 28, 31, 54, 55, 61 | P3-T17 | **IMPLEMENTED_DEV_ONLY** | Decode bounds + privacy cleanup; T21 E2E NOT_RUN |
| A22 | P8-A22 | T22 | 24, 41, 53, 75, 76 | P8-T06 | **IMPLEMENTED_DEV_ONLY** | Identity tracer + Native crash reconciliation; T22 physical harness NOT_RUN |
| A23 | P8-A23 | T23 | 0.1, 3, 65–70, 73–75 | P8-T04 | **IMPLEMENTED_DEV_ONLY** | PolicyReadinessRecord + activation gate; §73 areas PARTIAL; T23 NOT_RUN |
| A24 | P8-A24 | T24 | 4, 32.1, 70, 77 | P3-T03, P8-A16 | **IMPLEMENTED_DEV_ONLY** | Runtime upgrade evaluation + rollback gate; T24 device eval NOT_RUN |

Acceptance registry: `plan/evidence/phase-08-p8-t03-acceptance-scenarios-registry.json` (all **NOT RUN**).

---

## Phase 8 exit

- **Date:** —  
- **Result:** DONE (dev scope) — v2 authority adopted; A01–A24 evidence at IMPLEMENTED_DEV_ONLY; §74 T12–T24 integration NOT_RUN; production activation gate CLOSED.  
- **Tasks completed:** P8-T01, P8-T02, P8-T03, P8-T04, P8-T05, P8-T06  

---

## Phase 7 exit

- **Date:** 2026-09-02  
- **Result:** PASS — 26/26 chaos scenarios + rollback dry-run; architecture v1 **implementation closure** complete at dev/staging level.  
- **Tasks completed:** P7-T01, P7-T02, P7-CHAOS-* (28 tasks)  
- **Classification:** IMPLEMENTED_DEV_ONLY — live production deploy proof deferred to staging/canary (WP-250).  
- **Harness:** `tools/run_production_chaos_harness.py`  
- **Sign-off:** `plan/evidence/phase-07-p7-t02-architecture-v1-closure-signoff.json`

---

## Phase 0 exit

- **Date:** 2026-09-01  
- **Result:** PASS — baseline established, gaps documented, Phase 1 cleared to start verification work.  
- **Tasks completed:** P0-T01 … P0-T11  
