from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "src" / "backend"))

from edgemint.tasks.errors import TaskServiceError  # noqa: E402
from edgemint.tasks.lifecycle import TaskLifecycle  # noqa: E402
from edgemint.tasks.validation import (  # noqa: E402
    load_task_type_contracts,
    validate_configuration_parameters,
    validate_task_submission,
)


def contract_checks() -> list[str]:
    errors: list[str] = []
    admission = (ROOT / "src/backend/edgemint/tasks/admission.py").read_text(encoding="utf-8")
    service = (ROOT / "src/backend/edgemint/services/task_intake.py").read_text(encoding="utf-8")
    settings = (ROOT / "src/backend/edgemint/building_blocks/settings.py").read_text(encoding="utf-8")

    for token in [
        "create_task",
        "create_revision",
        "cancel_task",
        "reserve_credit",
        "enqueue_outbox_event",
        "begin_idempotent_command",
    ]:
        if token not in admission:
            errors.append(f"admission missing:{token}")
    for route in [
        '"/tasks"',
        '"/tasks/{task_id}:cancel"',
        '"/tasks/{task_id}/revisions"',
    ]:
        if route not in service:
            errors.append(f"task-intake missing route {route}")
    if "task_admission_max_drafts" not in settings:
        errors.append("settings missing task admission limit")
    lifecycle = TaskLifecycle.load()
    if not lifecycle.can_transition("draft", "submitted"):
        errors.append("task lifecycle missing draft->submitted")
    return errors


def semantic_checks() -> list[str]:
    errors: list[str] = []
    contracts = load_task_type_contracts()
    try:
        validate_task_submission(
            api_task_type="document-ocr",
            content_type="application/pdf",
            contracts=contracts,
        )
    except TaskServiceError as exc:
        errors.append(f"valid ocr submission rejected: {exc.code}")
    try:
        validate_task_submission(
            api_task_type="document-ocr",
            content_type="application/x-msdownload",
            contracts=contracts,
        )
    except TaskServiceError as exc:
        if exc.code != "INPUT_SCHEMA_INVALID":
            errors.append("unexpected error for invalid content type")
    else:
        errors.append("invalid content type accepted")
    try:
        validate_configuration_parameters("document-ocr", {})
    except TaskServiceError as exc:
        if exc.code != "INPUT_SCHEMA_INVALID":
            errors.append("unexpected error for missing pageRange")
    else:
        errors.append("missing pageRange accepted")
    return errors


def main() -> int:
    errors = contract_checks() + semantic_checks()
    report = {"status": "passed" if not errors else "failed", "errors": errors}
    print(json.dumps(report, indent=2))
    return 0 if not errors else 1


if __name__ == "__main__":
    raise SystemExit(main())
