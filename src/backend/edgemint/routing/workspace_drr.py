"""Workspace deficit round-robin (DRR) accounting (Architecture v2 §9, §36, A19)."""

from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import yaml

DEFAULT_POLICY_PATH = (
    Path(__file__).resolve().parents[4]
    / "dsl"
    / "policies"
    / "scheduling"
    / "workspace-admission-backpressure-v1.yaml"
)


@dataclass
class WorkspaceDrrState:
    deficit_by_workspace: dict[str, int] = field(default_factory=dict)
    consecutive_assignments: dict[str, int] = field(default_factory=dict)
    last_assigned_workspace: str | None = None

    def deficit(self, workspace_id: str) -> int:
        return int(self.deficit_by_workspace.get(workspace_id, 0))

    def set_deficit(self, workspace_id: str, units: int) -> None:
        self.deficit_by_workspace[workspace_id] = max(0, int(units))


def load_admission_backpressure_policy(path: Path | None = None) -> dict[str, Any]:
    policy_path = path or DEFAULT_POLICY_PATH
    raw = yaml.safe_load(policy_path.read_text(encoding="utf-8"))
    if not isinstance(raw, dict):
        raise ValueError(f"invalid admission backpressure policy: {policy_path}")
    return raw


def compute_queue_cost_units(
    estimated_execution_ms: int,
    *,
    divisor_ms: int = 1000,
) -> int:
    """Map estimator milliseconds to common queue cost units."""
    safe_ms = max(0, int(estimated_execution_ms))
    safe_divisor = max(1, int(divisor_ms))
    return max(1, (safe_ms + safe_divisor - 1) // safe_divisor)


def credit_idle_workspaces(
    state: WorkspaceDrrState,
    workspace_ids: list[str],
    *,
    quantum_units: int,
    credit_cap_units: int,
) -> None:
    """Increase deficit for idle workspaces up to the configured credit cap."""
    cap = max(0, int(credit_cap_units))
    quantum = max(1, int(quantum_units))
    for workspace_id in workspace_ids:
        current = state.deficit(workspace_id)
        state.set_deficit(workspace_id, min(cap, current + quantum))


def apply_dispatch_debit(
    state: WorkspaceDrrState,
    *,
    workspace_id: str,
    cost_units: int,
) -> int:
    """Debit served workspace deficit after dispatch; returns remaining deficit."""
    current = state.deficit(workspace_id)
    remaining = max(0, current - max(1, int(cost_units)))
    state.set_deficit(workspace_id, remaining)
    if state.last_assigned_workspace == workspace_id:
        state.consecutive_assignments[workspace_id] = (
            int(state.consecutive_assignments.get(workspace_id, 0)) + 1
        )
    else:
        for key in list(state.consecutive_assignments):
            if key != workspace_id:
                state.consecutive_assignments[key] = 0
        state.consecutive_assignments[workspace_id] = 1
        state.last_assigned_workspace = workspace_id
    return remaining


def attach_workspace_deficits(
    attempts: list[dict[str, Any]],
    state: WorkspaceDrrState,
) -> list[dict[str, Any]]:
    """Inject current workspace deficit into attempt records for fair ranking."""
    enriched: list[dict[str, Any]] = []
    for attempt in attempts:
        workspace_id = str(attempt["workspaceId"])
        merged = dict(attempt)
        merged["deficitUnits"] = state.deficit(workspace_id)
        enriched.append(merged)
    return enriched


def enforce_consecutive_assignment_cap(
    state: WorkspaceDrrState,
    *,
    workspace_id: str,
    max_consecutive: int,
) -> bool:
    """Return True when another consecutive assignment for the workspace is permitted."""
    limit = max(1, int(max_consecutive))
    current = int(state.consecutive_assignments.get(workspace_id, 0))
    return current < limit


def select_next_workspace_under_drr(
    attempts: list[dict[str, Any]],
    state: WorkspaceDrrState,
    *,
    max_consecutive: int,
) -> str | None:
    """Pick workspace with highest deficit that still has queued attempts and cap headroom."""
    by_workspace: dict[str, list[dict[str, Any]]] = {}
    for attempt in attempts:
        workspace_id = str(attempt["workspaceId"])
        by_workspace.setdefault(workspace_id, []).append(attempt)

    candidates = [
        workspace_id
        for workspace_id in by_workspace
        if enforce_consecutive_assignment_cap(
            state,
            workspace_id=workspace_id,
            max_consecutive=max_consecutive,
        )
    ]
    if not candidates:
        return None
    return max(candidates, key=lambda workspace_id: state.deficit(workspace_id))
