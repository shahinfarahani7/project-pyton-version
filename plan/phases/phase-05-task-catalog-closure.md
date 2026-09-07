# Phase 5 — Task Catalog Closure

> **Architecture ref:** Section 65 Phase 5, Sections 55–59, 56–57  
> **Depends on:** Phase 3–4 substantially complete  
> **Blocks:** Phase 7 catalog-wide proof

## Objective

Close all 56 task types: Qwen (25), Flex contracts (9), Vision (14), resolve 8 taxonomy gaps, plus cross-cutting validation/retry/checkpoint/golden tests.

Each per-task task follows the same closure pattern (Section 55):

1. Resource profile bound  
2. Result schema validation  
3. Retry policy assigned  
4. Checkpoint policy (if applicable)  
5. Golden test passes on production path  

---

## Cross-cutting tasks

### P5-CROSS-01 — Result schema validation framework

- **Status:** done
- **Depends on:** P4-T16
- **Objective:** Server-side result validation framework (Section 48).
- **Impacted paths:** backend validation service, DSL result schemas
- **Acceptance criteria:** Validator pluggable per task type; rejects malformed results before reward.
- **Evidence:** `plan/evidence/phase-05-p5-cross-01-result-validation-framework.json`; `validator.py`; `test_document_ocr_validator.py`
- **Rollback:** N/A.

---

### P5-CROSS-02 — Retry policy matrix (all 56 tasks)

- **Status:** done
- **Depends on:** P4-T12, P5-CROSS-01
- **Objective:** Assign retry class per task type in catalog DSL.
- **Impacted paths:** `dsl/`, task catalog, routing classifier
- **Acceptance criteria:** 56/56 tasks have retry class; Flex without contract remain non-executable.
- **Evidence:** `plan/evidence/phase-05-p5-cross-02-retry-policy-matrix.json`; `dsl/policies/retry/task-retry-matrix-v1.yaml`; `test_retry_policy_matrix.py`; `validate_dsl.py`
- **Rollback:** Revert matrix file.

---

### P5-CROSS-03 — Checkpoint policy matrix

- **Status:** done
- **Depends on:** P3-T08
- **Objective:** Define which tasks support checkpoint/resume (Section 28, 46).
- **Impacted paths:** catalog DSL, execution plan resolver
- **Acceptance criteria:** Long-running tasks flagged; short tasks explicitly `checkpoint: false`.
- **Evidence:** `plan/evidence/phase-05-p5-cross-03-checkpoint-policy-matrix.json`; `task-checkpoint-matrix-v1.yaml`; `test_checkpoint_policy_matrix.py`
- **Rollback:** N/A.

---

### P5-CROSS-04 — Golden test harness

- **Status:** done
- **Depends on:** P5-CROSS-01
- **Objective:** Reusable harness for per-task golden I/O tests (Section 55).
- **Impacted paths:** `tools/`, `tests/`, `artifacts/`
- **Acceptance criteria:** Harness runs single task type with fixture input/output; CI integrable.
- **Evidence:** `plan/evidence/phase-05-p5-cross-04-golden-harness.json`; `tools/run_golden_task_harness.py`; `tests/golden/fixtures/document.ocr.json`
- **Rollback:** N/A.

---

### P5-CROSS-05 — Catalog DSL sync and validation gate

- **Status:** done
- **Depends on:** P5-CROSS-02, P5-CROSS-03
- **Objective:** CI gate: no task enters executable queue without complete contract (Section 55).
- **Impacted paths:** `tools/validate_dsl.py`, task catalog loader, portal API
- **Acceptance criteria:** Incomplete tasks rejected at create time with closed error code.
- **Evidence:** `plan/evidence/phase-05-p5-cross-05-catalog-closure-gate.json`; `validate_catalog_closure.py`; `test_catalog_closure.py`
- **Rollback:** Warn-only mode (`EDGEMINT_CATALOG_CLOSURE_MODE=warn_only`).

---

## Qwen task closure (25 tasks)

> Populate `taskTypeId` during P0-T06 inventory. Each task closes one Qwen-family task type.

### P5-QWEN-01 — Close Qwen task slot 01

