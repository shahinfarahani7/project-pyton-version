from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum
from uuid import UUID

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncConnection

from edgemint.routing.envelope_registry import envelope_for_task_type
from edgemint.routing.errors import router_error


# Fixed runtime overhead baseline (v2 §16 policy commitment bucket).
FIXED_RUNTIME_BASE_MEMORY_BYTES = 256 * 1024 * 1024

# Default resident model memory when envelope-specific resident bytes unavailable.
DEFAULT_RESIDENT_MODEL_MEMORY_BYTES = 768 * 1024 * 1024


class MemoryCommitmentKind(StrEnum):
    BASE = "base"
    RESIDENT = "resident"
    TASK_PEAK = "task_peak"
    TRANSFER = "transfer"


class MemoryAttributionStatus(StrEnum):
    KNOWN = "known"
    UNCERTAIN = "uncertain"


@dataclass(frozen=True, slots=True)
class MemoryCommitment:
    kind: MemoryCommitmentKind
    commitment_key: str
    memory_bytes: int
    peak_memory_bytes: int
    resident_identity: str | None = None


@dataclass(frozen=True, slots=True)
class MemoryAdmissionResult:
    allowed: bool
    accounted_bytes: int
    remaining_bytes: int
    reasons: tuple[str, ...]
    attribution_status: MemoryAttributionStatus


def dedupe_resident_commitments(
    commitments: list[MemoryCommitment],
) -> list[MemoryCommitment]:
    """Count each resident identity once (v2 §610, T04 warm-model rule)."""
    seen_resident: set[str] = set()
    result: list[MemoryCommitment] = []
    for commitment in commitments:
        if commitment.kind != MemoryCommitmentKind.RESIDENT:
            result.append(commitment)
            continue
        identity = commitment.resident_identity or commitment.commitment_key
        if identity in seen_resident:
            continue
        seen_resident.add(identity)
        result.append(commitment)
    return result


def accounted_memory_bytes(commitments: list[MemoryCommitment]) -> int:
    """Sum commitments without double-counting shared resident memory."""
    total = 0
    for commitment in dedupe_resident_commitments(commitments):
        total += max(commitment.peak_memory_bytes, commitment.memory_bytes)
    return total


def evaluate_memory_admission(
    *,
    effective_memory_limit_bytes: int,
    commitments: list[MemoryCommitment],
    requested: MemoryCommitment | None = None,
    attribution_status: MemoryAttributionStatus = MemoryAttributionStatus.KNOWN,
) -> MemoryAdmissionResult:
    active = list(commitments)
    if requested is not None:
        active.append(requested)
    if attribution_status == MemoryAttributionStatus.UNCERTAIN:
        return MemoryAdmissionResult(
            allowed=False,
            accounted_bytes=accounted_memory_bytes(active),
            remaining_bytes=0,
            reasons=("CAPACITY_UNCERTAIN",),
            attribution_status=attribution_status,
        )
    accounted = accounted_memory_bytes(active)
    remaining = max(0, effective_memory_limit_bytes - accounted)
    if accounted > effective_memory_limit_bytes:
        return MemoryAdmissionResult(
            allowed=False,
            accounted_bytes=accounted,
            remaining_bytes=remaining,
            reasons=("MEMORY_BUDGET_EXCEEDED",),
            attribution_status=attribution_status,
        )
    return MemoryAdmissionResult(
        allowed=True,
        accounted_bytes=accounted,
        remaining_bytes=remaining,
        reasons=(),
        attribution_status=attribution_status,
    )


def base_runtime_commitment() -> MemoryCommitment:
    return MemoryCommitment(
        kind=MemoryCommitmentKind.BASE,
        commitment_key="runtime_base",
        memory_bytes=FIXED_RUNTIME_BASE_MEMORY_BYTES,
        peak_memory_bytes=FIXED_RUNTIME_BASE_MEMORY_BYTES,
    )


def resident_commitment_for_model(model_version_id: str, *, memory_bytes: int | None = None) -> MemoryCommitment:
    resident_bytes = memory_bytes if memory_bytes is not None else DEFAULT_RESIDENT_MODEL_MEMORY_BYTES
    return MemoryCommitment(
        kind=MemoryCommitmentKind.RESIDENT,
        commitment_key=f"resident:{model_version_id}",
        memory_bytes=resident_bytes,
        peak_memory_bytes=resident_bytes,
        resident_identity=model_version_id,
    )


def task_peak_commitment_for_assignment(
    *,
    assignment_id: str,
    task_type: str,
) -> MemoryCommitment:
    envelope = envelope_for_task_type(task_type)
    peak = envelope.memory_reservation_bytes if envelope is not None else 512 * 1024 * 1024
    return MemoryCommitment(
        kind=MemoryCommitmentKind.TASK_PEAK,
        commitment_key=f"task_peak:{assignment_id}",
        memory_bytes=peak,
        peak_memory_bytes=peak,
    )


