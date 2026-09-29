from __future__ import annotations

import base64
import json
from typing import Any

from fastapi.responses import Response

from edgemint.dev.dev_public_urls import dev_api_public_base
from edgemint.dev.task_type_catalog import image_blob_family, pipeline_family

_OCR_DOCUMENT = """INVOICE #INV-2026-0847
EdgeMint Demo Supplies Ltd.
123 Cloud Street, Helsinki
Date: 2026-08-03

Bill To: Shakhsi Dev Workspace

Item                    Qty    Amount (EUR)
USB-C Hub               2      49.98
Wireless Mouse          1      29.99
-----------------------------------------
Subtotal                       79.97
VAT (24%)                      19.19
TOTAL                          99.16

Payment terms: Net 30 days
Reference: PO-EM-2026-441
"""

_SUMMARIZE_DOCUMENT = """EdgeMint workers run assigned AI tasks on-device while the
customer portal tracks lifecycle status. Tasks move from queued to running to
completed after the worker uploads OCR or summarization output.
"""

_CLASSIFY_PROMPT = """Image metadata: warehouse shelf photo, 12 SKU labels visible,
lighting: indoor fluorescent, resolution: 1920x1080.
Classify the dominant product category in one short label.
"""

_TEXT_CLASSIFY_SAMPLE = """Your EdgeMint verification code is 847291. Do not share this code."""

# Minimal valid 1x1 PNG (white pixel) for dev OCR image tasks.
_SAMPLE_PNG_BYTES = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
)

_TASK_INPUTS: dict[str, dict[str, Any]] = {}
_INPUT_BLOBS: dict[str, dict[str, Any]] = {}
_RESULT_BLOBS: dict[str, dict[str, Any]] = {}
_MAX_TEXT_CHARS = 32_000
_MAX_FILE_BYTES = 2 * 1024 * 1024

_FLEX_SAMPLES: dict[str, dict[str, Any]] = {
    "catalog.fake_listing": {"listing": {"title": "New phone - unusually low price", "description": "Prepay by crypto", "price": 99, "currency": "EUR", "sellerSignals": {"accountAgeDays": 1, "completedSales": 0}}},
    "llm.ai_tag_validation": {"content": "Red leather shoulder bag", "candidateTags": ["red", "leather", "backpack"], "allowedTags": ["red", "leather", "shoulder-bag", "backpack"]},
    "llm.caption_validation": {"caption": "A red bag on a table", "imageDescription": "A red leather shoulder bag photographed on a white table"},
    "dataset.label_verification": {"record": {"id": "r1", "text": "Refund has not arrived"}, "candidateLabel": "billing", "allowedLabels": ["billing", "delivery", "account"]},
    "dataset.duplicate_cleanup": {"records": [{"id": "r1", "payload": "USB C cable 1m"}, {"id": "r2", "payload": "1 metre USB-C cable"}, {"id": "r3", "payload": "Wireless mouse"}]},
    "dataset.low_quality_removal": {"records": [{"id": "r1", "payload": "Complete product description"}, {"id": "r2", "payload": "x"}], "qualityCriteria": ["specific", "non-empty", "useful"], "threshold": 0.6},
    "ml.active_learning_prelabel": {"record": {"id": "r1", "text": "Package arrived two days late"}, "allowedLabels": ["delivery", "product", "billing"]},
    "ml.consensus_label_validation": {"record": {"id": "r1", "text": "Excellent battery"}, "votes": [{"annotatorId": "a1", "label": "positive", "confidence": 0.9}, {"annotatorId": "a2", "label": "positive", "confidence": 0.8}, {"annotatorId": "a3", "label": "neutral", "confidence": 0.6}]},
    "ml.human_verification_quality": {"record": {"id": "r1", "claim": "Photo contains a receipt"}, "verification": {"verdict": "yes", "evidence": ["merchant name and total visible"], "durationSeconds": 18}},
}

