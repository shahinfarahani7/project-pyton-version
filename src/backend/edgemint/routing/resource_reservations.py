from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime
from uuid import UUID

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncConnection

from edgemint.building_blocks.settings import Settings, get_settings
from edgemint.routing.device_certification import (
    load_device_concurrency_certified,
    load_device_thermal_state,
)
from edgemint.routing.envelope_registry import ResourceEnvelopeSpec, envelope_for_task_type
from edgemint.routing.errors import router_error
from edgemint.routing.exclusive_groups import (
    exclusive_group_enforcement_reasons,
    load_device_exclusive_group_counts,
)
from edgemint.routing.memory_accounting import (
    MemoryAttributionStatus,
    WorkerMemoryAccountingService,
)
from edgemint.routing.physical_release import PhysicalReleaseService
from edgemint.routing.resource_budget import (
    ResourceClassTotals,
    compute_effective_resource_budgets,
    load_contribution_budget_multiplier_bps_for_device,
    load_device_resource_class_totals,
    load_worker_device_capability,
    resource_class_budget_reasons,
)


@dataclass(frozen=True, slots=True)
class ResourceReservationVector:
    cpu_units: int
    memory_bytes: int
    storage_bytes: int
    accelerator_units: int
    model_session_units: int
    exclusive_group: str


def reservation_vector_for_task_type(task_type: str) -> ResourceReservationVector:
    envelope = envelope_for_task_type(task_type)
    if envelope is None:
        return ResourceReservationVector(
            cpu_units=1,
            memory_bytes=0,
            storage_bytes=0,
            accelerator_units=0,
            model_session_units=1,
            exclusive_group="",
        )
    return _vector_from_envelope(envelope)


def _vector_from_envelope(envelope: ResourceEnvelopeSpec) -> ResourceReservationVector:
    return ResourceReservationVector(
        cpu_units=envelope.cpu_units,
        memory_bytes=envelope.memory_reservation_bytes,
        storage_bytes=envelope.storage_reservation_bytes,
        accelerator_units=envelope.accelerator_units,
        model_session_units=envelope.model_session_units,
        exclusive_group=envelope.exclusive_group,
    )


