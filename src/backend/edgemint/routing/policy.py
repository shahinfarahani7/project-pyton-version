from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Any

import yaml


@dataclass(frozen=True, slots=True)
class RoutingPolicy:
    spec: dict[str, Any]

    @classmethod
    def load(cls, path: Path | None = None) -> RoutingPolicy:
        policy_path = path or (
            Path(__file__).resolve().parents[4] / "dsl" / "policies" / "routing" / "smart-router-v2.yaml"
        )
        document = yaml.safe_load(policy_path.read_text(encoding="utf-8"))
        return cls(spec=document["spec"])

    @property
    def eligibility(self) -> dict[str, Any]:
        return self.spec["eligibility"]

    @property
    def score_weights_bps(self) -> dict[str, int]:
        return dict(self.spec["score"]["weightsBps"])

    @property
    def assignment_mode(self) -> str:
        return str(self.spec["assignmentMode"])

    @property
    def per_task_worker_confirmation(self) -> bool:
        return bool(self.spec["perTaskWorkerConfirmation"])

    @property
    def max_worker_reassignments(self) -> int:
        return int(self.spec["fallback"]["maxWorkerReassignments"])

    @property
    def cloud_after_seconds(self) -> int:
        return int(self.spec["fallback"]["cloudAfterSeconds"])

    @property
    def delivery_ack_meaning(self) -> str:
        return str(self.spec["deliveryAcknowledgementMeaning"])
