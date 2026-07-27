from __future__ import annotations

from dataclasses import dataclass


@dataclass(slots=True)
class ModelServiceError(Exception):
    code: str
    status: int
    title: str
    detail: str | None = None


def model_error(code: str, *, detail: str | None = None) -> ModelServiceError:
    catalog: dict[str, tuple[int, str]] = {
        "AUTH_INVALID_CREDENTIAL": (401, "Invalid credentials"),
        "AUTH_SCOPE_REQUIRED": (403, "Required permission missing"),
        "DOWNLOAD_POLICY_BLOCKED": (403, "Download blocked by policy"),
        "IDEMPOTENCY_CONFLICT": (409, "Idempotency conflict"),
        "INPUT_SCHEMA_INVALID": (422, "Invalid request"),
        "INSUFFICIENT_STORAGE": (409, "Insufficient storage"),
        "MODEL_DIGEST_MISMATCH": (409, "Model digest mismatch"),
        "MODEL_HAS_ACTIVE_ASSIGNMENTS": (409, "Model has active assignments"),
        "MODEL_NOT_COMPATIBLE": (409, "Model not compatible with device"),
        "MODEL_RELEASE_EVIDENCE_MISSING": (409, "Model release evidence missing"),
        "MODEL_REVOCATION_REASON_REQUIRED": (422, "Revocation reason required"),
        "MODEL_ROLLOUT_ALREADY_ACTIVE": (409, "Model rollout already active"),
        "MODEL_SIGNATURE_INVALID": (403, "Model signature invalid"),
        "MODEL_UNLOAD_FAILED": (409, "Model unload failed"),
        "RUNTIME_ABI_MISMATCH": (409, "Runtime ABI mismatch"),
        "TENANT_RESOURCE_NOT_FOUND": (404, "Resource not found"),
        "VERSION_CONFLICT": (412, "Version conflict"),
    }
    status, title = catalog.get(code, (500, "Model operation failed"))
    return ModelServiceError(code=code, status=status, title=title, detail=detail)