class WorkerMemoryAccountingService:
    """Persist and load worker memory commitments (v2 §16, §19, A04)."""

    async def ensure_base_commitment(
        self,
        connection: AsyncConnection,
        *,
        worker_device_id: UUID,
        snapshot_sequence: int = 1,
    ) -> None:
        base = base_runtime_commitment()
        await self._upsert(
            connection,
            worker_device_id=worker_device_id,
            commitment=base,
            snapshot_sequence=snapshot_sequence,
        )

    async def sync_resident_models(
        self,
        connection: AsyncConnection,
        *,
        worker_device_id: UUID,
        loaded_model_ids: list[str],
        snapshot_sequence: int,
        resident_memory_by_model: dict[str, int] | None = None,
    ) -> None:
        memory_by_model = resident_memory_by_model or {}
        for model_id in loaded_model_ids:
            commitment = resident_commitment_for_model(
                model_id,
                memory_bytes=memory_by_model.get(model_id),
            )
            await self._upsert(
                connection,
                worker_device_id=worker_device_id,
                commitment=commitment,
                snapshot_sequence=snapshot_sequence,
            )

    async def record_task_peak_for_assignment(
        self,
        connection: AsyncConnection,
        *,
        worker_device_id: UUID,
        assignment_id: UUID,
        task_type: str,
        snapshot_sequence: int = 1,
    ) -> None:
        commitment = task_peak_commitment_for_assignment(
            assignment_id=str(assignment_id),
            task_type=task_type,
        )
        await self._upsert(
            connection,
            worker_device_id=worker_device_id,
            commitment=commitment,
            assignment_id=assignment_id,
            snapshot_sequence=snapshot_sequence,
        )

    async def release_task_peak_for_assignment(
        self,
        connection: AsyncConnection,
        *,
        assignment_id: UUID,
    ) -> int:
        released = (
            await connection.execute(
                text(
                    """
                    SELECT public.release_worker_memory_commitment_by_assignment(
                        :assignment_id, 'task_peak'
                    )
                    """
                ),
                {"assignment_id": assignment_id},
            )
        ).scalar_one()
        return int(released)

    async def load_active_commitments(
        self,
        connection: AsyncConnection,
        *,
        worker_device_id: UUID,
    ) -> list[MemoryCommitment]:
        rows = (
            await connection.execute(
                text(
                    """
                    SELECT commitment_kind, commitment_key, resident_identity,
                           memory_bytes, peak_memory_bytes
                    FROM public.worker_memory_commitments
                    WHERE worker_device_id = :worker_device_id
                      AND status = 'active'
                    """
                ),
                {"worker_device_id": worker_device_id},
            )
        ).mappings()
        commitments = [
            MemoryCommitment(
                kind=MemoryCommitmentKind(str(row["commitment_kind"])),
                commitment_key=str(row["commitment_key"]),
                memory_bytes=int(row["memory_bytes"]),
                peak_memory_bytes=int(row["peak_memory_bytes"]),
                resident_identity=str(row["resident_identity"])
                if row["resident_identity"] is not None
                else None,
            )
            for row in rows
        ]
        if not any(item.kind == MemoryCommitmentKind.BASE for item in commitments):
            commitments.append(base_runtime_commitment())
        return commitments

    async def assert_memory_available_for_task(
        self,
        connection: AsyncConnection,
        *,
        worker_device_id: UUID,
        task_type: str,
        effective_memory_limit_bytes: int,
        attribution_status: MemoryAttributionStatus = MemoryAttributionStatus.KNOWN,
        assignment_id: UUID | None = None,
    ) -> MemoryAdmissionResult:
        if effective_memory_limit_bytes <= 0:
            raise router_error("MEMORY_BUDGET_EXCEEDED", detail="no effective memory budget")
        commitments = await self.load_active_commitments(
            connection,
            worker_device_id=worker_device_id,
        )
        requested = None
        if assignment_id is not None:
            requested = task_peak_commitment_for_assignment(
                assignment_id=str(assignment_id),
                task_type=task_type,
            )
        else:
            requested = task_peak_commitment_for_assignment(
                assignment_id="pending",
                task_type=task_type,
            )
        result = evaluate_memory_admission(
            effective_memory_limit_bytes=effective_memory_limit_bytes,
            commitments=commitments,
            requested=requested,
            attribution_status=attribution_status,
        )
        if not result.allowed:
            code = result.reasons[0] if result.reasons else "MEMORY_BUDGET_EXCEEDED"
            raise router_error(code, detail=f"accounted={result.accounted_bytes}")
        return result

    async def _upsert(
        self,
        connection: AsyncConnection,
        *,
        worker_device_id: UUID,
        commitment: MemoryCommitment,
        snapshot_sequence: int,
        assignment_id: UUID | None = None,
        model_version_id: UUID | None = None,
    ) -> None:
        await connection.execute(
            text(
                """
                SELECT public.upsert_worker_memory_commitment(
                    :worker_device_id, :commitment_kind, :commitment_key,
                    :resident_identity, :memory_bytes, :peak_memory_bytes,
                    :assignment_id, :model_version_id, :snapshot_sequence
                )
                """
            ),
            {
                "worker_device_id": worker_device_id,
                "commitment_kind": str(commitment.kind),
                "commitment_key": commitment.commitment_key,
                "resident_identity": commitment.resident_identity,
                "memory_bytes": commitment.memory_bytes,
                "peak_memory_bytes": commitment.peak_memory_bytes,
                "assignment_id": assignment_id,
                "model_version_id": model_version_id,
                "snapshot_sequence": snapshot_sequence,
            },
        )