- **Status:** done
- **Notes:** `taskTypeId=text.summarize`
- **Depends on:** P5-CROSS-04, P0-T06
- **Objective:** Full closure for Qwen task #1 (record `taskTypeId` in Notes when known).
- **Impacted paths:** catalog, worker handler, validation schema, golden fixture
- **Acceptance criteria:** Resource profile + validation + retry + golden test PASS on prod path.
- **Evidence:** `plan/evidence/phase-05-p5-qwen-01-text-summarize.json`; `dsl/catalog/task-types/text-summarize.yaml`; `tests/golden/fixtures/text.summarize.json`; `src/backend/tests/results/test_text_summarize_validator.py`
- **Rollback:** Mark task non-executable in catalog.

### P5-QWEN-02 — Close Qwen task slot 02

- **Status:** done
- **Notes:** `taskTypeId=text.classify`
- **Depends on:** P5-CROSS-04, P0-T06
- **Objective:** Full closure for Qwen task #2.
- **Impacted paths:** catalog, worker handler, validation schema, golden fixture
- **Acceptance criteria:** Same as P5-QWEN-01.
- **Evidence:** `plan/evidence/phase-05-p5-qwen-02-text-classify.json`; `dsl/catalog/task-types/text-classify.yaml`; `tests/golden/fixtures/text.classify.json`
- **Rollback:** Mark non-executable.

### P5-QWEN-03 — Close Qwen task slot 03

- **Status:** done
- **Notes:** `taskTypeId=moderation.prompt_safety`
- **Depends on:** P5-CROSS-04, P0-T06
- **Objective:** Full closure for Qwen task #3.
- **Acceptance criteria:** Same as P5-QWEN-01.
- **Evidence:** `plan/evidence/phase-05-p5-qwen-03-moderation-prompt-safety.json`; `dsl/catalog/task-types/moderation-prompt-safety.yaml`; `tests/golden/fixtures/moderation.prompt_safety.json`

### P5-QWEN-04 — Close Qwen task slot 04

- **Status:** done
- **Notes:** `taskTypeId=moderation.text`
- **Depends on:** P5-CROSS-04, P0-T06
- **Objective:** Full closure for Qwen task #4.
- **Acceptance criteria:** Same as P5-QWEN-01.
- **Evidence:** `plan/evidence/phase-05-p5-qwen-04-moderation-text.json`; `dsl/catalog/task-types/moderation-text.yaml`; `tests/golden/fixtures/moderation.text.json`

### P5-QWEN-05 — Close Qwen task slot 05

- **Status:** done
- **Notes:** `taskTypeId=moderation.profanity`
- **Depends on:** P5-CROSS-04, P0-T06
- **Objective:** Full closure for Qwen task #5.
- **Acceptance criteria:** Same as P5-QWEN-01.
- **Evidence:** `plan/evidence/phase-05-p5-qwen-05-moderation-profanity.json`; `dsl/catalog/task-types/moderation-profanity.yaml`; `tests/golden/fixtures/moderation.profanity.json`

### P5-QWEN-06 — Close Qwen task slot 06

- **Status:** done
- **Notes:** `taskTypeId=moderation.spam_comment`
- **Depends on:** P5-CROSS-04, P0-T06
- **Objective:** Full closure for Qwen task #6.
- **Acceptance criteria:** Same as P5-QWEN-01.
- **Evidence:** `plan/evidence/phase-05-p5-qwen-06-moderation-spam-comment.json`; `dsl/catalog/task-types/moderation-spam-comment.yaml`; `tests/golden/fixtures/moderation.spam_comment.json`

### P5-QWEN-07 — Close Qwen task slot 07

- **Status:** done
- **Notes:** `taskTypeId=review.fake_detection`
- **Depends on:** P5-CROSS-04, P0-T06
- **Objective:** Full closure for Qwen task #7.
- **Acceptance criteria:** Same as P5-QWEN-01.
- **Evidence:** `plan/evidence/phase-05-p5-qwen-07-review-fake-detection.json`; `dsl/catalog/task-types/review-fake-detection.yaml`; `tests/golden/fixtures/review.fake_detection.json`

