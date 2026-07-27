from __future__ import annotations

from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field

from edgemint.building_blocks.app import create_service_app
from edgemint.ledger.engine import compute_ledger

app = create_service_app("ledger")


class PostLedgerRequest(BaseModel):
    chargeMicros: int = Field(ge=0)
    rewardMicros: int = Field(ge=0)
    refundMicros: int = Field(ge=0)


@app.post("/internal/ledger/post", tags=["ledger"])
async def post_ledger(payload: PostLedgerRequest) -> JSONResponse:
    entries, expected = compute_ledger(payload.model_dump())
    return JSONResponse({"entries": entries, "expected": expected}, status_code=200)


@app.get("/ledger/policy", tags=["ledger"])
async def get_ledger_policy() -> JSONResponse:
    from edgemint.ledger.policy import load_ledger_policy

    policy = load_ledger_policy()
    return JSONResponse(
        {
            "currencyMode": policy.spec["currencyMode"],
            "reconciliation": policy.spec["reconciliation"],
            "postingRules": list(policy.spec["postingRules"].keys()),
        },
        status_code=200,
    )
