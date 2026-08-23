# EdgeMint 56-task infrastructure and real-test checkpoint

Date: 2026-08-22

## Outcome

The catalog and control-plane infrastructure cover all 56 task types. This is not the same as 56 real model executions. The honest execution status is:

| Status | Count | Scope |
|---|---:|---|
| Real algorithm/model evidence | 8 | 5 PaddleOCR task types from the prior real-device evidence; 3 lightweight-vision task types implemented and runtime-tested here |
| Qwen contract-ready, real runtime blocked | 25 | 20 text tasks plus 5 document/extraction tasks |
| Flexible-input contract partial | 9 | Requires task-specific paired/reference input semantics before production advertisement |
| Visual-model/runtime blocked | 14 | General image safety/catalog/classification and background removal need a real VLM or segmentation model |
| Total | 56 | Catalog unique count verified |

## Implemented in this checkpoint

- Added real lightweight image metrics for `quality.blurry_image`, `quality.document_image`, and `catalog.duplicate_image`.
- Added the two-image manifest/input contract (`compareInputContentUrl`) and fail-closed validation for duplicate detection.
- Removed OCR and Qwen requirements from the three lightweight handlers.
- Added durable Outbox fan-out to targeted WebSocket subscriptions.
- Added retry/replay of expired leased and unacknowledged sent deliveries while preserving subscription sequence.
- Added worker-principal targeting so an `assignment.leased` event cannot fan out to another worker.
- Added production completion with lease/fence verification, payload digest verification, lease-scoped result MAC, transactional result persistence, lifecycle updates, Outbox event, and lease-credential destruction.
- Aligned the Worker completion body and OpenAPI `Completion` schema with `outputInline`.
- Added PostgreSQL 18 RDS source with Multi-AZ, encryption, IAM database authentication, backups, private networking, deletion protection, and observability controls.
- Pinned the canonical Qwen3-0.6B LiteRT-LM artifact SHA-256 to `555579ff2f4fd13379abe69c1c3ab5200f7338bc92471557f1d6614a6e5ab0b4`.
- Made frontend container base images fail closed through digest-pinned build arguments.

## Executed evidence

### Lightweight vision runtime

Decoded the project Android PNG and executed the same Laplacian-variance and dHash-64 math used by the Worker implementation:

- sharp Laplacian variance: `2542.8481440443215`
- Gaussian-blurred variance: `1.8262752825714963`
- resized duplicate Hamming distance: `0`
- deliberately different image Hamming distance: `59`
- result: PASS (4/4)

This proves the image algorithms on decoded pixels. Flutter/Android integration execution is still unavailable in this environment.

### Full task-catalog protocol load

- workers: 20
- task types: 56
- assignment flows: 1,120 / 1,120
- AES-256-GCM device-bound lease bootstrap: PASS for every flow
- lease-token result MAC: PASS for every flow
- stale-fence rejection after simulated reassignment: 1,120 / 1,120
- failures: 0

This is control-plane cryptography/fencing load evidence; it does not claim 1,120 model inferences.

### Source and contract gates

- production completion source contract: PASS (9/9)
- WebSocket replay source contract: PASS (8/8)
- production auto-assignment source contract: PASS (11/11)
- task catalog infrastructure: PASS (8/8; 56 unique types)
- PostgreSQL SQL validation: PASS (15 migrations, 75 tables, 36 RLS tables)
- OpenAPI/AsyncAPI contracts: PASS (141 operations, 186 events)
- WebSocket architecture: PASS (WSS, PostgreSQL 18, 186 events)
- dependency lock policy: PASS
- Python compileall: PASS

## Explicit blockers (not converted to fake passes)

1. Live PostgreSQL E2E is BLOCKED: SQLAlchemy and psycopg are absent, `EDGEMINT_DATABASE_URL` and `EDGEMINT_LEASE_CREDENTIAL_ENCRYPTION_KEY` are unset, and no PostgreSQL service is available.
2. Real Qwen inference is BLOCKED: `Qwen3-0.6B.litertlm` and a LiteRT-LM runtime are absent. The probe exits with code 2 and reports both blockers.
3. Flutter analysis/device tests are BLOCKED: Flutter/Dart are not installed in this runtime. The new `image` dependency and transitive lock entries are pinned from the configured package mirror.
4. Full AWS/EKS/Helm production source remains BLOCKED: the supplied project package has no 21-service Helm deployment and lacks the broader EKS/WAF/backup/CloudTrail resources required by `validate_infrastructure_source.py`. The PostgreSQL/WebSocket-specific production source is present and passes its focused validator.
5. Fourteen image task types require real visual models; nine flexible-input types require task-specific paired/reference contracts. They must not be advertised as real-executable yet.

## Reproduction commands

```bash
python tools/run_lightweight_vision_real_test.py
python tools/run_56_task_protocol_load.py
python tools/verify_task_catalog_infrastructure.py
python tools/verify_websocket_replay_source.py
python tools/verify_production_completion_source.py
python tools/verify_production_auto_assignment_source.py
python tools/run_production_auto_assignment_e2e.py
python tools/run_qwen_real_inference.py
python tools/validate_sql.py
python tools/validate_contracts.py
python tools/validate_websocket_architecture.py
python tools/validate_dependency_locks.py
```