### P5-QWEN-08 — Close Qwen task slot 08

- **Status:** done
- **Notes:** `taskTypeId=review.sentiment`
- **Depends on:** P5-CROSS-04, P0-T06
- **Objective:** Full closure for Qwen task #8.
- **Acceptance criteria:** Same as P5-QWEN-01.
- **Evidence:** `plan/evidence/phase-05-p5-qwen-08-review-sentiment.json`; `dsl/catalog/task-types/review-sentiment.yaml`; `tests/golden/fixtures/review.sentiment.json`

### P5-QWEN-09 — Close Qwen task slot 09

- **Status:** done
- **Notes:** `taskTypeId=review.topic_tagging`
- **Depends on:** P5-CROSS-04, P0-T06
- **Objective:** Full closure for Qwen task #9.
- **Acceptance criteria:** Same as P5-QWEN-01.
- **Evidence:** `plan/evidence/phase-05-p5-qwen-09-review-topic-tagging.json`; `dsl/catalog/task-types/review-topic-tagging.yaml`; `tests/golden/fixtures/review.topic_tagging.json`

### P5-QWEN-10 — Close Qwen task slot 10

- **Status:** done
- **Notes:** `taskTypeId=llm.summary_verification`
- **Depends on:** P5-CROSS-04, P0-T06
- **Objective:** Full closure for Qwen task #10.
- **Acceptance criteria:** Same as P5-QWEN-01.
- **Evidence:** `plan/evidence/phase-05-p5-qwen-10-llm-summary-verification.json`; `dsl/catalog/task-types/llm-summary-verification.yaml`; `tests/golden/fixtures/llm.summary_verification.json`

### P5-QWEN-11 — Close Qwen task slot 11

- **Status:** done
- **Notes:** `taskTypeId=llm.hallucination_check`
- **Depends on:** P5-CROSS-04, P0-T06
- **Objective:** Full closure for Qwen task #11.
- **Acceptance criteria:** Same as P5-QWEN-01.
- **Evidence:** `plan/evidence/phase-05-p5-qwen-11-llm-hallucination-check.json`; `dsl/catalog/task-types/llm-hallucination-check.yaml`; `tests/golden/fixtures/llm.hallucination_check.json`

### P5-QWEN-12 — Close Qwen task slot 12

- **Status:** done
- **Notes:** `taskTypeId=llm.ocr_output_validation`
- **Depends on:** P5-CROSS-04, P0-T06
- **Objective:** Full closure for Qwen task #12.
- **Acceptance criteria:** Same as P5-QWEN-01.
- **Evidence:** `plan/evidence/phase-05-p5-qwen-12-llm-ocr-output-validation.json`; `dsl/catalog/task-types/llm-ocr-output-validation.yaml`; `tests/golden/fixtures/llm.ocr_output_validation.json`

### P5-QWEN-13 — Close Qwen task slot 13

- **Status:** done
- **Notes:** `taskTypeId=llm.policy_violation`
- **Depends on:** P5-CROSS-04, P0-T06
- **Objective:** Full closure for Qwen task #13.
- **Acceptance criteria:** Same as P5-QWEN-01.
- **Evidence:** `plan/evidence/phase-05-p5-qwen-13-llm-policy-violation.json`; `dsl/catalog/task-types/llm-policy-violation.yaml`; `tests/golden/fixtures/llm.policy_violation.json`

### P5-QWEN-14 — Close Qwen task slot 14

- **Status:** done
- **Notes:** `taskTypeId=llm.prompt_output_consistency`
- **Depends on:** P5-CROSS-04, P0-T06
- **Objective:** Full closure for Qwen task #14.
- **Acceptance criteria:** Same as P5-QWEN-01.
- **Evidence:** `plan/evidence/phase-05-p5-qwen-14-llm-prompt-output-consistency.json`; `dsl/catalog/task-types/llm-prompt-output-consistency.yaml`; `tests/golden/fixtures/llm.prompt_output_consistency.json`

### P5-QWEN-15 — Close Qwen task slot 15

