from __future__ import annotations

from typing import Any

from fastapi.responses import JSONResponse
from pydantic import BaseModel

from edgemint.building_blocks.app import create_service_app
from edgemint.rewards.engine import compute_reward

app = create_service_app("reward")


class ComputeRewardRequest(BaseModel):
    input: dict[str, Any]


@app.post("/internal/reward/compute", tags=["reward"])
async def compute_worker_reward(payload: ComputeRewardRequest) -> JSONResponse:
    return JSONResponse(compute_reward(payload.input), status_code=200)


@app.get("/reward/policy", tags=["reward"])
async def get_reward_policy() -> JSONResponse:
    from edgemint.rewards.policy import load_reward_policy

    policy = load_reward_policy()
    return JSONResponse(
        {
            "unit": policy.unit,
            "policyVersion": policy.version_label,
            "holds": policy.spec["holds"],
        },
        status_code=200,
    )
