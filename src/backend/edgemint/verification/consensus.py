from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from edgemint.verification.errors import verification_error


@dataclass(frozen=True, slots=True)
class ConsensusVote:
    worker_id: str
    worker_device_id: str
    result_sha256: str
    similarity_milli: int
    decision: str


def evaluate_consensus(
    votes: list[ConsensusVote],
    *,
    minimum_workers: int,
    minimum_similarity_milli: int,
) -> dict[str, Any]:
    if len(votes) < minimum_workers:
        raise verification_error("CONSENSUS_QUORUM_NOT_REACHED")

    workers = {vote.worker_id for vote in votes}
    devices = {vote.worker_device_id for vote in votes}
    if len(workers) != len(votes) or len(devices) != len(votes):
        raise verification_error("CONSENSUS_IDENTITY_COLLISION")

    digests = {vote.result_sha256 for vote in votes}
    if len(digests) != 1:
        raise verification_error("VERIFICATION_DISAGREEMENT")

    if any(vote.similarity_milli < minimum_similarity_milli for vote in votes):
        return {
            "outcome": "human_review",
            "reason": "similarity_below_threshold",
            "strategy": "consensus",
            "voteCount": len(votes),
            "deterministic": True,
        }

    return {
        "outcome": "accepted",
        "reason": "consensus_quorum_met",
        "strategy": "consensus",
        "voteCount": len(votes),
        "deterministic": True,
    }