@dataclass(slots=True)
class ResourceReservationService:
    settings: Settings = field(default_factory=get_settings)
    physical_release: PhysicalReleaseService = field(default_factory=PhysicalReleaseService)
    memory_accounting: WorkerMemoryAccountingService = field(default_factory=WorkerMemoryAccountingService)

    async def _device_scheduling_context(
        self,
        connection: AsyncConnection,
        *,
        worker_device_id: UUID,
    ) -> tuple[bool, str | None]:
        certified = await load_device_concurrency_certified(
            connection,
            worker_device_id=worker_device_id,
        )
        thermal_state = await load_device_thermal_state(
            connection,
            worker_device_id=worker_device_id,
        )
        return certified, thermal_state

    async def assert_exclusive_group_available(
        self,
        connection: AsyncConnection,
        *,
        worker_device_id: UUID,
        exclusive_group: str,
        device_certified: bool | None = None,
        thermal_state: str | None = None,
    ) -> None:
        if not self.settings.worker_exclusive_group_enforcement_enabled or not exclusive_group:
            return
        if device_certified is None or thermal_state is None:
            loaded_certified, loaded_thermal = await self._device_scheduling_context(
                connection,
                worker_device_id=worker_device_id,
            )
            if device_certified is None:
                device_certified = loaded_certified
            if thermal_state is None:
                thermal_state = loaded_thermal
        active_counts = await load_device_exclusive_group_counts(
            connection,
            worker_device_id=worker_device_id,
        )
        reasons = exclusive_group_enforcement_reasons(
            requested_group=exclusive_group,
            active_counts=active_counts,
            device_certified=device_certified,
            thermal_state=thermal_state,
        )
        if reasons:
            code = reasons[0]
            if code not in {"EXCLUSIVE_GROUP_SATURATED", "EXCLUSIVE_GROUP_CROSS_BLOCKED", "EXCLUSIVE_GROUP_UNKNOWN"}:
                code = "EXCLUSIVE_GROUP_SATURATED"
            raise router_error(code, detail=exclusive_group)

    async def assert_per_class_resource_budget_available(
        self,
        connection: AsyncConnection,
        *,
        worker_device_id: UUID,
        requested: ResourceReservationVector,
        task_type: str,
    ) -> None:
        if not self.settings.worker_per_class_budget_enforcement_enabled:
            return
        capability = await load_worker_device_capability(
            connection,
            worker_device_id=worker_device_id,
        )
        if capability is None:
            return
        multiplier_bps = await load_contribution_budget_multiplier_bps_for_device(
            connection,
            worker_device_id=worker_device_id,
        )
        effective = compute_effective_resource_budgets(
            capability=capability,
            contribution_multiplier_bps=multiplier_bps,
        )
        reserved = await load_device_resource_class_totals(
            connection,
            worker_device_id=worker_device_id,
        )
        reasons = resource_class_budget_reasons(
            effective=effective,
            reserved=reserved,
            requested=ResourceClassTotals(
                cpu_units=requested.cpu_units,
                memory_bytes=requested.memory_bytes,
                storage_bytes=requested.storage_bytes,
            ),
        )
        if reasons:
            raise router_error(reasons[0])
        attribution = (
            MemoryAttributionStatus.KNOWN
            if capability.memory.availableBytes > 0
            else MemoryAttributionStatus.UNCERTAIN
        )
        await self.memory_accounting.assert_memory_available_for_task(
            connection,
            worker_device_id=worker_device_id,
            task_type=task_type,
            effective_memory_limit_bytes=effective.memory_bytes,
            attribution_status=attribution,
        )

    async def reserve_for_assignment(
        self,
        connection: AsyncConnection,
        *,
        workspace_id: UUID,
        assignment_id: UUID,
        worker_device_id: UUID,
        task_revision_id: UUID,
        task_type: str,
        fence_token: int,
        expires_at_utc: datetime,
    ) -> UUID:
        vector = reservation_vector_for_task_type(task_type)
        await self.assert_exclusive_group_available(
            connection,
            worker_device_id=worker_device_id,
            exclusive_group=vector.exclusive_group,
        )
        await self.assert_per_class_resource_budget_available(
            connection,
            worker_device_id=worker_device_id,
            requested=vector,
            task_type=task_type,
        )
        reservation_id = (
            await connection.execute(
                text(
                    """
                    SELECT public.create_worker_resource_reservation(
                        :workspace_id, :assignment_id, :worker_device_id, :task_revision_id,
                        :cpu_units, :memory_bytes, :storage_bytes, :accelerator_units,
                        :model_session_units, :exclusive_group, :fence_token, :expires_at_utc
                    )
                    """
                ),
                {
                    "workspace_id": workspace_id,
                    "assignment_id": assignment_id,
                    "worker_device_id": worker_device_id,
                    "task_revision_id": task_revision_id,
                    "cpu_units": vector.cpu_units,
                    "memory_bytes": vector.memory_bytes,
                    "storage_bytes": vector.storage_bytes,
                    "accelerator_units": vector.accelerator_units,
                    "model_session_units": vector.model_session_units,
                    "exclusive_group": vector.exclusive_group,
                    "fence_token": fence_token,
                    "expires_at_utc": expires_at_utc,
                },
            )
        ).scalar_one()
        await self.memory_accounting.record_task_peak_for_assignment(
            connection,
            worker_device_id=worker_device_id,
            assignment_id=assignment_id,
            task_type=task_type,
        )
        return UUID(str(reservation_id))

    async def activate_for_assignment(
        self,
        connection: AsyncConnection,
        *,
        assignment_id: UUID,
        fence_token: int,
    ) -> bool:
        reservation_id = (
            await connection.execute(
                text(
                    """
                    SELECT id
                    FROM public.worker_resource_reservations
                    WHERE assignment_id = :assignment_id
                      AND status = 'reserved'
                    FOR UPDATE
                    """
                ),
                {"assignment_id": assignment_id},
            )
        ).scalar_one_or_none()
        if reservation_id is None:
            return False
        activated = (
            await connection.execute(
                text(
                    """
                    SELECT public.activate_worker_resource_reservation(
                        :reservation_id, :fence_token
                    )
                    """
                ),
                {"reservation_id": reservation_id, "fence_token": fence_token},
            )
        ).scalar_one()
        return bool(activated)

    async def release_for_assignment(
        self,
        connection: AsyncConnection,
        *,
        assignment_id: UUID,
        terminal_status: str = "released",
        fence_token: int | None = None,
        stop_reason: str = "logical_release",
    ) -> bool:
        if fence_token is not None:
            await self.physical_release.request_stop_for_assignment(
                connection,
                assignment_id=assignment_id,
                fence_token=fence_token,
                reason=stop_reason,
            )
        released = (
            await connection.execute(
                text(
                    """
                    SELECT public.release_worker_resource_reservation_by_assignment(
                        :assignment_id, :terminal_status
                    )
                    """
                ),
                {"assignment_id": assignment_id, "terminal_status": terminal_status},
            )
        ).scalar_one()
        await self.memory_accounting.release_task_peak_for_assignment(
            connection,
            assignment_id=assignment_id,
        )
        return bool(released)

    async def confirm_physical_stop_for_assignment(
        self,
        connection: AsyncConnection,
        *,
        assignment_id: UUID,
        fence_token: int,
        proof: str,
        reason: str = "worker_stop_confirmed",
    ) -> bool:
        commit = await self.physical_release.confirm_stop_for_assignment(
            connection,
            assignment_id=assignment_id,
            fence_token=fence_token,
            proof=proof,
            reason=reason,
        )
        return commit.committed

    async def load_assignment_reservation_context(
        self,
        connection: AsyncConnection,
        *,
        assignment_id: UUID,
    ) -> dict[str, object]:
        row = (
            await connection.execute(
                text(
                    """
                    SELECT
                        assignment.workspace_id,
                        assignment.worker_device_id,
                        assignment.fence_token,
                        assignment.lease_expires_at_utc,
                        revision.id AS task_revision_id,
                        task.task_type
                    FROM public.assignments AS assignment
                    JOIN public.task_attempts AS attempt
                      ON attempt.id = assignment.task_attempt_id
                     AND attempt.workspace_id = assignment.workspace_id
                    JOIN public.tasks AS task
                      ON task.id = attempt.task_id
                     AND task.workspace_id = attempt.workspace_id
                    JOIN public.task_revisions AS revision
                      ON revision.id = task.current_revision_id
                     AND revision.workspace_id = task.workspace_id
                    WHERE assignment.id = :assignment_id
                    """
                ),
                {"assignment_id": assignment_id},
            )
        ).mappings().first()
        if row is None:
            raise router_error("TENANT_RESOURCE_NOT_FOUND", detail="assignment context missing")
        return dict(row)


async def reserve_resources_for_new_assignment(
    service: ResourceReservationService,
    connection: AsyncConnection,
    *,
    assignment_id: UUID,
) -> UUID | None:
    context = await service.load_assignment_reservation_context(
        connection,
        assignment_id=assignment_id,
    )
    return await service.reserve_for_assignment(
        connection,
        workspace_id=UUID(str(context["workspace_id"])),
        assignment_id=assignment_id,
        worker_device_id=UUID(str(context["worker_device_id"])),
        task_revision_id=UUID(str(context["task_revision_id"])),
        task_type=str(context["task_type"]),
        fence_token=int(context["fence_token"]),
        expires_at_utc=context["lease_expires_at_utc"],  # type: ignore[arg-type]
    )
