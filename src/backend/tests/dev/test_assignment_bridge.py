from __future__ import annotations

from unittest.mock import MagicMock, patch

from edgemint.dev.assignment_bridge import enqueue_assignment_for_worker


def test_enqueue_assignment_falls_back_to_local_queue_on_http_error() -> None:
    with patch("edgemint.dev.assignment_bridge.httpx.Client") as client_cls:
        client = MagicMock()
        client.__enter__.return_value = client
        client.post.side_effect = RuntimeError("connection refused")
        client_cls.return_value = client

        with patch("edgemint.dev.worker_assignments.enqueue_dev_assignment") as enqueue:
            enqueue_assignment_for_worker(task_id="tsk_dev_abc", task_type="text.generate")
            enqueue.assert_called_once_with(task_id="tsk_dev_abc", task_type="text.generate")
