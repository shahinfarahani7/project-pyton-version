from __future__ import annotations

from edgemint.routing.scarcity_cost import AttemptWorkerFailure

_ARTIFACT_BLOCKING_FAILURE_CODES: frozenset[str] = frozenset(
    {
        "MODEL_EXECUTION_FAILED",
        "MODEL_DIGEST_MISMATCH",
        "GOLDEN_VALIDATION_FAILED",
    }
)


def blocked_artifact_digests_from_failures(
    failures: list[AttemptWorkerFailure],
) -> frozenset[str]:
    """Section 45: shared corrupt artifact blocks affected pool until recovery."""
    blocked: set[str] = set()
    for failure in failures:
        if failure.failure_code not in _ARTIFACT_BLOCKING_FAILURE_CODES:
            continue
        if failure.model_version_id:
            blocked.add(failure.model_version_id)
    return frozenset(blocked)


def artifact_blocks_worker(
    *,
    model_version_id: str | None,
    blocked_artifact_digests: frozenset[str],
) -> bool:
    if not model_version_id:
        return False
    return model_version_id in blocked_artifact_digests