- **Status:** done
- **Notes:** `taskTypeId=llm.answer_quality_score`
- **Depends on:** P5-CROSS-04, P0-T06
- **Objective:** Full closure for Qwen task #15.
- **Acceptance criteria:** Same as P5-QWEN-01.
- **Evidence:** `plan/evidence/phase-05-p5-qwen-15-llm-answer-quality-score.json`; `dsl/catalog/task-types/llm-answer-quality-score.yaml`; `tests/golden/fixtures/llm.answer_quality_score.json`

### P5-QWEN-16 — Close Qwen task slot 16

- **Status:** done
- **Notes:** `taskTypeId=llm.suspicious_output`
- **Depends on:** P5-CROSS-04, P0-T06
- **Objective:** Full closure for Qwen task #16.
- **Acceptance criteria:** Same as P5-QWEN-01.
- **Evidence:** `plan/evidence/phase-05-p5-qwen-16-llm-suspicious-output.json`; `dsl/catalog/task-types/llm-suspicious-output.yaml`; `tests/golden/fixtures/llm.suspicious_output.json`

### P5-QWEN-17 — Close Qwen task slot 17

- **Status:** done
- **Notes:** `taskTypeId=nlp.language_detection`
- **Depends on:** P5-CROSS-04, P0-T06
- **Objective:** Full closure for Qwen task #17.
- **Acceptance criteria:** Same as P5-QWEN-01.
- **Evidence:** `plan/evidence/phase-05-p5-qwen-17-nlp-language-detection.json`; `dsl/catalog/task-types/nlp-language-detection.yaml`; `tests/golden/fixtures/nlp.language_detection.json`

### P5-QWEN-18 — Close Qwen task slot 18

- **Status:** done
- **Notes:** `taskTypeId=nlp.text_classification`
- **Depends on:** P5-CROSS-04, P0-T06
- **Objective:** Full closure for Qwen task #18.
- **Acceptance criteria:** Same as P5-QWEN-01.
- **Evidence:** `plan/evidence/phase-05-p5-qwen-18-nlp-text-classification.json`; `dsl/catalog/task-types/nlp-text-classification.yaml`; `tests/golden/fixtures/nlp.text_classification.json`

### P5-QWEN-19 — Close Qwen task slot 19

- **Status:** done
- **Notes:** `taskTypeId=nlp.spam_fraud_classification`
- **Depends on:** P5-CROSS-04, P0-T06
- **Objective:** Full closure for Qwen task #19.
- **Acceptance criteria:** Same as P5-QWEN-01.
- **Evidence:** `plan/evidence/phase-05-p5-qwen-19-nlp-spam-fraud-classification.json`; `dsl/catalog/task-types/nlp-spam-fraud-classification.yaml`; `tests/golden/fixtures/nlp.spam_fraud_classification.json`

### P5-QWEN-20 — Close Qwen task slot 20

- **Status:** done
- **Notes:** `taskTypeId=ml.bot_abuse_risk`
- **Depends on:** P5-CROSS-04, P0-T06
- **Objective:** Full closure for Qwen task #20.
- **Acceptance criteria:** Same as P5-QWEN-01.
- **Evidence:** `plan/evidence/phase-05-p5-qwen-20-ml-bot-abuse-risk.json`; `dsl/catalog/task-types/ml-bot-abuse-risk.yaml`; `tests/golden/fixtures/ml.bot_abuse_risk.json`

### P5-QWEN-21 — Close Qwen task slot 21

- **Status:** done
- **Notes:** `taskTypeId=document.extract`
- **Depends on:** P5-CROSS-04, P0-T06
- **Objective:** Full closure for Qwen task #21.
- **Acceptance criteria:** Same as P5-QWEN-01.
- **Evidence:** `plan/evidence/phase-05-p5-qwen-21-document-extract.json`; `dsl/catalog/task-types/document-extract.yaml`; `tests/golden/fixtures/document.extract.json`

### P5-QWEN-22 — Close Qwen task slot 22

