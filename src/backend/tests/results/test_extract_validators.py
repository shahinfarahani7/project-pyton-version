from __future__ import annotations

import json

from edgemint.golden.harness import run_golden_task
from edgemint.results.validator import extract_task_result_payload, validate_task_result

EXTRACT_TASK_TYPES = (
    "document.extract",
    "extract.amount",
    "extract.date",
    "extract.order_number",
    "extract.document_type",
)


def test_extract_worker_envelope_unwraps_nested_data() -> None:
    envelope = {
        "schemaVersion": "1",
        "taskId": "tsk_extract",
        "status": "SUCCEEDED",
        "output": {
            "rawText": "ACME Invoice. TOTAL 99.16 EUR.",
            "ocrLines": [],
            "data": {"vendor": "ACME", "total": 99.16, "currency": "EUR"},
        },
        "metrics": {"llmMs": 1000},
    }
    payload = extract_task_result_payload(envelope)
    assert payload["data"]["vendor"] == "ACME"
    assert payload["data"]["total"] == 99.16


def test_document_extract_invalid_total_rejected() -> None:
    inline = json.dumps(
        {
            "schemaVersion": "1",
            "taskId": "tsk_extract",
            "status": "SUCCEEDED",
            "output": {
                "rawText": "TOTAL 0 EUR",
                "ocrLines": [],
                "data": {"vendor": "ACME", "total": 0, "currency": "EUR"},
            },
            "metrics": {},
        }
    )
    outcome = validate_task_result(task_type="document.extract", inline_output=inline)
    assert outcome.valid is False


def test_all_extract_golden_fixtures_pass() -> None:
    for task_type in EXTRACT_TASK_TYPES:
        outcome = run_golden_task(task_type)
        assert outcome.passed is True, task_type
