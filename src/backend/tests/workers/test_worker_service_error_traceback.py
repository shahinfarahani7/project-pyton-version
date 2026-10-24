from edgemint.workers.errors import WorkerServiceError, worker_error


def test_worker_service_error_allows_traceback_assignment() -> None:
    """Py 3.13 context managers assign __traceback__ on exit; slotted errors must allow it."""
    exc = worker_error("AUTH_INVALID_CREDENTIAL")
    assert isinstance(exc, WorkerServiceError)
    exc.__traceback__ = None
    exc.__context__ = None
    exc.__cause__ = None