- **Status:** done
- **Notes:** `taskTypeId=extract.amount`
- **Depends on:** P5-CROSS-04, P0-T06
- **Objective:** Full closure for Qwen task #22.
- **Acceptance criteria:** Same as P5-QWEN-01.
- **Evidence:** `plan/evidence/phase-05-p5-qwen-22-extract-amount.json`; `dsl/catalog/task-types/extract-amount.yaml`; `tests/golden/fixtures/extract.amount.json`

### P5-QWEN-23 — Close Qwen task slot 23

- **Status:** done
- **Notes:** `taskTypeId=extract.date`
- **Depends on:** P5-CROSS-04, P0-T06
- **Objective:** Full closure for Qwen task #23.
- **Acceptance criteria:** Same as P5-QWEN-01.
- **Evidence:** `plan/evidence/phase-05-p5-qwen-23-extract-date.json`; `dsl/catalog/task-types/extract-date.yaml`; `tests/golden/fixtures/extract.date.json`

### P5-QWEN-24 — Close Qwen task slot 24

- **Status:** done
- **Notes:** `taskTypeId=extract.order_number`
- **Depends on:** P5-CROSS-04, P0-T06
- **Objective:** Full closure for Qwen task #24.
- **Acceptance criteria:** Same as P5-QWEN-01.
- **Evidence:** `plan/evidence/phase-05-p5-qwen-24-extract-order-number.json`; `dsl/catalog/task-types/extract-order-number.yaml`; `tests/golden/fixtures/extract.order_number.json`

### P5-QWEN-25 — Close Qwen task slot 25

- **Status:** done
- **Notes:** `taskTypeId=extract.document_type`
- **Depends on:** P5-CROSS-04, P0-T06
- **Objective:** Full closure for Qwen task #25.
- **Acceptance criteria:** Same as P5-QWEN-01.
- **Evidence:** `plan/evidence/phase-05-p5-qwen-25-extract-document-type.json`; `dsl/catalog/task-types/extract-document-type.yaml`; `tests/golden/fixtures/extract.document_type.json`

---

## Flex input contracts (9 tasks — Section 57)

> Flex tasks MUST NOT enter execution queue until contract complete.

### P5-FLEX-01 — Flex contract slot 01

- **Status:** done
- **Notes:** `taskTypeId=catalog.fake_listing`; `executable=true`
- **Depends on:** P5-CROSS-05
- **Objective:** Complete input contract for Flex task #1 (record `taskTypeId` when mapped from catalog).
- **Acceptance criteria:** JSON schema + validation + golden test; queue gate allows execution.
- **Evidence:** `plan/evidence/phase-05-p5-flex-01-catalog-fake-listing.json`; `dsl/catalog/task-types/catalog-fake-listing.yaml`; `src/backend/edgemint/results/flex_validators.py`

### P5-FLEX-02 — Flex contract slot 02

- **Status:** done
- **Notes:** `taskTypeId=llm.ai_tag_validation`
- **Depends on:** P5-CROSS-05
- **Objective:** Complete input contract for Flex task #2.
- **Acceptance criteria:** Same as P5-FLEX-01.
- **Evidence:** `plan/evidence/phase-05-p5-flex-02-llm-ai-tag-validation.json`

### P5-FLEX-03 — Flex contract slot 03

- **Status:** done
- **Notes:** `taskTypeId=llm.caption_validation`
- **Depends on:** P5-CROSS-05
- **Objective:** Complete input contract for Flex task #3.
- **Acceptance criteria:** Same as P5-FLEX-01.
- **Evidence:** `plan/evidence/phase-05-p5-flex-03-llm-caption-validation.json`

### P5-FLEX-04 — Flex contract slot 04

- **Status:** done
- **Notes:** `taskTypeId=dataset.label_verification`
- **Depends on:** P5-CROSS-05
- **Objective:** Complete input contract for Flex task #4.
- **Acceptance criteria:** Same as P5-FLEX-01.
- **Evidence:** `plan/evidence/phase-05-p5-flex-04-dataset-label-verification.json`

### P5-FLEX-05 — Flex contract slot 05

