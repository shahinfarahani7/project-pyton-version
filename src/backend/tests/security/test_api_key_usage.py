from datetime import UTC, datetime, timedelta
from uuid import uuid4

import pytest
from edgemint.security.api_key_usage import ApiKeyUsage


def test_summary_counts_requests_tasks_errors_and_buckets() -> None:
    usage = ApiKeyUsage()
    workspace = uuid4()
    other = uuid4()
    now = datetime(2026, 11, 1, 12, tzinfo=UTC)
    usage.record("key_a", workspace, kind="task", ok=True, client_ip="10.0.0.1", at=now - timedelta(hours=2))
    recent = now - timedelta(minutes=5)
    usage.record("key_a", workspace, kind="request", ok=True, client_ip="10.0.0.2", at=recent)
    usage.record("key_a", workspace, kind="task", ok=False, client_ip="10.0.0.3", at=now - timedelta(days=3))
    usage.record("key_b", other, kind="task", ok=True, client_ip=None, at=now)

    day = usage.summary(workspace, "day", now=now)
    assert len(day["buckets"]) == 24
    [item] = day["items"]
    assert item["keyId"] == "key_a"
    assert item["totalRequests"] == 3
    assert item["totalTasks"] == 1
    assert item["rangeRequests"] == 2
    assert item["rangeTasks"] == 1
    assert item["rangeErrors"] == 0
    assert item["lastIp"] == "10.0.0.2"
    assert sum(item["series"]) == 2

    week = usage.summary(workspace, "week", now=now)
    assert week["items"][0]["rangeErrors"] == 1
    assert len(usage.summary(workspace, "6m", now=now)["buckets"]) == 26


def test_summary_rejects_unknown_range() -> None:
    with pytest.raises(ValueError, match="USAGE_RANGE_INVALID"):
        ApiKeyUsage().summary(uuid4(), "year")
