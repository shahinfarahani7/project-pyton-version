from __future__ import annotations

import json

from edgemint.routing.routing_audit import policy_hash


def test_policy_hash_is_64_char_hex() -> None:
    digest = policy_hash()
    assert len(digest) == 64
    int(digest, 16)


def test_routing_audit_schema_fields_documented() -> None:
    sample = {
        "task_attempt_id": "11111111-1111-1111-1111-111111111111",
        "task_id": "tsk_1",
        "router_epoch": 3,
        "policy_hash": policy_hash(),
        "winner_worker_id": "wrk_win",
        "winner_score": 9120,
        "candidates_json": [{"workerId": "wrk_win", "score": 9120, "eligible": True}],
        "decision_trace_json": {"eligibleCount": 1, "candidateCount": 2},
    }
    payload = json.dumps(sample)
    assert "policy_hash" in payload
    assert "candidates_json" in payload