- **Status:** done
- **Notes:** `taskTypeId=dataset.duplicate_cleanup`
- **Depends on:** P5-CROSS-05
- **Objective:** Complete input contract for Flex task #5.
- **Acceptance criteria:** Same as P5-FLEX-01.
- **Evidence:** `plan/evidence/phase-05-p5-flex-05-dataset-duplicate-cleanup.json`

### P5-FLEX-06 — Flex contract slot 06

- **Status:** done
- **Notes:** `taskTypeId=dataset.low_quality_removal`
- **Depends on:** P5-CROSS-05
- **Objective:** Complete input contract for Flex task #6.
- **Acceptance criteria:** Same as P5-FLEX-01.
- **Evidence:** `plan/evidence/phase-05-p5-flex-06-dataset-low-quality-removal.json`

### P5-FLEX-07 — Flex contract slot 07

- **Status:** done
- **Notes:** `taskTypeId=ml.active_learning_prelabel`
- **Depends on:** P5-CROSS-05
- **Objective:** Complete input contract for Flex task #7.
- **Acceptance criteria:** Same as P5-FLEX-01.
- **Evidence:** `plan/evidence/phase-05-p5-flex-07-ml-active-learning-prelabel.json`

### P5-FLEX-08 — Flex contract slot 08

- **Status:** done
- **Notes:** `taskTypeId=ml.consensus_label_validation`
- **Depends on:** P5-CROSS-05
- **Objective:** Complete input contract for Flex task #8.
- **Acceptance criteria:** Same as P5-FLEX-01.
- **Evidence:** `plan/evidence/phase-05-p5-flex-08-ml-consensus-label-validation.json`

### P5-FLEX-09 — Flex contract slot 09

- **Status:** done
- **Notes:** `taskTypeId=ml.human_verification_quality`
- **Depends on:** P5-CROSS-05
- **Objective:** Complete input contract for Flex task #9.
- **Acceptance criteria:** Same as P5-FLEX-01.
- **Evidence:** `plan/evidence/phase-05-p5-flex-09-ml-human-verification-quality.json`

---

## Vision task closure (14 tasks — Section 58)

> Separate runtime, resource envelope, compatibility, concurrency, validation per vision category.

### P5-VIS-01 — Vision task slot 01

- **Status:** done
- **Notes:** `taskTypeId=image.classify`; `visionCategory=vlm`
- **Depends on:** P5-CROSS-04, P3-T12
- **Objective:** Close vision task #1 with distinct runtime profile (OCR/classify/detect/VLM/segment taxonomy).
- **Acceptance criteria:** Full closure pattern + vision category tagged.
- **Evidence:** `plan/evidence/phase-05-p5-vis-01-image-classify.json`; `dsl/catalog/task-types/image-classify.yaml`; `src/backend/edgemint/results/vision_validators.py`

### P5-VIS-02 — Vision task slot 02

- **Status:** done
- **Notes:** `taskTypeId=safety.nsfw_detection`; `visionCategory=safety`
- **Depends on:** P5-CROSS-04, P3-T12
- **Objective:** Close vision task #2.
- **Acceptance criteria:** Same as P5-VIS-01.
- **Evidence:** `plan/evidence/phase-05-p5-vis-02-safety-nsfw-detection.json`

### P5-VIS-03 — Vision task slot 03

- **Status:** done
- **Notes:** `taskTypeId=safety.violence_detection`; `visionCategory=safety`
- **Depends on:** P5-CROSS-04, P3-T12
- **Objective:** Close vision task #3.
- **Acceptance criteria:** Same as P5-VIS-01.
- **Evidence:** `plan/evidence/phase-05-p5-vis-03-safety-violence-detection.json`

### P5-VIS-04 — Vision task slot 04

- **Status:** done
- **Notes:** `taskTypeId=safety.weapon_detection`; `visionCategory=safety`
- **Depends on:** P5-CROSS-04, P3-T12
- **Objective:** Close vision task #4.
- **Acceptance criteria:** Same as P5-VIS-01.
- **Evidence:** `plan/evidence/phase-05-p5-vis-04-safety-weapon-detection.json`

### P5-VIS-05 — Vision task slot 05

