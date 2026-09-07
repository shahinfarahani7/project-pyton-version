# EdgeMint Architecture Implementation TODO

> **Authority:** [docs/EDGE-MINT-TARGET-ARCHITECTURE-v2.md](../docs/EDGE-MINT-TARGET-ARCHITECTURE-v2.md) (supersedes v1)
> **Last updated:** 2026-09-06
> **Rule:** After completing any task, update this file and the matching phase file in the same session (see .cursor/rules/architecture-plan-todo.mdc).

## Summary

| Phase | Total | Done | In Progress | Blocked |
|-------|-------|------|-------------|---------|
| 0 — Baseline Correction | 11 | 11 | 0 | 0 |
| 1 — Assignment Integrity | 14 | 14 | 0 | 0 |
| 2 — Resource Foundation | 22 | 22 | 0 | 0 |
| 3 — Worker Runtime Foundation | 21 | 21 | 0 | 0 |
| 4 — Scheduler Upgrade | 16 | 16 | 0 | 0 |
| 5 — Task Catalog Closure | 61 | 61 | 0 | 0 |
| 6 — Adaptive Execution | 14 | 14 | 0 | 0 |
| 7 — Production Proof | 28 | 28 | 0 | 0 |
| 8 — v2 Audit Integration | 31 | 31 | 0 | 0 |
| **Total (Phase 0–7)** | **187** | **187** | **0** | **0** |
| **Total (incl. Phase 8)** | **218** | **218** | **0** | **0** |

## Dependency notes

- Execute phases **sequentially** (0 → 8) unless a task lists explicit cross-phase dependencies.
- Phases 0–7 closed the **v1-plan scope**. Phase 8 closes **v2 audit integration** (§72–77, extended §69).
- Phase 5 per-task slots map to catalog IDs during **P0-T06** inventory — record 	askTypeId in phase file Notes when closing.
- Do **not** mark [x] without IMPLEMENTED_PRODUCTION evidence per Section 66.
- Detail for each task: [phases/](./phases/).

## Phase 0 — Baseline Correction

- [x] **P0-T01** — Audit classification for Phase 0 scope
- [x] **P0-T02** — Verify Qwen2.5 0.5B runtime path
- [x] **P0-T03** — Verify model lifecycle
- [x] **P0-T04** — Close active-model identity loop
- [x] **P0-T05** — Confirm context / maxTokens guard
- [x] **P0-T06** — Inventory 56 Task Catalog entries
- [x] **P0-T07** — Map production vs dev/test paths
- [x] **P0-T08** — Document scheduler authority violations
- [x] **P0-T09** — Produce Phase 0 gap report
- [x] **P0-T10** — Cross-link work-packages.json
- [x] **P0-T11** — Phase 0 exit sign-off
## Phase 1 — Assignment Integrity

- [x] **P1-T01** — Auto Lease Credential Bootstrap (SQL + schema)
- [x] **P1-T02** — Auto Lease Credential Bootstrap (service + tests)
- [x] **P1-T03** — Outbox delivery
- [x] **P1-T04** — WebSocket delivery (worker gateway)
- [x] **P1-T05** — Replay (duplicate-safe)
- [x] **P1-T06** — Lease renewal
- [x] **P1-T07** — Start deadline enforcement
- [x] **P1-T08** — Stale fence rejection
- [x] **P1-T09** — Reservation release on terminal states
- [x] **P1-T10** — Delivery ACK semantics
- [x] **P1-T11** — Assignment state machine (schema + transitions)
- [x] **P1-T12** — Closed failure codes
- [x] **P1-T13** — Phase 1 E2E integration test
- [x] **P1-T14** — Update closure checklist (assignment items)
## Phase 2 — Resource Foundation

