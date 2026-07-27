from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

import yaml

from edgemint.workers.errors import worker_error

TERMINAL_STATUSES = frozenset({"banned"})
PAID_WORK_READY_STATUSES = frozenset({"ready"})


@dataclass(frozen=True, slots=True)
class WorkerLifecycle:
    transitions: frozenset[tuple[str, str]]

    @classmethod
    def load(cls, path: Path | None = None) -> WorkerLifecycle:
        workflow_path = path or (
            Path(__file__).resolve().parents[4] / "dsl" / "workflows" / "worker-lifecycle.yaml"
        )
        document = yaml.safe_load(workflow_path.read_text(encoding="utf-8"))
        pairs = {(str(item["from"]), str(item["to"])) for item in document["spec"]["transitions"]}
        return cls(transitions=frozenset(pairs))

    def can_transition(self, current: str, target: str) -> bool:
        return (current, target) in self.transitions

    def assert_transition(self, current: str, target: str) -> None:
        if current in TERMINAL_STATUSES:
            raise worker_error("WORKER_QUARANTINED", detail=f"terminal state {current}")
        if not self.can_transition(current, target):
            raise worker_error("WORKER_NOT_READY", detail=f"{current} -> {target} not allowed")