- **Status:** done
- **Notes:** `taskTypeId=safety.unsafe_image`; `visionCategory=safety`
- **Depends on:** P5-CROSS-04, P3-T12
- **Objective:** Close vision task #5.
- **Acceptance criteria:** Same as P5-VIS-01.
- **Evidence:** `plan/evidence/phase-05-p5-vis-05-safety-unsafe-image.json`

### P5-VIS-06 — Vision task slot 06

- **Status:** done
- **Notes:** `taskTypeId=moderation.profile_image`; `visionCategory=safety`
- **Depends on:** P5-CROSS-04, P3-T12
- **Objective:** Close vision task #6.
- **Acceptance criteria:** Same as P5-VIS-01.
- **Evidence:** `plan/evidence/phase-05-p5-vis-06-moderation-profile-image.json`

### P5-VIS-07 — Vision task slot 07

- **Status:** done
- **Notes:** `taskTypeId=moderation.generated_image`; `visionCategory=safety`
- **Depends on:** P5-CROSS-04, P3-T12
- **Objective:** Close vision task #7.
- **Acceptance criteria:** Same as P5-VIS-01.
- **Evidence:** `plan/evidence/phase-05-p5-vis-07-moderation-generated-image.json`

### P5-VIS-08 — Vision task slot 08

- **Status:** done
- **Notes:** `taskTypeId=catalog.image_tagging`; `visionCategory=catalog`
- **Depends on:** P5-CROSS-04, P3-T12
- **Objective:** Close vision task #8.
- **Acceptance criteria:** Same as P5-VIS-01.
- **Evidence:** `plan/evidence/phase-05-p5-vis-08-catalog-image-tagging.json`

### P5-VIS-09 — Vision task slot 09

- **Status:** done
- **Notes:** `taskTypeId=catalog.product_classification`; `visionCategory=catalog`
- **Depends on:** P5-CROSS-04, P3-T12
- **Objective:** Close vision task #9.
- **Acceptance criteria:** Same as P5-VIS-01.
- **Evidence:** `plan/evidence/phase-05-p5-vis-09-catalog-product-classification.json`

### P5-VIS-10 — Vision task slot 10

- **Status:** done
- **Notes:** `taskTypeId=catalog.product_quality_score`; `visionCategory=catalog`
- **Depends on:** P5-CROSS-04, P3-T12
- **Objective:** Close vision task #10.
- **Acceptance criteria:** Same as P5-VIS-01.
- **Evidence:** `plan/evidence/phase-05-p5-vis-10-catalog-product-quality-score.json`

### P5-VIS-11 — Vision task slot 11

- **Status:** done
- **Notes:** `taskTypeId=catalog.brand_logo`; `visionCategory=catalog`
- **Depends on:** P5-CROSS-04, P3-T12
- **Objective:** Close vision task #11.
- **Acceptance criteria:** Same as P5-VIS-01.
- **Evidence:** `plan/evidence/phase-05-p5-vis-11-catalog-brand-logo.json`

### P5-VIS-12 — Vision task slot 12

- **Status:** done
- **Notes:** `taskTypeId=catalog.prohibited_product`; `visionCategory=catalog`
- **Depends on:** P5-CROSS-04, P3-T12
- **Objective:** Close vision task #12.
- **Acceptance criteria:** Same as P5-VIS-01.
- **Evidence:** `plan/evidence/phase-05-p5-vis-12-catalog-prohibited-product.json`

### P5-VIS-13 — Vision task slot 13

- **Status:** done
- **Notes:** `taskTypeId=llm.image_output_safety`; `visionCategory=safety`
- **Depends on:** P5-CROSS-04, P3-T12
- **Objective:** Close vision task #13.
- **Acceptance criteria:** Same as P5-VIS-01.
- **Evidence:** `plan/evidence/phase-05-p5-vis-13-llm-image-output-safety.json`

### P5-VIS-14 — Vision task slot 14

- **Status:** done
- **Notes:** `taskTypeId=image.remove_background`; `visionCategory=segmentation`
- **Depends on:** P5-CROSS-04, P3-T12
- **Objective:** Close vision task #14.
- **Acceptance criteria:** Same as P5-VIS-01.
- **Evidence:** `plan/evidence/phase-05-p5-vis-14-image-remove-background.json`