_FLEX_OUTPUT_SCHEMAS: dict[str, dict[str, str]] = {
    "catalog.fake_listing": {"fake": "boolean", "riskScore": "number", "reasons": "array"},
    "llm.ai_tag_validation": {"validTags": "array", "rejectedTags": "array", "score": "number", "reasons": "array"},
    "llm.caption_validation": {"valid": "boolean", "score": "number", "issues": "array", "suggestedCaption": "string"},
    "dataset.label_verification": {"valid": "boolean", "correctedLabel": "string", "confidence": "number", "reasons": "array"},
    "dataset.duplicate_cleanup": {"duplicateGroups": "array", "keepIds": "array", "removeIds": "array"},
    "dataset.low_quality_removal": {"acceptedIds": "array", "rejected": "array", "threshold": "number"},
    "ml.active_learning_prelabel": {"label": "string", "confidence": "number", "needsHumanReview": "boolean", "evidence": "array"},
    "ml.consensus_label_validation": {"consensusLabel": "string", "agreementScore": "number", "disputed": "boolean", "reason": "string"},
    "ml.human_verification_quality": {"valid": "boolean", "qualityScore": "number", "issues": "array", "recommendation": "string"},
}


def _dev_api_base() -> str:
    return dev_api_public_base()


def _pipeline_manifest(task_type: str, task_id: str, **extra: Any) -> dict[str, Any]:
    manifest: dict[str, Any] = {
        "schemaVersion": "1.0",
        "taskId": task_id,
        "taskType": task_type,
        "idempotencyKey": f"{task_id}-attempt",
        "options": {
            "languages": ["fa", "en"],
            "minOcrConfidence": 0.55,
            "maxOutputTokens": 256,
        },
    }
    manifest.update(extra)
    return manifest


def _sample_title(task_type: str) -> str:
    return {
        "document.ocr": "Sample invoice (dev OCR)",
        "document.extract": "Sample invoice (structured extract)",
        "text.summarize": "EdgeMint overview",
        "text.classify": "SMS verification sample",
        "image.classify": "Warehouse shelf photo",
        "image.remove_background": "Sample portrait (dev)",
    }.get(task_type, "Dev task input")


def _sample_prompt(task_type: str) -> str:
    if task_type == "document.ocr":
        return _OCR_DOCUMENT
    if task_type == "document.extract":
        return _OCR_DOCUMENT
    if task_type == "text.summarize":
        return _SUMMARIZE_DOCUMENT
    if task_type == "text.classify":
        return _TEXT_CLASSIFY_SAMPLE
    if task_type == "image.classify":
        return _CLASSIFY_PROMPT
    if task_type == "image.remove_background":
        return (
            "Remove the background from this customer image. "
            "Return a PNG with a transparent background."
        )
    return f"Process this {task_type} assignment payload."


def _decode_upload(*, file_name: str | None, file_mime: str | None, file_bytes: bytes | None) -> str | None:
    if not file_bytes:
        return None
    if file_mime and file_mime.startswith("text/"):
        return file_bytes.decode("utf-8", errors="replace")[:_MAX_TEXT_CHARS]
    if file_name and file_name.lower().endswith((".txt", ".md", ".csv", ".json")):
        return file_bytes.decode("utf-8", errors="replace")[:_MAX_TEXT_CHARS]
    return None


def _is_image(*, file_mime: str | None, file_name: str | None, file_bytes: bytes | None) -> bool:
    if file_mime and file_mime.startswith("image/"):
        return True
    if file_name and file_name.lower().endswith((".png", ".jpg", ".jpeg", ".webp", ".gif")):
        return True
    if file_bytes and len(file_bytes) >= 4:
        if file_bytes[:4] == b"\x89PNG":
            return True
        if file_bytes[:3] == b"\xff\xd8\xff":
            return True
    return False


def _is_pdf(*, file_mime: str | None, file_name: str | None, file_bytes: bytes | None) -> bool:
    if file_mime == "application/pdf":
        return True
    if file_name and file_name.lower().endswith(".pdf"):
        return True
    if file_bytes and len(file_bytes) >= 4 and file_bytes[:4] == b"%PDF":
        return True
    return False


def _needs_input_blob(
    *,
    task_type: str,
    file_mime: str | None,
    file_name: str | None,
    file_bytes: bytes | None,
) -> bool:
    if not file_bytes:
        return False
    family = pipeline_family(task_type)
    if family in {"document.ocr", "document.extract"}:
        return _is_image(file_mime=file_mime, file_name=file_name, file_bytes=file_bytes) or _is_pdf(
            file_mime=file_mime, file_name=file_name, file_bytes=file_bytes
        )
    if family == "image.classify":
        return _is_image(file_mime=file_mime, file_name=file_name, file_bytes=file_bytes)
    return _is_image(file_mime=file_mime, file_name=file_name, file_bytes=file_bytes)