- [x] **P2-T01** — Device Capability Contract (DSL schema)
- [x] **P2-T02** — Device Capability Contract (worker reporting)
- [x] **P2-T03** — Worker Calibration Profile (schema)
- [x] **P2-T04** — Worker Calibration Profile (persistence + API)
- [x] **P2-T05** — Task Resource Envelope (DSL)
- [x] **P2-T06** — Task Resource Envelope (catalog binding)
- [x] **P2-T07** — Task Cost Estimator (interface)
- [x] **P2-T08** — Task Cost Estimator (implementation)
- [x] **P2-T09** — Execution Plan (schema)
- [x] **P2-T10** — Execution Plan (resolver)
- [x] **P2-T11** — User Consent Policy (schema) — evidence: `plan/evidence/phase-02-p2-t11-user-resource-policy.json`
- [x] **P2-T12** — User Consent Policy (enforcement hooks) — evidence: `plan/evidence/phase-02-p2-t12-consent-enforcement.json`
- [x] **P2-T13** — Reservation Ledger (SQL) — evidence: `plan/evidence/phase-02-p2-t13-reservation-ledger-sql.json`
- [x] **P2-T14** — Reservation Ledger (service API) — evidence: `plan/evidence/phase-02-p2-t14-reservation-ledger-service.json`
- [x] **P2-T15** — Runtime Compatibility Matrix (DSL) — evidence: `plan/evidence/phase-02-p2-t15-runtime-compatibility-matrix.json`
- [x] **P2-T16** — Runtime Compatibility Matrix (scheduler filter) — evidence: `plan/evidence/phase-02-p2-t16-runtime-compatibility-filter.json`
- [x] **P2-T17** — Exclusive Groups (definition) — evidence: `plan/evidence/phase-02-p2-t17-exclusive-groups.json`
- [x] **P2-T18** — Exclusive Groups (enforcement) — evidence: `plan/evidence/phase-02-p2-t18-exclusive-group-enforcement.json`
- [x] **P2-T19** — Per-resource-class budgets — evidence: `plan/evidence/phase-02-p2-t19-per-class-resource-budgets.json`
- [x] **P2-T20** — Atomic Reservation SQL (transaction design) — evidence: `plan/evidence/phase-02-p2-t20-atomic-assignment-transaction.json`
- [x] **P2-T21** — Atomic Reservation SQL (production verification) — evidence: `plan/evidence/phase-02-p2-t21-atomic-production-verify.json`
- [x] **P2-T22** — Phase 2 exit: closure checklist resource items — evidence: `plan/evidence/phase-02-p2-t22-phase-exit.json`
## Phase 3 — Worker Runtime Foundation

- [x] **P3-T01** — RuntimeSafetyController — evidence: `plan/evidence/phase-03-p3-t01-runtime-safety-controller.json`
- [x] **P3-T02** — WorkerResourceEnforcer — evidence: `plan/evidence/phase-03-p3-t02-worker-resource-enforcer.json`
- [x] **P3-T03** — ModelRuntimeManager (lifecycle) — evidence: `plan/evidence/phase-03-p3-t03-model-runtime-manager.json`
- [x] **P3-T04** — ContextBudgetManager — evidence: `plan/evidence/phase-03-p3-t04-context-budget-manager.json`
- [x] **P3-T05** — Session lifecycle integration — evidence: `plan/evidence/phase-03-p3-t05-session-lifecycle-integration.json`
- [x] **P3-T06** — Semantic ChunkEngine — evidence: `plan/evidence/phase-03-p3-t06-semantic-chunk-engine.json`
- [x] **P3-T07** — Hierarchical Reduce — evidence: `plan/evidence/phase-03-p3-t07-hierarchical-reduce.json`
- [x] **P3-T08** — CheckpointManager — evidence: `plan/evidence/phase-03-p3-t08-checkpoint-manager.json`
- [x] **P3-T09** — ExecutionPlanRunner shell — evidence: `plan/evidence/phase-03-p3-t09-execution-plan-runner.json`
- [x] **P3-T10** — Progress and checkpoint events — evidence: `plan/evidence/phase-03-p3-t10-progress-checkpoint-events.json`
- [x] **P3-T11** — OCR runtime integration under enforcer — evidence: `plan/evidence/phase-03-p3-t11-ocr-runtime-enforcer.json`
- [x] **P3-T12** — Vision runtime integration — evidence: `plan/evidence/phase-03-p3-t12-vision-runtime-integration.json`
- [x] **P3-T13** — Failure evidence submission — evidence: `plan/evidence/phase-03-p3-t13-failure-evidence.json`
- [x] **P3-T14** — Predicted vs observed telemetry — evidence: `plan/evidence/phase-03-p3-t14-predicted-observed-telemetry.json`
- [x] **P3-T15** — Assignment receiver hardening — evidence: `plan/evidence/phase-03-p3-t15-assignment-receiver-hardening.json`
- [x] **P3-T16** — Model download and verify hook — evidence: `plan/evidence/phase-03-p3-t16-model-download-verify-hook.json`
- [x] **P3-T17** — Storage pressure handling — evidence: `plan/evidence/phase-03-p3-t17-storage-pressure-handling.json`
- [x] **P3-T18** — Worker telemetry heartbeat alignment — evidence: `plan/evidence/phase-03-p3-t18-heartbeat-telemetry.json`
- [x] **P3-T19** — Phase 3 integration smoke — evidence: `plan/evidence/phase-03-p3-t19-integration-smoke.json`
- [x] **P3-T20** — Forbidden local scheduler audit (Phase 3 gate) — evidence: `plan/evidence/phase-03-p3-t20-forbidden-scheduler-audit.json`
- [x] **P3-T21** — Phase 3 exit: closure checklist worker items — evidence: `plan/evidence/phase-03-p3-t21-phase-exit.json`
## Phase 4 — Scheduler Upgrade

