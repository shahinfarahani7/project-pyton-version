from __future__ import annotations

import pytest

from edgemint.routing.retry_classifier import RetryClass, classify_failure_code, requires_stronger_worker
from edgemint.routing.service import RouterService
from edgemint.workers.failure_codes import CLOSED_WORKER_FAILURE_CODES


_IMMEDIATE = {
    "RESOURCE_PRESSURE",
    "MODEL_UNAVAILABLE",
    "RUNTIME_INCOMPATIBLE",
    "THERMAL_BLOCK",
    "WORKER_DISCONNECTED",
    "LEASE_EXPIRED",
    "DELIVERY_TIMEOUT",
    "START_TIMEOUT",
}

_STRONGER = {
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

_NO_RETRY = {
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
    "LONG_FORM_INCOMPLETE",
}


@pytest.mark.parametrize("code", sorted(_IMMEDIATE))
def test_immediate_other_worker_codes(code: str) -> None:
    assert classify_failure_code(code) == RetryClass.IMMEDIATE_OTHER_WORKER


@pytest.mark.parametrize("code", sorted(_STRONGER))
def test_stronger_worker_codes(code: str) -> None:
    assert classify_failure_code(code) == RetryClass.STRONGER_WORKER
    assert requires_stronger_worker(code) is True


@pytest.mark.parametrize("code", sorted(_NO_RETRY))
def test_no_retry_codes(code: str) -> None:
    assert classify_failure_code(code) == RetryClass.NO_RETRY


def test_all_closed_codes_classified() -> None:
    classified = _IMMEDIATE | _STRONGER | _NO_RETRY
    unclassified = CLOSED_WORKER_FAILURE_CODES - classified - {
        "RUNTIME_CRASH",
        "OS_PROCESS_TERMINATED",
        "INPUT_RUNTIME_UNSUPPORTED",
    }
    for code in unclassified:
        assert classify_failure_code(code) == RetryClass.IMMEDIATE_OTHER_WORKER


def test_router_service_classify_retry_wrapper() -> None:
    router = RouterService()
    payload = router.classify_retry("RESULT_VALIDATION_FAILED")
    assert payload["retryClass"] == RetryClass.STRONGER_WORKER.value
    assert payload["requiresStrongerWorker"] is True
    assert payload["retryPermitted"] is True

    terminal = router.classify_retry("TASK_CANCELLED")
    assert terminal["retryClass"] == RetryClass.NO_RETRY.value
    assert terminal["retryPermitted"] is False
