# RB-022 Adaptive Concurrency Certification

## Purpose

Document how worker devices earn and lose OCR+LLM concurrent execution certification (Architecture Sections 30, 35).

## Certification criteria (server)

Stored in `worker_calibration_profiles.metrics_json.concurrencyCertified`:

- `runtimeStabilityScoreMilli >= 900`
- `thermalDeltaBps <= 600`
- `llmDecodeTokensPerSec >= 50`

Sources:

- Benchmark upsert (`WorkerCalibrationService.upsert_from_benchmark`)
- Execution cost feedback loop (`apply_execution_cost_feedback_to_calibration`)

## Scheduler effects when certified

- Exclusive group `ocr_inference` limit increases from 1 → 2
- Cross-group rule `llm_inference` + `ocr_inference` concurrent when `certificationRequired=true`
- Runtime compatibility allows `mediapipe_llm` + `paddle_ocr` co-run

## Revocation

Certification is recomputed on every feedback/benchmark update. Thermal regression or instability removes the flag automatically.

## Ops visibility

Query:

```sql
SELECT worker_device_id, profile_version, metrics_json->>'concurrencyCertified'
FROM public.worker_calibration_profiles;
```

## Worker runtime

`RuntimeExclusiveGroupEnforcer(llmOcrConcurrentCertified: true)` must mirror server flag from calibration profile heartbeat/session payload.