- [x] **P4-T01** — Hard eligibility filter — evidence: `plan/evidence/phase-04-p4-t01-hard-eligibility-filter.json`
- [x] **P4-T02** — Model locality scoring — evidence: `plan/evidence/phase-04-p4-t02-model-locality-scoring.json`
- [x] **P4-T03** — Resource fit scoring — evidence: `plan/evidence/phase-04-p4-t03-resource-fit-scoring.json`
- [x] **P4-T04** — Fragmentation / scarcity cost — evidence: `plan/evidence/phase-04-p4-t04-scarcity-fragmentation-cost.json`
- [x] **P4-T05** — Failure affinity and cooldown — evidence: `plan/evidence/phase-04-p4-t05-failure-affinity-cooldown.json`
- [x] **P4-T06** — Queue selection ordering — evidence: `plan/evidence/phase-04-p4-t06-queue-selection-ordering.json`
- [x] **P4-T07** — Deterministic worker scoring — evidence: `plan/evidence/phase-04-p4-t07-deterministic-scoring.json`
- [x] **P4-T08** — Routing Decision Audit log — evidence: `plan/evidence/phase-04-p4-t08-routing-decision-audit.json`
- [x] **P4-T09** — Atomic reservation integration in scheduler — evidence: `plan/evidence/phase-04-p4-t09-atomic-scheduler-integration.json`
- [x] **P4-T10** — Cloud fallback decision (server-only) — evidence: `plan/evidence/phase-04-p4-t10-cloud-fallback.json`
- [x] **P4-T11** — Reassignment budget enforcement — evidence: `plan/evidence/phase-04-p4-t11-reassignment-budget.json`
- [x] **P4-T12** — Retry classification routing — evidence: `plan/evidence/phase-04-p4-t12-retry-classifier.json`
- [x] **P4-T13** — Quality-aware escalation hook — evidence: `plan/evidence/phase-04-p4-t13-quality-escalation.json`
- [x] **P4-T14** — Workspace fair queue metrics — evidence: `plan/evidence/phase-04-p4-t14-fair-queue-metrics.json`
- [x] **P4-T15** — Scheduler upgrade integration test — evidence: `plan/evidence/phase-04-p4-t15-scheduler-integration-smoke.json`
- [x] **P4-T16** — Phase 4 exit: closure checklist scheduling items — evidence: `plan/evidence/phase-04-p4-t16-phase-exit.json`
## Phase 5 — Task Catalog Closure

