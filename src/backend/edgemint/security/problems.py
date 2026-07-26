from __future__ import annotations

from typing import Any
from uuid import uuid4

from fastapi import HTTPException, Request
from starlette.responses import JSONResponse

PROBLEM_TYPE = "https://problems.edgemint.io/"


def problem_response(
    *,
    status: int,
    code: str,
    title: str,
    detail: str | None = None,
    trace_id: str | None = None,
) -> JSONResponse:
    return JSONResponse(
        {
            "type": f"{PROBLEM_TYPE}{code.lower().replace('_', '-')}",
            "title": title,
            "status": status,
            "code": code,
            "traceId": trace_id or str(uuid4()),
            **({"detail": detail} if detail else {}),
        },
        status_code=status,
    )


def raise_auth_error(code: str, *, status: int = 401, detail: str | None = None) -> None:
    titles = {
        "AUTH_INVALID_CREDENTIAL": "Invalid credentials",
        "AUTH_SCOPE_REQUIRED": "Required permission missing",
        "AUTH_SESSION_REVOKED": "Session revoked",
        "AUTH_CSRF_FAILED": "CSRF validation failed",
        "AUTH_WORKSPACE_MISMATCH": "Workspace binding mismatch",
    }
    raise HTTPException(
        status_code=status,
        detail={
            "code": code,
            "title": titles.get(code, "Authorization failed"),
            "detail": detail,
        },
    )


def request_trace_id(request: Request) -> str:
    return request.headers.get("x-request-id") or str(uuid4())


def problem_from_http_exception(exc: HTTPException) -> dict[str, Any]:
    if isinstance(exc.detail, dict):
        return exc.detail
    return {"code": "UNEXPECTED_ERROR", "title": str(exc.detail)}
