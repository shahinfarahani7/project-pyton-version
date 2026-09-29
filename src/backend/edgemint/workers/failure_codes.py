from __future__ import annotations

from edgemint.workers.errors import worker_error

# Architecture Section 41 closed worker failure codes plus Section 43 orchestration codes.
CLOSED_WORKER_FAILURE_CODES: frozenset[str] = frozenset(
    {
        # Before execution (Section 41)
        "MODEL_UNAVAILABLE",
        "INSUFFICIENT_MEMORY",
        "INSUFFICIENT_STORAGE",
        "RUNTIME_INCOMPATIBLE",
        "THERMAL_BLOCK",
        "NETWORK_POLICY_MISMATCH",
        "DELIVERY_TIMEOUT",
        "START_TIMEOUT",
        "CONSENT_MISMATCH",
        # During execution (Section 41)
        "RUNTIME_OUT_OF_MEMORY",
        "RUNTIME_CRASH",
        "INFERENCE_TIMEOUT",
        "MODEL_EXECUTION_FAILED",
        "OS_PROCESS_TERMINATED",
        "INPUT_RUNTIME_UNSUPPORTED",
        "INPUT_FETCH_TIMEOUT",
        "INPUT_UNAVAILABLE",
        "CONTEXT_BUDGET_EXCEEDED",
        # After execution (Section 41)
        "RESULT_INVALID_JSON",
        "RESULT_SCHEMA_MISMATCH",
        "RESULT_EMPTY",
        "RESULT_LOW_CONFIDENCE",
        "RESULT_SIGNATURE_INVALID",
        "GOLDEN_VALIDATION_FAILED",
        # Orchestration / retry taxonomy (Section 43)
        "RESOURCE_PRESSURE",
        "WORKER_DISCONNECTED",
        "LEASE_EXPIRED",
        "RESULT_VALIDATION_FAILED",
        "OCR_EMPTY_RESULT",
        "VISION_LOW_CONFIDENCE",
        "INPUT_SCHEMA_INVALID",
        "PERMISSION_DENIED",
        "CONSENT_REVOKED",
        "POLICY_BLOCKED",
        "UNRECOVERABLE_FILE",
        "TASK_CANCELLED",
        "DEADLINE_EXPIRED",
    }
)

_RETRYABLE_CODES: frozenset[str] = frozenset(
    {
        "RESOURCE_PRESSURE",
        "MODEL_UNAVAILABLE",
        "RUNTIME_INCOMPATIBLE",
        "THERMAL_BLOCK",
        "WORKER_DISCONNECTED",
        "LEASE_EXPIRED",
        "DELIVERY_TIMEOUT",
        "START_TIMEOUT",
        "INPUT_FETCH_TIMEOUT",
        "INPUT_UNAVAILABLE",
        "INSUFFICIENT_MEMORY",
        "INSUFFICIENT_STORAGE",
        "RUNTIME_OUT_OF_MEMORY",
        "INFERENCE_TIMEOUT",
        "MODEL_EXECUTION_FAILED",
        "RUNTIME_CRASH",
        "OS_PROCESS_TERMINATED",
        "CONTEXT_BUDGET_EXCEEDED",
        "RESULT_VALIDATION_FAILED",
        "OCR_EMPTY_RESULT",
        "VISION_LOW_CONFIDENCE",
        "RESULT_LOW_CONFIDENCE",
        "RESULT_EMPTY",
    }
)


def default_retryable_for_code(code: str) -> bool:
    return code in _RETRYABLE_CODES


def validate_worker_failure_submission(*, error_code: str, retryable: bool) -> None:
    if error_code not in CLOSED_WORKER_FAILURE_CODES:
        raise worker_error(
            "INPUT_SCHEMA_INVALID",
            detail=f"errorCode must be a closed worker failure code, got {error_code!r}",
        )
    expected = default_retryable_for_code(error_code)
    if retryable != expected:
        raise worker_error(
            "INPUT_SCHEMA_INVALID",
            detail=(
                f"retryable={retryable} does not match canonical classification "
                f"for {error_code} (expected {expected})"
            ),
        )