def _options_for(
    task_type: str,
    *,
    summarize_options: dict[str, Any] | None = None,
) -> dict[str, Any]:
    if task_type in _FLEX_OUTPUT_SCHEMAS:
        return {"maxOutputTokens": 512, "outputSchema": _FLEX_OUTPUT_SCHEMAS[task_type]}
    family = pipeline_family(task_type)
    if task_type == "text.direct":
        # Output length is chosen on the worker from the prompt. Do not inject
        # the retired 256 catalog cap; that value was treated as an explicit
        # override and blocked long-form resolution.
        return {"languages": ["fa", "en"], "minOcrConfidence": 0.55}
    if family == "document.extract":
        return {
            "languages": ["fa", "en"],
            "minOcrConfidence": 0.55,
            "outputSchema": {
                "vendor": "string",
                "total": "number",
                "currency": "string",
            },
        }
    if family in {"image.classify", "text.classify"}:
        return {
            "allowedLabels": ["receipt", "invoice", "payment", "other"],
            "minOcrConfidence": 0.55,
        }
    if family == "document.ocr":
        return {"languages": ["fa", "en"], "minOcrConfidence": 0.55, "ocrOnly": True}
    if family == "text.summarize":
        options: dict[str, Any] = {
            "languages": ["fa", "en"],
            "minOcrConfidence": 0.55,
        }
        if summarize_options:
            options["summarize"] = summarize_options
        return options
    return {"languages": ["fa", "en"], "minOcrConfidence": 0.55}


def _flex_input_data(task_type: str, content_text: str | None) -> dict[str, Any] | None:
    if task_type not in _FLEX_SAMPLES:
        return None
    if content_text:
        try:
            parsed = json.loads(content_text)
        except json.JSONDecodeError as exc:
            raise ValueError("FLEX_INPUT_MUST_BE_JSON_OBJECT") from exc
        if not isinstance(parsed, dict):
            raise ValueError("FLEX_INPUT_MUST_BE_JSON_OBJECT")
        return parsed
    return _FLEX_SAMPLES[task_type]


def _passthrough_body(
    *,
    content_text: str | None,
    user_note: str | None,
) -> str:
    parts: list[str] = []
    if user_note and user_note.strip():
        parts.append(user_note.strip())
    if content_text and content_text.strip():
        text = content_text.strip()
        if not parts or text not in parts[0]:
            parts.append(text)
    combined = "\n\n".join(parts)
    return combined[:_MAX_TEXT_CHARS]


def _prompt_for_custom(
    task_type: str,
    *,
    content_text: str | None,
    file_name: str | None,
    file_mime: str | None,
    user_note: str | None = None,
) -> str:
    if task_type == "text.direct":
        body = _passthrough_body(content_text=content_text, user_note=user_note)
        if not body.strip():
            return " "
        return body
    note = f"\n\nUser note: {user_note.strip()}" if user_note and user_note.strip() else ""
    family = pipeline_family(task_type)
    if family in {"document.ocr", "document.extract"}:
        body = content_text or f"[Binary document uploaded: {file_name or 'document'}]"
        return f"OCR source document ({file_name or 'upload'}):\n\n{body}{note}"
    if family == "text.summarize":
        body = content_text or ""
        return f"Summarize the following customer text in 2 concise sentences:\n\n{body}{note}"
    if family == "text.classify":
        body = content_text or ""
        return f"Classify this text:\n\n{body}{note}"
    if family == "image.classify":
        meta = content_text or f"Uploaded image: {file_name or 'image'} ({file_mime or 'unknown'})"
        return f"Classify image metadata:\n\n{meta}{note}"
    if task_type == "image.remove_background":
        return (
            f"Remove the background from this customer image ({file_name or 'upload'}). "
            f"Return a PNG with transparent background.{note}"
        )
    body = content_text or f"Uploaded file: {file_name or 'payload'}"
    return f"Process this {task_type} customer payload:\n\n{body}{note}"


def _store_input_blob(*, task_id: str, file_bytes: bytes, file_mime: str, file_name: str) -> None:
    _INPUT_BLOBS[task_id] = {
        "bytes": file_bytes,
        "mimeType": file_mime,
        "fileName": file_name,
    }


