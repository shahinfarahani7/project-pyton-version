from __future__ import annotations

from typing import Any

from fastapi.responses import JSONResponse
from pydantic import BaseModel

from edgemint.building_blocks.app import create_service_app
from edgemint.notifications.templates import render_template

app = create_service_app("notification")


class RenderTemplateRequest(BaseModel):
    templateId: str
    context: dict[str, Any]


@app.post("/internal/notifications/templates:render", tags=["notification"])
async def render_notification_template(payload: RenderTemplateRequest) -> JSONResponse:
    try:
        body = render_template(payload.templateId, payload.context)
    except KeyError as exc:
        return JSONResponse({"code": "INPUT_SCHEMA_INVALID", "detail": str(exc)}, status_code=422)
    return JSONResponse({"templateId": payload.templateId, "body": body}, status_code=200)
