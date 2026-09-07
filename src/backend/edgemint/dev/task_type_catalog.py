from __future__ import annotations

import json
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path
from typing import Any, Literal

InputMode = Literal["text", "image", "document", "flex"]

_TEXT_MODERATION_TYPES = frozenset(
    {
        "moderation.prompt_safety",
        "moderation.text",
        "moderation.profanity",
        "moderation.spam_comment",
    }
)
_SUMMARIZE_TYPES = frozenset({"text.summarize", "llm.summary_verification"})
_IMAGE_BLOB_FAMILIES = frozenset({"document.ocr", "document.extract", "image.classify"})


@dataclass(frozen=True, slots=True)
class TaskTypeEntry:
    value: str
    label_en: str
    label_fa: str
    input_mode: InputMode
    category_id: str
    category_label_en: str
    category_label_fa: str
    resource_envelope_ref: str | None = None
    retry_class: str | None = None
    retry_policy_ref: str | None = None
    executable: bool = True
    checkpoint_enabled: bool | None = None
    checkpoint_strategy: str | None = None
    checkpoint_policy_ref: str | None = None


def _catalog_path() -> Path:
    return Path(__file__).resolve().parents[3] / "shared" / "task-types" / "catalog.json"


def _read_catalog_document() -> dict[str, Any]:
    path = _catalog_path()
    if not path.is_file():
        raise FileNotFoundError(f"TASK_TYPE_CATALOG_NOT_FOUND:{path}")
    return json.loads(path.read_text(encoding="utf-8"))


@lru_cache(maxsize=1)
def _load_index() -> dict[str, TaskTypeEntry]:
    document = _read_catalog_document()
    index: dict[str, TaskTypeEntry] = {}
    for category in document["categories"]:
        category_id = str(category["id"])
        category_label_en = str(category["labelEn"])
        category_label_fa = str(category["labelFa"])
        for item in category["types"]:
            entry = TaskTypeEntry(
                value=str(item["value"]),
                label_en=str(item["labelEn"]),
                label_fa=str(item["labelFa"]),
                input_mode=str(item["inputMode"]),  # type: ignore[arg-type]
                category_id=category_id,
                category_label_en=category_label_en,
                category_label_fa=category_label_fa,
                resource_envelope_ref=str(item["resourceEnvelopeRef"])
                if item.get("resourceEnvelopeRef")
                else None,
                retry_class=str(item["retryClass"]) if item.get("retryClass") else None,
                retry_policy_ref=str(item["retryPolicyRef"]) if item.get("retryPolicyRef") else None,
                executable=bool(item.get("executable", True)),
                checkpoint_enabled=bool(item["checkpointEnabled"]) if "checkpointEnabled" in item else None,
                checkpoint_strategy=str(item["checkpointStrategy"])
                if item.get("checkpointStrategy")
                else None,
                checkpoint_policy_ref=str(item["checkpointPolicyRef"])
                if item.get("checkpointPolicyRef")
                else None,
            )
            index[entry.value] = entry
    return index


@lru_cache(maxsize=1)
def _load_categories_raw() -> list[dict[str, Any]]:
    document = _read_catalog_document()
    return list(document["categories"])


def get_task_type(task_type: str) -> TaskTypeEntry | None:
    return _load_index().get(task_type)


def supported_task_types() -> frozenset[str]:
    return frozenset(_load_index())


def pipeline_family(task_type: str) -> str:
    if task_type.startswith("ocr.") or task_type == "document.ocr":
        return "document.ocr"
    if task_type.startswith("extract.") or task_type == "document.extract":
        return "document.extract"
    if task_type in _SUMMARIZE_TYPES:
        return "text.summarize"
    if (
        task_type in _TEXT_MODERATION_TYPES
        or task_type.startswith("nlp.")
        or task_type.startswith("ml.")
        or task_type.startswith("dataset.")
        or task_type.startswith("review.")
        or task_type == "text.classify"
        or task_type.startswith("llm.")
    ):
        if task_type == "llm.summary_verification":
            return "text.summarize"
        if task_type == "llm.image_output_safety":
            return "image.classify"
        return "text.classify"
    if (
        task_type.startswith("safety.")
        or task_type.startswith("quality.")
        or task_type.startswith("catalog.")
        or task_type == "image.classify"
        or task_type.startswith("moderation.")
    ):
        return "image.classify"
    return task_type


def image_blob_family(task_type: str) -> bool:
    return pipeline_family(task_type) in _IMAGE_BLOB_FAMILIES


def accept_for(task_type: str) -> str:
    entry = get_task_type(task_type)
    if entry is None:
        return "*/*"
    if entry.input_mode == "image":
        return "image/*"
    if entry.input_mode == "document":
        return ".txt,.md,.pdf,image/*"
    if entry.input_mode == "text":
        return ".txt,.md,.csv,.json"
    return ".txt,.md,.pdf,image/*,.csv,.json"


def label_for(task_type: str, *, locale: str = "en") -> str:
    entry = get_task_type(task_type)
    if entry is None:
        return task_type
    return entry.label_fa if locale == "fa" else entry.label_en


