from __future__ import annotations

from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path
from typing import Literal

import yaml

from edgemint.dev.task_type_catalog import TaskTypeEntry, get_task_type, supported_task_types
from edgemint.golden.harness import list_fixture_task_types
from edgemint.tasks.errors import task_error

CatalogClosureMode = Literal["warn_only", "baseline", "strict"]


@dataclass(frozen=True, slots=True)
class CatalogClosureReport:
    task_type: str
    executable: bool
    metadata_complete: bool
    dsl_contract_complete: bool
    golden_fixture_present: bool
    queue_admissible: bool
    missing_fields: tuple[str, ...]

    @property
    def contract_complete(self) -> bool:
        return self.metadata_complete and self.dsl_contract_complete and self.golden_fixture_present


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[4]


@lru_cache(maxsize=1)
def _load_task_type_dsl_index() -> dict[str, dict[str, object]]:
    directory = _repo_root() / "dsl" / "catalog" / "task-types"
    index: dict[str, dict[str, object]] = {}
    if not directory.is_dir():
        return index
    for path in sorted(directory.glob("*.yaml")):
        document = yaml.safe_load(path.read_text(encoding="utf-8"))
        catalog_code = str(document["spec"]["code"])
        index[catalog_code] = document
    return index


def dsl_contract_complete(task_type: str) -> bool:
    document = _load_task_type_dsl_index().get(task_type)
    if document is None:
        return False
    metadata = document.get("metadata", {})
    spec = document.get("spec", {})
    if str(metadata.get("status")) != "active":
        return False
    output_schema = spec.get("outputSchema")
    return isinstance(output_schema, dict) and bool(output_schema)


def _missing_metadata_fields(entry: TaskTypeEntry) -> tuple[str, ...]:
    missing: list[str] = []
    if not entry.resource_envelope_ref:
        missing.append("resourceEnvelopeRef")
    if not entry.retry_class:
        missing.append("retryClass")
    if not entry.retry_policy_ref:
        missing.append("retryPolicyRef")
    if entry.checkpoint_strategy is None:
        missing.append("checkpointStrategy")
    if not entry.checkpoint_policy_ref:
        missing.append("checkpointPolicyRef")
    if entry.checkpoint_enabled is None:
        missing.append("checkpointEnabled")
    return tuple(missing)


def inspect_catalog_entry(entry: TaskTypeEntry) -> CatalogClosureReport:
    missing = _missing_metadata_fields(entry)
    metadata_complete = not missing
    dsl_complete = dsl_contract_complete(entry.value)
    golden_present = entry.value in set(list_fixture_task_types())
    if not entry.executable:
        queue_admissible = entry.retry_class == "no_retry"
    elif missing:
        queue_admissible = False
    else:
        queue_admissible = True
    return CatalogClosureReport(
        task_type=entry.value,
        executable=entry.executable,
        metadata_complete=metadata_complete,
        dsl_contract_complete=dsl_complete,
        golden_fixture_present=golden_present,
        queue_admissible=queue_admissible,
        missing_fields=missing,
    )


def validate_catalog_sync() -> list[CatalogClosureReport]:
    reports: list[CatalogClosureReport] = []
    for task_type in sorted(supported_task_types()):
        entry = get_task_type(task_type)
        if entry is not None:
            reports.append(inspect_catalog_entry(entry))
    return reports


def validate_queue_admission(
    *,
    catalog_code: str,
    mode: CatalogClosureMode = "baseline",
) -> TaskTypeEntry:
    entry = get_task_type(catalog_code)
    if entry is None:
        raise task_error("UNSUPPORTED_TASK_CONFIGURATION", detail=f"unknown taskType {catalog_code!r}")

    report = inspect_catalog_entry(entry)
    if mode == "warn_only":
        return entry

    if not entry.executable:
        raise task_error("TASK_TYPE_NOT_EXECUTABLE", detail=catalog_code)

    from edgemint.tasks.catalog_reconciliation import assert_flex_dispatch_permitted

    assert_flex_dispatch_permitted(catalog_code=catalog_code)

    if report.missing_fields:
        raise task_error(
            "UNSUPPORTED_TASK_CONFIGURATION",
            detail=f"missing catalog contract fields: {', '.join(report.missing_fields)}",
        )

    if mode == "strict" and not report.dsl_contract_complete:
        raise task_error(
            "UNSUPPORTED_TASK_CONFIGURATION",
            detail=f"taskType DSL contract incomplete for {catalog_code}",
        )
    return entry