def _ensure_sample_image(task_id: str, task_type: str) -> None:
    if not image_blob_family(task_type):
        return
    if task_id in _INPUT_BLOBS:
        return
    _store_input_blob(
        task_id=task_id,
        file_bytes=_SAMPLE_PNG_BYTES,
        file_mime="image/png",
        file_name="sample-invoice.png",
    )


def register_task(
    *,
    task_id: str,
    task_type: str,
    input_text: str | None = None,
    instructions: str | None = None,
    file_name: str | None = None,
    file_mime: str | None = None,
    file_bytes: bytes | None = None,
    summarize_options: dict[str, Any] | None = None,
) -> None:
    if file_bytes and len(file_bytes) > _MAX_FILE_BYTES:
        raise ValueError("INPUT_FILE_TOO_LARGE")

    decoded_text = _decode_upload(file_name=file_name, file_mime=file_mime, file_bytes=file_bytes)
    content_text = (input_text or decoded_text or "").strip()[:_MAX_TEXT_CHARS] or None
    user_note = instructions if instructions and instructions.strip() else None
    has_custom = bool(content_text or file_bytes or user_note)
    store_blob = _needs_input_blob(
        task_type=task_type,
        file_mime=file_mime,
        file_name=file_name,
        file_bytes=file_bytes,
    )

    if not has_custom:
        _ensure_sample_image(task_id, task_type)
        entry = _pipeline_manifest(
            task_type,
            task_id,
            mimeType="image/png" if task_id in _INPUT_BLOBS else "text/plain; charset=utf-8",
            documentTitle=_sample_title(task_type),
            prompt=_sample_prompt(task_type),
            customInput=False,
            outputKind="text" if task_type != "image.remove_background" else "image",
            options=_options_for(task_type),
        )
        flex_data = _flex_input_data(task_type, None)
        if flex_data is not None:
            entry["inputData"] = flex_data
        if task_id in _INPUT_BLOBS:
            entry["inputContentUrl"] = f"{_dev_api_base()}/v1/dev/worker/tasks/{task_id}/input/content"
        family = pipeline_family(task_type)
        if family == "text.classify":
            entry["inputText"] = _TEXT_CLASSIFY_SAMPLE
        elif family == "text.summarize":
            entry["inputText"] = _SUMMARIZE_DOCUMENT
        _TASK_INPUTS[task_id] = entry
        return

    title = file_name or ("Pasted text" if content_text else "Customer upload")
    mime = file_mime or ("text/plain; charset=utf-8" if content_text else "application/octet-stream")
    if store_blob and file_bytes:
        blob_mime = mime
        if _is_pdf(file_mime=file_mime, file_name=file_name, file_bytes=file_bytes):
            blob_mime = "application/pdf"
        elif not mime.startswith("image/"):
            blob_mime = "image/png"
        _store_input_blob(
            task_id=task_id,
            file_bytes=file_bytes,
            file_mime=blob_mime,
            file_name=file_name or "input.bin",
        )

    entry = _pipeline_manifest(
        task_type,
        task_id,
        mimeType=mime,
        documentTitle=title,
        prompt=_prompt_for_custom(
            task_type,
            content_text=content_text,
            file_name=file_name,
            file_mime=file_mime,
            user_note=user_note,
        ),
        customInput=True,
        inputLabel=title,
        outputKind="image" if task_type == "image.remove_background" else "text",
        options=_options_for(task_type, summarize_options=summarize_options),
    )
    flex_data = _flex_input_data(task_type, content_text)
    if flex_data is not None:
        entry["inputData"] = flex_data
    if user_note and task_type != "text.direct":
        entry["instructions"] = user_note
    if store_blob and task_id in _INPUT_BLOBS:
        entry["inputContentUrl"] = f"{_dev_api_base()}/v1/dev/worker/tasks/{task_id}/input/content"
    if task_type == "text.direct":
        passthrough = _passthrough_body(content_text=content_text, user_note=user_note)
        if passthrough.strip():
            entry["inputText"] = passthrough
            entry["prompt"] = passthrough
    elif content_text:
        entry["inputText"] = content_text
    _TASK_INPUTS[task_id] = entry


