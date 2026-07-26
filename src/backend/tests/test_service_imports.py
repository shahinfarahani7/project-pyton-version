import importlib
import pytest

SERVICES = ['api_gateway', 'identity', 'customer', 'file', 'task_intake', 'pricing', 'router', 'worker_gateway', 'worker_registry', 'result', 'verification', 'billing', 'ledger', 'reward', 'claim', 'fraud', 'webhook', 'model_registry', 'notification', 'operations', 'event_relay']

@pytest.mark.parametrize("service", SERVICES)
def test_service_exposes_fastapi_application(service: str) -> None:
    module = importlib.import_module(f"edgemint.services.{service}")
    assert module.app.version == "5.0.0"