---

## Catalog gap resolution (8 tasks — Section 56)

### P5-GAP-01 — Resolve taxonomy gap slot 01

- **Status:** done
- **Notes:** `taskTypeId=document.ocr`; canonical OCR / `paddle_ocr` runtime class
- **Depends on:** P0-T06
- **Objective:** Identify and classify 1 of 8 unresolved catalog entries (48+8=56 reconciliation).
- **Acceptance criteria:** Task type ID assigned to Qwen/Flex/Vision/Other with evidence.
- **Evidence:** `plan/evidence/phase-05-p5-gap-01-document-ocr.json`; `dsl/catalog/task-types/document-ocr.yaml`

### P5-GAP-02 — Resolve taxonomy gap slot 02

- **Status:** done
- **Notes:** `taskTypeId=ocr.receipt`; OCR family alias → `ocr.extract_text.v1`
- **Depends on:** P0-T06
- **Objective:** Resolve gap entry #2.
- **Acceptance criteria:** Same as P5-GAP-01.
- **Evidence:** `plan/evidence/phase-05-p5-gap-02-ocr-receipt.json`

### P5-GAP-03 — Resolve taxonomy gap slot 03

- **Status:** done
- **Notes:** `taskTypeId=ocr.invoice`
- **Depends on:** P0-T06
- **Objective:** Resolve gap entry #3.
- **Acceptance criteria:** Same as P5-GAP-01.
- **Evidence:** `plan/evidence/phase-05-p5-gap-03-ocr-invoice.json`

### P5-GAP-04 — Resolve taxonomy gap slot 04

- **Status:** done
- **Notes:** `taskTypeId=ocr.simple_form`
- **Depends on:** P0-T06
- **Objective:** Resolve gap entry #4.
- **Acceptance criteria:** Same as P5-GAP-01.
- **Evidence:** `plan/evidence/phase-05-p5-gap-04-ocr-simple-form.json`

### P5-GAP-05 — Resolve taxonomy gap slot 05

- **Status:** done
- **Notes:** `taskTypeId=ocr.product_label`
- **Depends on:** P0-T06
- **Objective:** Resolve gap entry #5.
- **Acceptance criteria:** Same as P5-GAP-01.
- **Evidence:** `plan/evidence/phase-05-p5-gap-05-ocr-product-label.json`

### P5-GAP-06 — Resolve taxonomy gap slot 06

- **Status:** done
- **Notes:** `taskTypeIds=quality.document_image,quality.blurry_image`; `image_classifier` runtime
- **Depends on:** P0-T06
- **Objective:** Resolve gap entry #6.
- **Acceptance criteria:** Same as P5-GAP-01.
- **Evidence:** `plan/evidence/phase-05-p5-gap-06-quality-lightweight-vision.json`

### P5-GAP-07 — Resolve taxonomy gap slot 07

- **Status:** done
- **Notes:** `taskTypeId=catalog.duplicate_image`; `embedding_runtime` / dHash similarity
- **Depends on:** P0-T06
- **Objective:** Resolve gap entry #7.
- **Acceptance criteria:** Same as P5-GAP-01.
- **Evidence:** `plan/evidence/phase-05-p5-gap-07-catalog-duplicate-image.json`

### P5-GAP-08 — Catalog closure sign-off (56/56 classified)

- **Status:** done
- **Depends on:** P5-GAP-01 … P5-GAP-07, all P5-QWEN-*, P5-FLEX-*, P5-VIS-*
- **Objective:** Verify all 56 tasks individually classified and evidenced (Section 56).
- **Impacted paths:** `plan/audit-matrix.md`, `plan/closure-checklist.md`
- **Acceptance criteria:** Gap tracker shows 56/56; no DOC_ONLY closure claims.
- **Evidence:** `plan/evidence/phase-05-p5-gap-08-catalog-signoff.json`; `tools/validate_catalog_closure.py`; `test_gap_validators.py::test_all_fifty_six_executable_tasks_have_golden_and_dsl`
- **Rollback:** Reopen gap tasks.
