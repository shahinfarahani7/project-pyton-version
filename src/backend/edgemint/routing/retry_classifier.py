from __future__ import annotations

from enum import Enum

from edgemint.workers.failure_codes import CLOSED_WORKER_FAILURE_CODES


class RetryClass(str, Enum):
    IMMEDIATE_OTHER_WORKER = "immediate_other_worker"
    STRONGER_WORKER = "stronger_worker"
    NO_RETRY = "no_retry"


_IMMEDIATE_OTHER_WORKER: frozenset[str] = frozenset(
    {
        "RESOURCE_PRESSURE",
        "MODEL_UNAVAILABLE",
        "RUNTIME_INCOMPATIBLE",
        "THERMAL_BLOCK",
        "WORKER_DISCONNECTED",
        "LEASE_EXPIRED",
        "DELIVERY_TIMEOUT",
        "START_TIMEOUT",
    }
)

_STRONGER_WORKER: frozenset[str] = frozenset(
    {
        "RUNTIME_OUT_OF_MEMORY",
        "INFERENCE_TIMEOUT",
        "MODEL_EXECUTION_FAILED",
        "RESULT_VALIDATION_FAILED",
        "OCR_EMPTY_RESULT",
        "VISION_LOW_CONFIDENCE",
        "INSUFFICIENT_MEMORY",
        "INSUFFICIENT_STORAGE",
        "CONTEXT_BUDGET_EXCEEDED",
        "RESULT_LOW_CONFIDENCE",
        "RESULT_EMPTY",
        "GOLDEN_VALIDATION_FAILED",
    }
)

_NO_RETRY: frozenset[str] = frozenset(
    {
        "INPUT_SCHEMA_INVALID",
        "PERMISSION_DENIED",
        "CONSENT_REVOKED",
        "POLICY_BLOCKED",
        "UNRECOVERABLE_FILE",
        "TASK_CANCELLED",
        "DEADLINE_EXPIRED",
        "CONSENT_MISMATCH",
        "RESULT_INVALID_JSON",
        "RESULT_SCHEMA_MISMATCH",
        "RESULT_SIGNATURE_INVALID",
        "NETWORK_POLICY_MISMATCH",
    }
)


def classify_failure_code(code: str) -> RetryClass:
    """Section 43 server-side retry taxonomy."""
    normalized = code.strip().upper()
    if normalized in _IMMEDIATE_OTHER_WORKER:
        return RetryClass.IMMEDIATE_OTHER_WORKER
    if normalized in _STRONGER_WORKER:
        return RetryClass.STRONGER_WORKER
    if normalized in _NO_RETRY:
        return RetryClass.NO_RETRY
    if normalized in CLOSED_WORKER_FAILURE_CODES:
        return RetryClass.IMMEDIATE_OTHER_WORKER
    raise ValueError(f"unknown failure code: {code}")


def requires_stronger_worker(code: str) -> bool:
    return classify_failure_code(code) == RetryClass.STRONGER_WORKER
