from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Any

import yaml

from edgemint.tasks.errors import task_error
from edgemint.tasks.lifecycle import task_type_to_catalog_code


@dataclass(frozen=True, slots=True)
class TaskTypeContract:
    code: str
    status: str
    allowed_content_types: frozenset[str]
    maximum_bytes: int


def load_task_type_contracts(root: Path | None = None) -> dict[str, TaskTypeContract]:
    base = root or Path(__file__).resolve().parents[4] / "dsl" / "catalog" / "task-types"
    contracts: dict[str, TaskTypeContract] = {}
    for path in sorted(base.glob("*.yaml")):
        document = yaml.safe_load(path.read_text(encoding="utf-8"))
        metadata = document["metadata"]
        spec = document["spec"]
        api_code = metadata["name"]
        limits = spec.get("inputLimits") or {}
        contracts[api_code] = TaskTypeContract(
            code=str(spec["code"]),
            status=str(metadata.get("status", "active")),
            allowed_content_types=frozenset(limits.get("allowedContentTypes") or []),
            maximum_bytes=int(limits.get("maximumBytes") or 52_428_800),
        )
    return contracts


def validate_task_submission(
    *,
    api_task_type: str,
    content_type: str,
    contracts: dict[str, TaskTypeContract] | None = None,
) -> TaskTypeContract:
    catalog = contracts or load_task_type_contracts()
    contract = catalog.get(api_task_type)
    if contract is None:
        raise task_error("UNSUPPORTED_TASK_CONFIGURATION", detail=f"unknown taskType {api_task_type!r}")
    if contract.status != "active":
        raise task_error("TASK_TYPE_NOT_ACTIVE", detail=contract.code)
    normalized = content_type.split(";", 1)[0].strip().lower()
    if contract.allowed_content_types and normalized not in contract.allowed_content_types:
        raise task_error(
            "INPUT_SCHEMA_INVALID",
            detail=f"contentType {content_type!r} not allowed for {api_task_type}",
        )
    if task_type_to_catalog_code(api_task_type) != contract.code:
        raise task_error("UNSUPPORTED_TASK_CONFIGURATION")
    return contract


def validate_configuration_parameters(task_type: str, parameters: dict[str, Any]) -> None:
    if task_type == "document-ocr" and "pageRange" not in parameters:
        raise task_error("INPUT_SCHEMA_INVALID", detail="parameters.pageRange is required for document-ocr")