- [x] **P5-CROSS-01** — Result schema validation framework — evidence: `plan/evidence/phase-05-p5-cross-01-result-validation-framework.json`
- [x] **P5-CROSS-02** — Retry policy matrix (all 56 tasks) — evidence: `plan/evidence/phase-05-p5-cross-02-retry-policy-matrix.json`
- [x] **P5-CROSS-03** — Checkpoint policy matrix — evidence: `plan/evidence/phase-05-p5-cross-03-checkpoint-policy-matrix.json`
- [x] **P5-CROSS-04** — Golden test harness — evidence: `plan/evidence/phase-05-p5-cross-04-golden-harness.json`
- [x] **P5-CROSS-05** — Catalog DSL sync and validation gate — evidence: `plan/evidence/phase-05-p5-cross-05-catalog-closure-gate.json`
- [x] **P5-QWEN-01** — Close Qwen task slot 01 (`text.summarize`) — evidence: `plan/evidence/phase-05-p5-qwen-01-text-summarize.json`
- [x] **P5-QWEN-02** — Close Qwen task slot 02 (`text.classify`) — evidence: `plan/evidence/phase-05-p5-qwen-02-text-classify.json`
- [x] **P5-QWEN-03** — Close Qwen task slot 03 (`moderation.prompt_safety`) — evidence: `plan/evidence/phase-05-p5-qwen-03-moderation-prompt-safety.json`
- [x] **P5-QWEN-04** — Close Qwen task slot 04 (`moderation.text`) — evidence: `plan/evidence/phase-05-p5-qwen-04-moderation-text.json`
- [x] **P5-QWEN-05** — Close Qwen task slot 05 (`moderation.profanity`) — evidence: `plan/evidence/phase-05-p5-qwen-05-moderation-profanity.json`
- [x] **P5-QWEN-06** — Close Qwen task slot 06 (`moderation.spam_comment`) — evidence: `plan/evidence/phase-05-p5-qwen-06-moderation-spam-comment.json`
- [x] **P5-QWEN-07** — Close Qwen task slot 07 (`review.fake_detection`) — evidence: `plan/evidence/phase-05-p5-qwen-07-review-fake-detection.json`
- [x] **P5-QWEN-08** — Close Qwen task slot 08 (`review.sentiment`) — evidence: `plan/evidence/phase-05-p5-qwen-08-review-sentiment.json`
- [x] **P5-QWEN-09** — Close Qwen task slot 09 (`review.topic_tagging`) — evidence: `plan/evidence/phase-05-p5-qwen-09-review-topic-tagging.json`
- [x] **P5-QWEN-10** — Close Qwen task slot 10 (`llm.summary_verification`) — evidence: `plan/evidence/phase-05-p5-qwen-10-llm-summary-verification.json`
- [x] **P5-QWEN-11** — Close Qwen task slot 11 (`llm.hallucination_check`) — evidence: `plan/evidence/phase-05-p5-qwen-11-llm-hallucination-check.json`
- [x] **P5-QWEN-12** — Close Qwen task slot 12 (`llm.ocr_output_validation`) — evidence: `plan/evidence/phase-05-p5-qwen-12-llm-ocr-output-validation.json`
- [x] **P5-QWEN-13** — Close Qwen task slot 13 (`llm.policy_violation`) — evidence: `plan/evidence/phase-05-p5-qwen-13-llm-policy-violation.json`
- [x] **P5-QWEN-14** — Close Qwen task slot 14 (`llm.prompt_output_consistency`) — evidence: `plan/evidence/phase-05-p5-qwen-14-llm-prompt-output-consistency.json`
- [x] **P5-QWEN-15** — Close Qwen task slot 15 (`llm.answer_quality_score`) — evidence: `plan/evidence/phase-05-p5-qwen-15-llm-answer-quality-score.json`
- [x] **P5-QWEN-16** — Close Qwen task slot 16 (`llm.suspicious_output`) — evidence: `plan/evidence/phase-05-p5-qwen-16-llm-suspicious-output.json`
- [x] **P5-QWEN-17** — Close Qwen task slot 17 (`nlp.language_detection`) — evidence: `plan/evidence/phase-05-p5-qwen-17-nlp-language-detection.json`
- [x] **P5-QWEN-18** — Close Qwen task slot 18 (`nlp.text_classification`) — evidence: `plan/evidence/phase-05-p5-qwen-18-nlp-text-classification.json`
- [x] **P5-QWEN-19** — Close Qwen task slot 19 (`nlp.spam_fraud_classification`) — evidence: `plan/evidence/phase-05-p5-qwen-19-nlp-spam-fraud-classification.json`
- [x] **P5-QWEN-20** — Close Qwen task slot 20 (`ml.bot_abuse_risk`) — evidence: `plan/evidence/phase-05-p5-qwen-20-ml-bot-abuse-risk.json`
- [x] **P5-QWEN-21** — Close Qwen task slot 21 (`document.extract`) — evidence: `plan/evidence/phase-05-p5-qwen-21-document-extract.json`
- [x] **P5-QWEN-22** — Close Qwen task slot 22 (`extract.amount`) — evidence: `plan/evidence/phase-05-p5-qwen-22-extract-amount.json`
- [x] **P5-QWEN-23** — Close Qwen task slot 23 (`extract.date`) — evidence: `plan/evidence/phase-05-p5-qwen-23-extract-date.json`
- [x] **P5-QWEN-24** — Close Qwen task slot 24 (`extract.order_number`) — evidence: `plan/evidence/phase-05-p5-qwen-24-extract-order-number.json`
- [x] **P5-QWEN-25** — Close Qwen task slot 25 (`extract.document_type`) — evidence: `plan/evidence/phase-05-p5-qwen-25-extract-document-type.json`
- [x] **P5-FLEX-01** — Flex contract slot 01 (`catalog.fake_listing`) — evidence: `plan/evidence/phase-05-p5-flex-01-catalog-fake-listing.json`
- [x] **P5-FLEX-02** — Flex contract slot 02 (`llm.ai_tag_validation`) — evidence: `plan/evidence/phase-05-p5-flex-02-llm-ai-tag-validation.json`
- [x] **P5-FLEX-03** — Flex contract slot 03 (`llm.caption_validation`) — evidence: `plan/evidence/phase-05-p5-flex-03-llm-caption-validation.json`
- [x] **P5-FLEX-04** — Flex contract slot 04 (`dataset.label_verification`) — evidence: `plan/evidence/phase-05-p5-flex-04-dataset-label-verification.json`
- [x] **P5-FLEX-05** — Flex contract slot 05 (`dataset.duplicate_cleanup`) — evidence: `plan/evidence/phase-05-p5-flex-05-dataset-duplicate-cleanup.json`
- [x] **P5-FLEX-06** — Flex contract slot 06 (`dataset.low_quality_removal`) — evidence: `plan/evidence/phase-05-p5-flex-06-dataset-low-quality-removal.json`
- [x] **P5-FLEX-07** — Flex contract slot 07 (`ml.active_learning_prelabel`) — evidence: `plan/evidence/phase-05-p5-flex-07-ml-active-learning-prelabel.json`
- [x] **P5-FLEX-08** — Flex contract slot 08 (`ml.consensus_label_validation`) — evidence: `plan/evidence/phase-05-p5-flex-08-ml-consensus-label-validation.json`
- [x] **P5-FLEX-09** — Flex contract slot 09 (`ml.human_verification_quality`) — evidence: `plan/evidence/phase-05-p5-flex-09-ml-human-verification-quality.json`
- [x] **P5-VIS-01** — Vision task slot 01 (`image.classify`) — evidence: `plan/evidence/phase-05-p5-vis-01-image-classify.json`
- [x] **P5-VIS-02** — Vision task slot 02 (`safety.nsfw_detection`) — evidence: `plan/evidence/phase-05-p5-vis-02-safety-nsfw-detection.json`
- [x] **P5-VIS-03** — Vision task slot 03 (`safety.violence_detection`) — evidence: `plan/evidence/phase-05-p5-vis-03-safety-violence-detection.json`
- [x] **P5-VIS-04** — Vision task slot 04 (`safety.weapon_detection`) — evidence: `plan/evidence/phase-05-p5-vis-04-safety-weapon-detection.json`
- [x] **P5-VIS-05** — Vision task slot 05 (`safety.unsafe_image`) — evidence: `plan/evidence/phase-05-p5-vis-05-safety-unsafe-image.json`
- [x] **P5-VIS-06** — Vision task slot 06 (`moderation.profile_image`) — evidence: `plan/evidence/phase-05-p5-vis-06-moderation-profile-image.json`
- [x] **P5-VIS-07** — Vision task slot 07 (`moderation.generated_image`) — evidence: `plan/evidence/phase-05-p5-vis-07-moderation-generated-image.json`
- [x] **P5-VIS-08** — Vision task slot 08 (`catalog.image_tagging`) — evidence: `plan/evidence/phase-05-p5-vis-08-catalog-image-tagging.json`
- [x] **P5-VIS-09** — Vision task slot 09 (`catalog.product_classification`) — evidence: `plan/evidence/phase-05-p5-vis-09-catalog-product-classification.json`
- [x] **P5-VIS-10** — Vision task slot 10 (`catalog.product_quality_score`) — evidence: `plan/evidence/phase-05-p5-vis-10-catalog-product-quality-score.json`
- [x] **P5-VIS-11** — Vision task slot 11 (`catalog.brand_logo`) — evidence: `plan/evidence/phase-05-p5-vis-11-catalog-brand-logo.json`
- [x] **P5-VIS-12** — Vision task slot 12 (`catalog.prohibited_product`) — evidence: `plan/evidence/phase-05-p5-vis-12-catalog-prohibited-product.json`
- [x] **P5-VIS-13** — Vision task slot 13 (`llm.image_output_safety`) — evidence: `plan/evidence/phase-05-p5-vis-13-llm-image-output-safety.json`
- [x] **P5-VIS-14** — Vision task slot 14 (`image.remove_background`) — evidence: `plan/evidence/phase-05-p5-vis-14-image-remove-background.json`
- [x] **P5-GAP-01** — Resolve taxonomy gap slot 01 (`document.ocr` canonical OCR) — evidence: `plan/evidence/phase-05-p5-gap-01-document-ocr.json`
- [x] **P5-GAP-02** — Resolve taxonomy gap slot 02 (`ocr.receipt`) — evidence: `plan/evidence/phase-05-p5-gap-02-ocr-receipt.json`
- [x] **P5-GAP-03** — Resolve taxonomy gap slot 03 (`ocr.invoice`) — evidence: `plan/evidence/phase-05-p5-gap-03-ocr-invoice.json`
- [x] **P5-GAP-04** — Resolve taxonomy gap slot 04 (`ocr.simple_form`) — evidence: `plan/evidence/phase-05-p5-gap-04-ocr-simple-form.json`
- [x] **P5-GAP-05** — Resolve taxonomy gap slot 05 (`ocr.product_label`) — evidence: `plan/evidence/phase-05-p5-gap-05-ocr-product-label.json`
- [x] **P5-GAP-06** — Resolve taxonomy gap slot 06 (`quality.document_image`, `quality.blurry_image`) — evidence: `plan/evidence/phase-05-p5-gap-06-quality-lightweight-vision.json`
- [x] **P5-GAP-07** — Resolve taxonomy gap slot 07 (`catalog.duplicate_image`) — evidence: `plan/evidence/phase-05-p5-gap-07-catalog-duplicate-image.json`
- [x] **P5-GAP-08** — Catalog closure sign-off (56/56 classified) — evidence: `plan/evidence/phase-05-p5-gap-08-catalog-signoff.json`
## Phase 6 — Adaptive Execution

