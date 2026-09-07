from __future__ import annotations

import json
import re
import subprocess
from dataclasses import dataclass
from enum import StrEnum
from functools import lru_cache
from pathlib import Path
from typing import Any

from edgemint.dev.task_type_catalog import TaskTypeEntry, get_task_type, supported_task_types
from edgemint.tasks.errors import task_error

HISTORICAL_EXPECTED_UNIQUE_TOTAL = 56
HISTORICAL_AXIS_COUNTS = {"qwenHeuristic": 25, "flex": 9, "visionHeuristic": 14}


class FlexDispatchDecision(StrEnum):
    NOT_FLEX = "not_flex"
    DISPATCH_PERMITTED = "dispatch_permitted"
    BLOCKED_NON_EXECUTABLE = "blocked_non_executable"
    BLOCKED_INCOMPLETE_CONTRACT = "blocked_incomplete_contract"
    BLOCKED_NO_HANDLER = "blocked_no_handler"


@dataclass(frozen=True, slots=True)
class CatalogReconciliationSnapshot:
    commit_sha: str
    unique_task_count: int
    duplicate_catalog_ids: tuple[str, ...]
    duplicate_dsl_codes: tuple[str, ...]
    unmapped_catalog_ids: tuple[str, ...]
    orphan_dsl_codes: tuple[str, ...]
    historical_expected_total: int
    reconciled_with_historical: bool
    reconciliation_delta: int
    flex_task_ids: tuple[str, ...]
    flex_dispatchable_ids: tuple[str, ...]
    flex_blocked_ids: tuple[str, ...]
    taxonomy_axes: dict[str, int]
    taxonomy_axis_overlap_note: str


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[4]


def _git_head() -> str:
    try:
        return (
            subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=_repo_root(), text=True)
            .strip()
        )
    except Exception:
        return "unknown"


@lru_cache(maxsize=1)
def _flex_handler_types() -> frozenset[str]:
    catalog_path = _repo_root() / "src/apps/worker/lib/contracts/task_contract_catalog.dart"
    text = catalog_path.read_text(encoding="utf-8")
    match = re.search(r"static const flexTypes = <String>\{([^}]+)\}", text, re.DOTALL)
    if match is None:
        return frozenset()
    return frozenset(re.findall(r"'([^']+)'", match.group(1)))


def flex_input_contract_complete(task_type: str) -> bool:
    from edgemint.tasks.catalog_closure import _load_task_type_dsl_index

    document = _load_task_type_dsl_index().get(task_type)
    if document is None:
        return False
    input_schema = document.get("spec", {}).get("inputSchema", {})
    if not isinstance(input_schema, dict):
        return False
    properties = input_schema.get("properties", {})
    required = input_schema.get("required", [])
    return "flexInput" in properties or "flexInput" in required


def evaluate_flex_dispatch_gate(
    entry: TaskTypeEntry,
    report: object | None = None,
) -> FlexDispatchDecision:
    if entry.input_mode != "flex":
        return FlexDispatchDecision.NOT_FLEX

    from edgemint.tasks.catalog_closure import inspect_catalog_entry

    active_report = report or inspect_catalog_entry(entry)
    if not entry.executable:
        return FlexDispatchDecision.BLOCKED_NON_EXECUTABLE

    if not flex_input_contract_complete(entry.value) or not active_report.dsl_contract_complete:
        return FlexDispatchDecision.BLOCKED_INCOMPLETE_CONTRACT

    if entry.value not in _flex_handler_types():
        return FlexDispatchDecision.BLOCKED_NO_HANDLER

    return FlexDispatchDecision.DISPATCH_PERMITTED


def assert_flex_dispatch_permitted(*, catalog_code: str) -> None:
    entry = get_task_type(catalog_code)
    if entry is None:
        raise task_error("UNSUPPORTED_TASK_CONFIGURATION", detail=f"unknown taskType {catalog_code!r}")
    decision = evaluate_flex_dispatch_gate(entry)
    if decision == FlexDispatchDecision.DISPATCH_PERMITTED:
        return
    if decision == FlexDispatchDecision.NOT_FLEX:
        return
    if decision == FlexDispatchDecision.BLOCKED_NON_EXECUTABLE:
        raise task_error("TASK_TYPE_NOT_EXECUTABLE", detail=catalog_code)
    raise task_error(
        "UNSUPPORTED_TASK_CONFIGURATION",
        detail=f"flex dispatch gate blocked ({decision.value}) for {catalog_code}",
    )


def list_flex_dispatch_violations() -> list[str]:
    violations: list[str] = []
    for task_type in sorted(supported_task_types()):
        entry = get_task_type(task_type)
        if entry is None or entry.input_mode != "flex":
            continue
        decision = evaluate_flex_dispatch_gate(entry)
        if entry.executable and decision != FlexDispatchDecision.DISPATCH_PERMITTED:
            violations.append(f"{task_type}:{decision.value}")
        if not entry.executable and decision == FlexDispatchDecision.DISPATCH_PERMITTED:
            violations.append(f"{task_type}:executable_false_but_contract_complete")
    handler_types = _flex_handler_types()
    for task_type in sorted(handler_types):
        entry = get_task_type(task_type)
        if entry is None:
            violations.append(f"{task_type}:handler_without_catalog_entry")
    return violations


