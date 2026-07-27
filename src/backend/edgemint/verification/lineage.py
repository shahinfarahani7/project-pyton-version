from __future__ import annotations

from dataclasses import dataclass
from typing import Any


@dataclass(frozen=True, slots=True)
class LineageNode:
    kind: str
    identifier: str
    digest: str | None = None


def build_dispute_lineage(
    *,
    task_id: str,
    attempt_id: str,
    assignment_id: str,
    result_id: str,
    verification_id: str,
    decision_evidence_id: str,
    result_sha256: str,
    input_digest: str,
    model_digest: str,
) -> dict[str, Any]:
    nodes = [
        LineageNode("task", task_id),
        LineageNode("attempt", attempt_id),
        LineageNode("assignment", assignment_id),
        LineageNode("input", input_digest, input_digest),
        LineageNode("model", model_digest, model_digest),
        LineageNode("result", result_id, result_sha256),
        LineageNode("verification", verification_id),
        LineageNode("decision_evidence", decision_evidence_id),
    ]
    return {
        "disputeReady": True,
        "chain": [
            {"kind": node.kind, "id": node.identifier, "digest": node.digest}
            for node in nodes
        ],
    }