- [x] **P6-T01** — 30% default resource profile (server policy) — evidence: `plan/evidence/phase-06-p6-t01-30-percent-default-policy.json`
- [x] **P6-T02** — 50% opt-in profile (server policy) — evidence: `plan/evidence/phase-06-p6-t02-50-percent-opt-in-policy.json`
- [x] **P6-T03** — Device calibration production loop — evidence: `plan/evidence/phase-06-p6-t03-device-calibration-loop.json`
- [x] **P6-T04** — Certified OCR concurrency (heavy + OCR) — evidence: `plan/evidence/phase-06-p6-t04-certified-ocr-concurrency.json`
- [x] **P6-T05** — Runtime-pair compatibility enforcement — evidence: `plan/evidence/phase-06-p6-t05-runtime-pair-enforcement.json`
- [x] **P6-T06** — Dynamic resource prediction — evidence: `plan/evidence/phase-06-p6-t06-dynamic-resource-prediction.json`
- [x] **P6-T07** — Prediction feedback loop closure — evidence: `plan/evidence/phase-06-p6-t07-prediction-feedback-loop.json`
- [x] **P6-T08** — Consent increase handling (30% → 50%) — evidence: `plan/evidence/phase-06-p6-t08-consent-increase-30-to-50.json`
- [x] **P6-T09** — Consent decrease handling (50% → 30%) — evidence: `plan/evidence/phase-06-p6-t09-consent-decrease-50-to-30.json`
- [x] **P6-T10** — Full consent revocation handling — evidence: `plan/evidence/phase-06-p6-t10-consent-revocation.json`
- [x] **P6-T11** — Adaptive concurrency certification workflow — evidence: `plan/evidence/phase-06-p6-t11-concurrency-certification-workflow.json`
- [x] **P6-T12** — Thermal transition policy — evidence: `plan/evidence/phase-06-p6-t12-thermal-transition-policy.json`
- [x] **P6-T13** — Light work during heavy inference (production) — evidence: `plan/evidence/phase-06-p6-t13-light-work-during-heavy.json`
- [x] **P6-T14** — Phase 6 exit: closure checklist consent items — evidence: `plan/evidence/phase-06-p6-t14-phase-6-exit-checklist.json`
## Phase 7 — Production Proof