def _catalog_task_ids() -> list[str]:
    catalog = json.loads(
        (_repo_root() / "src/shared/task-types/catalog.json").read_text(encoding="utf-8")
    )
    return [str(item["value"]) for cat in catalog["categories"] for item in cat["types"]]


def _dsl_task_codes() -> list[str]:
    from edgemint.tasks.catalog_closure import _load_task_type_dsl_index

    return sorted(_load_task_type_dsl_index())


def _duplicate_values(values: list[str]) -> tuple[str, ...]:
    seen: set[str] = set()
    duplicates: set[str] = set()
    for value in values:
        if value in seen:
            duplicates.add(value)
        seen.add(value)
    return tuple(sorted(duplicates))


def _taxonomy_axes(task_ids: frozenset[str]) -> dict[str, int]:
    flex = {task_id for task_id in task_ids if get_task_type(task_id) and get_task_type(task_id).input_mode == "flex"}  # type: ignore[union-attr]
    vision = {
        task_id
        for task_id in task_ids
        if any(token in task_id for token in ("image.", "vision.", "safety.", "quality.", "catalog.", "moderation."))
        or (get_task_type(task_id) and get_task_type(task_id).input_mode == "image")  # type: ignore[union-attr]
    }
    qwen = {
        task_id
        for task_id in task_ids
        if task_id.startswith(("text.", "document.", "extract.", "llm.", "nlp.", "ocr.", "ml.", "dataset.", "review."))
        or task_id in {"document.summarize", "text.summarize"}
    }
    return {
        "uniqueTotal": len(task_ids),
        "flexAxis": len(flex),
        "visionAxis": len(vision),
        "qwenAxis": len(qwen),
    }


def build_catalog_reconciliation_snapshot() -> CatalogReconciliationSnapshot:
    catalog_ids = _catalog_task_ids()
    dsl_codes = _dsl_task_codes()
    catalog_set = set(catalog_ids)
    dsl_set = set(dsl_codes)
    unique_count = len(catalog_set)
    flex_ids = tuple(
        sorted(task_type for task_type in catalog_set if get_task_type(task_type) and get_task_type(task_type).input_mode == "flex")  # type: ignore[union-attr]
    )
    dispatchable: list[str] = []
    blocked: list[str] = []
    for task_type in flex_ids:
        entry = get_task_type(task_type)
        if entry is None:
            blocked.append(task_type)
            continue
        if evaluate_flex_dispatch_gate(entry) == FlexDispatchDecision.DISPATCH_PERMITTED:
            dispatchable.append(task_type)
        else:
            blocked.append(task_type)

    axes = _taxonomy_axes(frozenset(catalog_set))
    historical_sum = sum(HISTORICAL_AXIS_COUNTS.values())
    return CatalogReconciliationSnapshot(
        commit_sha=_git_head(),
        unique_task_count=unique_count,
        duplicate_catalog_ids=_duplicate_values(catalog_ids),
        duplicate_dsl_codes=_duplicate_values(dsl_codes),
        unmapped_catalog_ids=tuple(sorted(catalog_set - dsl_set)),
        orphan_dsl_codes=tuple(sorted(dsl_set - catalog_set)),
        historical_expected_total=HISTORICAL_EXPECTED_UNIQUE_TOTAL,
        reconciled_with_historical=unique_count == HISTORICAL_EXPECTED_UNIQUE_TOTAL,
        reconciliation_delta=unique_count - HISTORICAL_EXPECTED_UNIQUE_TOTAL,
        flex_task_ids=flex_ids,
        flex_dispatchable_ids=tuple(dispatchable),
        flex_blocked_ids=tuple(blocked),
        taxonomy_axes=axes,
        taxonomy_axis_overlap_note=(
            f"Historical axis sum {historical_sum} exceeds unique total because "
            "Qwen/Vision/Flex axes overlap (v2 §56)."
        ),
    )


def snapshot_to_dict(snapshot: CatalogReconciliationSnapshot) -> dict[str, Any]:
    return {
        "commitSha": snapshot.commit_sha,
        "uniqueTaskCount": snapshot.unique_task_count,
        "duplicateCatalogIds": list(snapshot.duplicate_catalog_ids),
        "duplicateDslCodes": list(snapshot.duplicate_dsl_codes),
        "unmappedCatalogIds": list(snapshot.unmapped_catalog_ids),
        "orphanDslCodes": list(snapshot.orphan_dsl_codes),
        "historicalExpectedTotal": snapshot.historical_expected_total,
        "reconciledWithHistorical": snapshot.reconciled_with_historical,
        "reconciliationDelta": snapshot.reconciliation_delta,
        "flexTaskIds": list(snapshot.flex_task_ids),
        "flexDispatchableIds": list(snapshot.flex_dispatchable_ids),
        "flexBlockedIds": list(snapshot.flex_blocked_ids),
        "taxonomyAxes": snapshot.taxonomy_axes,
        "taxonomyAxisOverlapNote": snapshot.taxonomy_axis_overlap_note,
    }