def task_type_meta(task_type: str) -> dict[str, Any]:
    entry = get_task_type(task_type)
    if entry is None:
        return {
            "value": task_type,
            "labelEn": task_type,
            "labelFa": task_type,
            "categoryId": None,
            "categoryLabelEn": None,
            "categoryLabelFa": None,
            "inputMode": None,
            "pipelineFamily": pipeline_family(task_type),
            "accept": "*/*",
            "supported": False,
            "resourceEnvelopeRef": None,
        }
    return {
        "value": entry.value,
        "labelEn": entry.label_en,
        "labelFa": entry.label_fa,
        "categoryId": entry.category_id,
        "categoryLabelEn": entry.category_label_en,
        "categoryLabelFa": entry.category_label_fa,
        "inputMode": entry.input_mode,
        "pipelineFamily": pipeline_family(entry.value),
        "accept": accept_for(entry.value),
        "supported": True,
        "resourceEnvelopeRef": entry.resource_envelope_ref,
    }


def enrich_task_list(payload: dict[str, Any], *, locale: str = "en") -> dict[str, Any]:
    items = [enrich_task_row(item, locale=locale) for item in payload.get("items", [])]
    return {**payload, "items": items}


def enrich_task_row(row: dict[str, Any], *, locale: str = "en") -> dict[str, Any]:
    task_type = str(row.get("taskType", ""))
    meta = task_type_meta(task_type)
    enriched = dict(row)
    enriched["taskTypeMeta"] = meta
    enriched["taskTypeLabel"] = label_for(task_type, locale=locale)

    task_id = str(row.get("id", ""))
    if task_id and (not enriched.get("inputPreview") or not enriched.get("inputLabel")):
        from edgemint.dev import worker_task_inputs

        manifest = worker_task_inputs.input_manifest(task_id)
        if manifest:
            if not enriched.get("inputLabel"):
                enriched["inputLabel"] = manifest.get("inputLabel") or manifest.get("documentTitle")
            if not enriched.get("inputPreview"):
                preview = manifest.get("inputText") or manifest.get("prompt")
                if preview:
                    enriched["inputPreview"] = str(preview)[:2000]
    return enriched


def _normalize_query(query: str | None) -> str:
    return (query or "").strip().casefold()


def _matches(entry: TaskTypeEntry, query: str) -> bool:
    if not query:
        return True
    haystack = " ".join(
        [
            entry.value,
            entry.label_en,
            entry.label_fa,
            entry.category_id,
            entry.category_label_en,
            entry.category_label_fa,
        ]
    ).casefold()
    return query in haystack


def list_catalog(*, query: str | None = None, locale: str = "en") -> dict[str, Any]:
    normalized_query = _normalize_query(query)
    categories: list[dict[str, Any]] = []
    flat_items: list[dict[str, Any]] = []

    for category in _load_categories_raw():
        category_types: list[dict[str, Any]] = []
        for item in category["types"]:
            entry = get_task_type(str(item["value"]))
            if entry is None or not _matches(entry, normalized_query):
                continue
            type_payload = {
                "value": entry.value,
                "label": label_for(entry.value, locale=locale),
                "labelEn": entry.label_en,
                "labelFa": entry.label_fa,
                "inputMode": entry.input_mode,
                "accept": accept_for(entry.value),
                "pipelineFamily": pipeline_family(entry.value),
                "resourceEnvelopeRef": entry.resource_envelope_ref,
            }
            category_types.append(type_payload)
            flat_items.append(
                {
                    **type_payload,
                    "categoryId": entry.category_id,
                    "categoryLabel": entry.category_label_fa if locale == "fa" else entry.category_label_en,
                    "categoryLabelEn": entry.category_label_en,
                    "categoryLabelFa": entry.category_label_fa,
                }
            )
        if category_types:
            categories.append(
                {
                    "id": category["id"],
                    "label": category["labelFa"] if locale == "fa" else category["labelEn"],
                    "labelEn": category["labelEn"],
                    "labelFa": category["labelFa"],
                    "types": category_types,
                }
            )

    return {
        "locale": "fa" if locale == "fa" else "en",
        "query": query or "",
        "total": len(flat_items),
        "categories": categories,
        "items": flat_items,
    }


def _is_image_mime(file_mime: str | None) -> bool:
    return bool(file_mime and file_mime.startswith("image/"))


def validate_task_submission(
    *,
    task_type: str,
    input_text: str | None = None,
    instructions: str | None = None,
    file_name: str | None = None,
    file_mime: str | None = None,
    file_bytes: bytes | None = None,
) -> TaskTypeEntry:
    normalized_type = task_type.strip()
    if not normalized_type:
        raise ValueError("TASK_TYPE_REQUIRED")

    entry = get_task_type(normalized_type)
    if entry is None:
        raise ValueError("UNSUPPORTED_TASK_TYPE")

    has_text = bool(input_text and input_text.strip()) or bool(instructions and instructions.strip())
    has_file = bool(file_bytes)

    if not has_text and not has_file:
        return entry

    if entry.input_mode == "text":
        if not has_text and not has_file:
            raise ValueError("INPUT_TEXT_REQUIRED")
    elif entry.input_mode == "image":
        if not has_file:
            raise ValueError("INPUT_IMAGE_REQUIRED")
        if not _is_image_mime(file_mime):
            raise ValueError("INPUT_IMAGE_REQUIRED")

    if entry.input_mode == "image" and has_file and not _is_image_mime(file_mime):
        raise ValueError("INPUT_IMAGE_REQUIRED")

    return entry