- [x] **P7-T01** — Rollout and rollback procedures — evidence: `plan/evidence/phase-07-p7-t01-rollout-rollback-drill.json`
- [x] **P7-T02** — Phase 7 exit: architecture v1 closure sign-off — evidence: `plan/evidence/phase-07-p7-t02-architecture-v1-closure-signoff.json`
- [x] **P7-CHAOS-20-workers** — 20-worker load test — evidence: `plan/evidence/phase-07-p7-chaos-20-workers.json`
- [x] **P7-CHAOS-56-task-catalog** — Full catalog execution sample — evidence: `plan/evidence/phase-07-p7-chaos-56-task-catalog.json`
- [x] **P7-CHAOS-multi-assignment** — Multi-assignment per worker — evidence: `plan/evidence/phase-07-p7-chaos-multi-assignment.json`
- [x] **P7-CHAOS-resource-exhaustion** — Resource exhaustion — evidence: `plan/evidence/phase-07-p7-chaos-resource-exhaustion.json`
- [x] **P7-CHAOS-worker-disconnect** — Worker disconnect mid-assignment — evidence: `plan/evidence/phase-07-p7-chaos-worker-disconnect.json`
- [x] **P7-CHAOS-lease-expiry** — Lease expiry — evidence: `plan/evidence/phase-07-p7-chaos-lease-expiry.json`
- [x] **P7-CHAOS-stale-result** — Stale result submission — evidence: `plan/evidence/phase-07-p7-chaos-stale-result.json`
- [x] **P7-CHAOS-runtime-crash** — Runtime crash during execution — evidence: `plan/evidence/phase-07-p7-chaos-runtime-crash.json`
- [x] **P7-CHAOS-oom** — OOM / memory pressure — evidence: `plan/evidence/phase-07-p7-chaos-oom.json`
- [x] **P7-CHAOS-thermal-failure** — Thermal failure — evidence: `plan/evidence/phase-07-p7-chaos-thermal-failure.json`
- [x] **P7-CHAOS-retry-exhaustion** — Retry exhaustion — evidence: `plan/evidence/phase-07-p7-chaos-retry-exhaustion.json`
- [x] **P7-CHAOS-cloud-fallback** — Cloud fallback — evidence: `plan/evidence/phase-07-p7-chaos-cloud-fallback.json`
- [x] **P7-CHAOS-reward-exactly-once** — Reward exactly-once — evidence: `plan/evidence/phase-07-p7-chaos-reward-exactly-once.json`
- [x] **P7-CHAOS-long-context-summarize** — Long-context summarize — evidence: `plan/evidence/phase-07-p7-chaos-long-context-summarize.json`
- [x] **P7-CHAOS-chunk-resume** — Chunk resume after crash — evidence: `plan/evidence/phase-07-p7-chaos-chunk-resume.json`
- [x] **P7-CHAOS-recursive-reduce** — Recursive reduce depth — evidence: `plan/evidence/phase-07-p7-chaos-recursive-reduce.json`
- [x] **P7-CHAOS-model-corruption** — Model corruption detection — evidence: `plan/evidence/phase-07-p7-chaos-model-corruption.json`
- [x] **P7-CHAOS-model-update** — Model update during residency — evidence: `plan/evidence/phase-07-p7-chaos-model-update.json`
- [x] **P7-CHAOS-storage-pressure** — Storage pressure — evidence: `plan/evidence/phase-07-p7-chaos-storage-pressure.json`
- [x] **P7-CHAOS-consent-30-to-50** — Consent 30% to 50% — evidence: `plan/evidence/phase-07-p7-chaos-consent-30-to-50.json`
- [x] **P7-CHAOS-consent-50-to-30** — Consent 50% to 30% — evidence: `plan/evidence/phase-07-p7-chaos-consent-50-to-30.json`
- [x] **P7-CHAOS-consent-revoke** — Full consent revocation — evidence: `plan/evidence/phase-07-p7-chaos-consent-revoke.json`
- [x] **P7-CHAOS-thermal-transition** — Thermal state transition — evidence: `plan/evidence/phase-07-p7-chaos-thermal-transition.json`
- [x] **P7-CHAOS-websocket-replay** — WebSocket replay — evidence: `plan/evidence/phase-07-p7-chaos-websocket-replay.json`
- [x] **P7-CHAOS-stale-fence-writes** — Stale fence writes — evidence: `plan/evidence/phase-07-p7-chaos-stale-fence-writes.json`
- [x] **P7-CHAOS-duplicate-delivery** — Duplicate assignment delivery — evidence: `plan/evidence/phase-07-p7-chaos-duplicate-delivery.json`