def ensure_registered(*, task_id: str, task_type: str) -> None:
    if task_id in _TASK_INPUTS:
        return
    register_task(task_id=task_id, task_type=task_type)


def input_manifest(task_id: str) -> dict[str, Any] | None:
    if task_id in _TASK_INPUTS:
        return dict(_TASK_INPUTS[task_id])
    from edgemint.dev import fixtures

    for workspace_id in fixtures.DEV_WORKSPACE_IDS:
        task = fixtures.dev_task(workspace_id, task_id)
        if task is not None:
            source = task.get("inputSource")
            if source:
                register_task(task_id=task_id, task_type=task["taskType"], **source)
            else:
                register_task(task_id=task_id, task_type=task["taskType"])
            return dict(_TASK_INPUTS[task_id])
    return None


def input_content(task_id: str) -> dict[str, Any] | None:
    if task_id not in _INPUT_BLOBS and task_id not in _TASK_INPUTS:
        input_manifest(task_id)
    return _INPUT_BLOBS.get(task_id)


def result_content(task_id: str) -> dict[str, Any] | None:
    return _RESULT_BLOBS.get(task_id)


def content_response(blob: dict[str, Any] | None) -> Response:
    if blob is None:
        raise ValueError("CONTENT_NOT_FOUND")
    return Response(
        content=blob["bytes"],
        media_type=blob.get("mimeType", "application/octet-stream"),
        headers={
            "Content-Disposition": f'inline; filename="{blob.get("fileName", "result")}"',
        },
    )


def _workspace_id_for_task(task_id: str):
    from edgemint.dev import fixtures

    for workspace_id in fixtures.DEV_WORKSPACE_IDS:
        if fixtures.dev_task(workspace_id, task_id) is not None:
            return workspace_id
    return None


def record_output(
    *,
    task_id: str,
    result_text: str,
    metrics: dict[str, Any] | None = None,
    result_file_bytes: bytes | None = None,
    result_file_name: str | None = None,
    result_mime_type: str | None = None,
) -> None:
    from edgemint.dev import fixtures

    model_transcript = result_text
    if metrics:
        structured_raw = metrics.get("structuredResultJson")
        if isinstance(structured_raw, str) and structured_raw.strip():
            try:
                envelope = json.loads(structured_raw)
                if isinstance(envelope, dict):
                    output = envelope.get("output")
                    if isinstance(output, dict):
                        transcript = output.get("modelTranscript") or output.get("rawText")
                        if isinstance(transcript, str) and transcript.strip():
                            model_transcript = transcript.strip()
            except json.JSONDecodeError:
                pass

    existing = fixtures.dev_task_by_id(task_id)
    if existing is not None and existing.get("lifecycleStatus") == "succeeded":
        _TASK_INPUTS.setdefault(task_id, {"taskId": task_id})
        _TASK_INPUTS[task_id]["lastOutput"] = {
            "resultText": result_text[:_MAX_TEXT_CHARS],
            "modelTranscript": model_transcript[:_MAX_TEXT_CHARS],
            "metrics": metrics or {},
            "hasResultFile": bool(result_file_bytes),
        }
        return

    workspace_id = _workspace_id_for_task(task_id)
    result_artifact_url = None
    result_mime = result_mime_type
    if result_file_bytes:
        file_name = result_file_name or "result.png"
        mime = result_mime_type or "image/png"
        _RESULT_BLOBS[task_id] = {
            "bytes": result_file_bytes,
            "mimeType": mime,
            "fileName": file_name,
        }
        result_mime = mime
        if workspace_id is not None:
            result_artifact_url = f"/v1/workspaces/{workspace_id}/tasks/{task_id}/result-file"

    fixtures.update_dev_task_execution(
        task_id,
        lifecycle_status="succeeded",
        execution_status="completed",
        result_text=model_transcript,
        result_artifact_url=result_artifact_url,
        result_mime_type=result_mime,
        model_transcript=model_transcript,
    )
    _TASK_INPUTS.setdefault(task_id, {"taskId": task_id})
    _TASK_INPUTS[task_id]["lastOutput"] = {
        "resultText": result_text[:_MAX_TEXT_CHARS],
        "modelTranscript": model_transcript[:_MAX_TEXT_CHARS],
        "metrics": metrics or {},
        "hasResultFile": bool(result_file_bytes),
    }
