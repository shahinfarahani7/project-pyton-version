from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

import yaml

from edgemint.models.errors import model_error

ACTIVE_STATUSES = frozenset({"active"})
REVOKED_STATUSES = frozenset({"revoked"})
PROMOTABLE_STATUSES = frozenset({"draft", "pending_approval", "approved"})


@dataclass(frozen=True, slots=True)
class ModelVersionLifecycle:
    transitions: frozenset[tuple[str, str]]

    @classmethod
    def load(cls, path: Path | None = None) -> ModelVersionLifecycle:
        # Model version states are encoded in promotion/revocation rules; reuse download lifecycle file
        # only for device-side download state checks elsewhere.
        pairs = {
            ("draft", "pending_approval"),
            ("draft", "active"),
            ("pending_approval", "approved"),
            ("approved", "active"),
            ("active", "deprecated"),
            ("active", "revoked"),
            ("deprecated", "revoked"),
        }
        return cls(transitions=frozenset(pairs))

    def can_transition(self, current: str, target: str) -> bool:
        return (current, target) in self.transitions

    def assert_transition(self, current: str, target: str) -> None:
        if current in REVOKED_STATUSES:
            raise model_error("MODEL_SIGNATURE_INVALID", detail=f"terminal state {current}")
        if not self.can_transition(current, target):
            raise model_error("MODEL_RELEASE_EVIDENCE_MISSING", detail=f"{current}->{target} not allowed")


@dataclass(frozen=True, slots=True)
class ModelDownloadLifecycle:
    transitions: frozenset[tuple[str, str]]

    @classmethod
    def load(cls, path: Path | None = None) -> ModelDownloadLifecycle:
        workflow_path = path or (
            Path(__file__).resolve().parents[4] / "dsl" / "workflows" / "model-download-lifecycle.yaml"
        )
        document = yaml.safe_load(workflow_path.read_text(encoding="utf-8"))
        pairs = {(str(item["from"]), str(item["to"])) for item in document["spec"]["transitions"]}
        return cls(transitions=frozenset(pairs))

    def can_transition(self, current: str, target: str) -> bool:
        return (current, target) in self.transitions