## Phase 8 — v2 Audit Integration

- [x] **P8-T01** — Adopt v2 as canonical authority — evidence: `plan/evidence/phase-08-p8-t01-v2-authority-adoption.json`
- [x] **P8-T02** — Audit traceability matrix A01–A24 — evidence: `plan/audit-matrix.md` § v2 Audit Integration
- [x] **P8-T03** — Acceptance scenarios registry T01–T24 — evidence: `plan/evidence/phase-08-p8-t03-acceptance-scenarios-registry.json`
- [x] **P8-T04** — Policy readiness gate gap analysis (§73) — evidence: `plan/evidence/phase-08-p8-t04-policy-readiness-gap.json`
- [x] **P8-T05** — Current-state evidence register baseline (§75) — evidence: `plan/evidence/phase-08-p8-t05-current-state-register.json`
- [x] **P8-T06** — Active model identity investigation (§76) — evidence: `plan/evidence/phase-08-p8-t06-identity-loop-investigation.json` (source static; device repro → P8-A22)
- [x] **P8-T07** — Phase 8 exit: v2 closure sign-off — evidence: `plan/evidence/phase-08-p8-t07-v2-closure-signoff.json` (A01–A24 IMPLEMENTED_DEV_ONLY; §74 T12–T24 NOT_RUN; production gate CLOSED)
- [x] **P8-A01** — TaskRun/terminal-race ownership (A01 / T01) — evidence: `plan/evidence/phase-08-p8-a01-task-run-terminal-cas.json` (IMPLEMENTED_DEV_ONLY; T01 integration race NOT_RUN)
- [x] **P8-A02** — Bounded grant, fencing, stop, physical release (A02 / T02) — evidence: `plan/evidence/phase-08-p8-a02-physical-release-grant.json` (IMPLEMENTED_DEV_ONLY; T02 integration NOT_RUN)
- [x] **P8-A03** — Durable delivery, Inbox, ACK, replay (A03 / T03) — evidence: `plan/evidence/phase-08-p8-a03-assignment-delivery-inbox.json` (IMPLEMENTED_DEV_ONLY; T03 integration NOT_RUN)
- [x] **P8-A04** — Memory accounting resident/base/peak (A04 / T04) — evidence: `plan/evidence/phase-08-p8-a04-memory-accounting.json` (IMPLEMENTED_DEV_ONLY; T04 integration NOT_RUN)
- [x] **P8-A05** — Envelope vs ExecutionAllocation (A05 / T05) — evidence: `plan/evidence/phase-08-p8-a05-execution-allocation.json` (IMPLEMENTED_DEV_ONLY; T05 integration NOT_RUN)
- [x] **P8-A06** — Contribution units and explicit consent (A06 / T06) — evidence: `plan/evidence/phase-08-p8-a06-contribution-consent-enforcement.json` (IMPLEMENTED_DEV_ONLY; T06 integration NOT_RUN)
- [x] **P8-A07** — Tenant/data trust and Cloud policy (A07 / T07) — evidence: `plan/evidence/phase-08-p8-a07-tenant-data-trust.json` (IMPLEMENTED_DEV_ONLY; T07 integration NOT_RUN)
- [x] **P8-A08** — Validation/reward uniqueness (A08 / T08) — evidence: `plan/evidence/phase-08-p8-a08-validation-reward-uniqueness.json`
- [x] **P8-A09** — Local Plan and transport recovery (A09 / T09) — evidence: `plan/evidence/phase-08-p8-a09-transport-recovery-boundary.json`
- [x] **P8-A10** — Context and output enforcement (A10 / T10) — evidence: `plan/evidence/phase-08-p8-a10-context-output-enforcement.json`
- [x] **P8-A11** — Bounded hierarchical reduce (A11 / T11) — evidence: `plan/evidence/phase-08-p8-a11-hierarchical-reduce-bounds.json`
- [x] **P8-A12** — Checkpoint provenance and ResumeGrant (A12 / T12) — evidence: `plan/evidence/phase-08-p8-a12-checkpoint-resume-grant.json`
- [x] **P8-A13** — Runtime-pair conflicts (A13 / T13) — evidence: `plan/evidence/phase-08-p8-a13-runtime-pair-light-work.json`
- [x] **P8-A14** — Scoped retries and affinity (A14 / T14) — evidence: `plan/evidence/phase-08-p8-a14-scoped-retry-affinity.json`
- [x] **P8-A15** — Catalog reconciliation and Flex gates (A15 / T15) — evidence: `plan/evidence/phase-08-p8-a15-catalog-reconciliation-flex-gates.json`
- [x] **P8-A16** — Artifact/install/runtime identity (A16 / T16) — evidence: `plan/evidence/phase-08-p8-a16-artifact-install-runtime-identity.json`
- [x] **P8-A17** — Physical-device lifecycle proof (A17 / T17) — evidence: `plan/evidence/phase-08-p8-a17-physical-device-lifecycle-proof.json` (IMPLEMENTED_DEV_ONLY; T17 physical harness NOT_RUN)
- [x] **P8-A18** — Semantic quality validation (A18 / T18) — evidence: `plan/evidence/phase-08-p8-a18-semantic-quality-validation.json` (IMPLEMENTED_DEV_ONLY; T18 golden matrix NOT_RUN)
- [x] **P8-A19** — DRR fairness and backpressure (A19 / T19) — evidence: `plan/evidence/phase-08-p8-a19-drr-fairness-backpressure.json` (IMPLEMENTED_DEV_ONLY; T19 saturation harness NOT_RUN)
- [x] **P8-A20** — Versioned calibration/prediction (A20 / T20) — evidence: `plan/evidence/phase-08-p8-a20-versioned-calibration-prediction.json` (IMPLEMENTED_DEV_ONLY; T20 E2E NOT_RUN)
- [x] **P8-A21** — Decode bounds and privacy cleanup (A21 / T21) — evidence: `plan/evidence/phase-08-p8-a21-decode-bounds-privacy-cleanup.json` (IMPLEMENTED_DEV_ONLY; T21 E2E NOT_RUN)
- [x] **P8-A22** — Identity loop and Native crash evidence (A22 / T22) — evidence: `plan/evidence/phase-08-p8-a22-identity-loop-native-crash.json` (IMPLEMENTED_DEV_ONLY; T22 physical harness NOT_RUN)
- [x] **P8-A23** — Policy gates and mixed-version rollout (A23 / T23) — evidence: `plan/evidence/phase-08-p8-a23-policy-readiness-gates.json` (IMPLEMENTED_DEV_ONLY; gate CLOSED; T23 harness NOT_RUN)
- [x] **P8-A24** — Runtime upgrade compatibility (A24 / T24) — evidence: `plan/evidence/phase-08-p8-a24-runtime-upgrade-compatibility.json` (IMPLEMENTED_DEV_ONLY; T24 device eval NOT_RUN)
