import asyncio

import pytest

from edgemint.dev import fixtures, task_events, task_type_catalog

WORKSPACE = fixtures.DEV_WORKSPACE_PRIMARY


@pytest.mark.asyncio
async def test_task_event_stream_notifies_subscribers() -> None:
    queue = await task_events.subscribe(WORKSPACE)
    try:
        task = fixtures.create_dev_task(WORKSPACE, task_type="text.summarize")
        enriched = task_type_catalog.enrich_task_row(task)
        task_events.publish_task_event(
            WORKSPACE,
            event="task.updated",
            task_id=task["id"],
            task=enriched,
        )
        payload = await asyncio.wait_for(queue.get(), timeout=1.0)
        while "task.updated" not in payload:
            payload = await asyncio.wait_for(queue.get(), timeout=1.0)
        assert task["id"] in payload
        assert "task.updated" in payload
    finally:
        await task_events.unsubscribe(WORKSPACE, queue)


def test_update_dev_task_execution_publishes_event() -> None:
    task = fixtures.create_dev_task(WORKSPACE, task_type="text.summarize")

    async def collect() -> str:
        queue = await task_events.subscribe(WORKSPACE)
        try:
            fixtures.update_dev_task_execution(
                task["id"],
                lifecycle_status="succeeded",
                execution_status="completed",
                result_preview="Done",
            )
            return await asyncio.wait_for(queue.get(), timeout=1.0)
        finally:
            await task_events.unsubscribe(WORKSPACE, queue)

    payload = asyncio.run(collect())
    assert task["id"] in payload
    assert "Done" in payload
