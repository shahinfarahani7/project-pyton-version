"""Atomic assignment transaction coordinator (Architecture Section 20)."""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any
from uuid import UUID

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncConnection

from edgemint.building_blocks.settings import Settings, get_settings
from edgemint.routing.errors import router_error
from edgemint.routing.execution_allocation import ExecutionAllocationService
from edgemint.routing.resource_reservations import (
    ResourceReservationService,
    reservation_vector_for_task_type,
)
from edgemint.security.lease_credentials import LeaseCredentialCipher

# Documented §20 sequence executed inside one database transaction.
ATOMIC_ASSIGNMENT_TRANSACTION_STEPS: tuple[str, ...] = (
    "lock_task_attempt",
    "lock_worker_capacity",
    "recheck_heartbeat_freshness",
    "recheck_consent",
    "recheck_worker_availability",
    "recheck_model_runtime_compatibility",
    "recalculate_remaining_capacity",
    "recheck_exclusive_groups",
    "create_resource_reservation",
    "create_assignment",
    "generate_fence_token",
    "persist_lease_token_material",
    "create_outbox_event",
    "commit",
)


@dataclass(slots=True)
class AtomicAssignmentTransaction:
    """Coordinates assignment lease + reservation in the caller's open transaction."""

    settings: Settings = field(default_factory=get_settings)
    resource_reservations: ResourceReservationService = field(default_factory=ResourceReservationService)
    execution_allocations: ExecutionAllocationService = field(default_factory=ExecutionAllocationService)

    async def load_task_type_for_attempt(
        self,
        connection: AsyncConnection,
        *,
        task_attempt_id: UUID,
    ) -> str:
        row = (
            await connection.execute(
                text(
                    """
                    SELECT task.task_type
                    FROM public.task_attempts AS attempt
                    JOIN public.tasks AS task
                      ON task.id = attempt.task_id
                     AND task.workspace_id = attempt.workspace_id
                    WHERE attempt.id = :task_attempt_id
                    """
                ),
                {"task_attempt_id": task_attempt_id},
            )
        ).mappings().first()
        if row is None:
            raise router_error("TENANT_RESOURCE_NOT_FOUND", detail="task attempt missing")
        return str(row["task_type"])

    async def acquire_with_reservation(
        self,
        connection: AsyncConnection,
        *,
        task_attempt_id: UUID,
        worker_id: UUID,
        worker_device_id: UUID,
        router_instance_id: str,
        lease_token: str,
        lease_token_hash: bytes,
        lease_seconds: int,
        delivery_seconds: int,
        auto_start_grace_seconds: int,
        heartbeat_max_age_seconds: int,
        min_trust_bps: int,
        task_type: str,
    ) -> dict[str, Any]:
        vector = await self.execution_allocations.load_vector_for_attempt(
            connection,
            task_attempt_id=task_attempt_id,
        ) or reservation_vector_for_task_type(task_type)
        allocation_id = await self.execution_allocations.load_allocation_id_for_attempt(
            connection,
            task_attempt_id=task_attempt_id,
        )
        await self.resource_reservations.assert_exclusive_group_available(
            connection,
            worker_device_id=worker_device_id,
            exclusive_group=vector.exclusive_group,
        )
        await self.resource_reservations.assert_per_class_resource_budget_available(
            connection,
            worker_device_id=worker_device_id,
            requested=vector,
            task_type=task_type,
        )

        row = (
            await connection.execute(
                text(
                    """
                    SELECT assignment_id, fence_token, lease_expires_at_utc, reservation_id
                    FROM public.atomic_acquire_assignment_with_reservation(
                        :task_attempt_id, :worker_id, :worker_device_id, :router_instance_id,
                        :lease_token_hash, :lease_seconds, :delivery_seconds,
                        :auto_start_grace_seconds, :heartbeat_max_age_seconds, :min_trust_bps,
                        :cpu_units, :memory_bytes, :storage_bytes, :accelerator_units,
                        :model_session_units, :exclusive_group
                    )
                    """
                ),
                {
                    "task_attempt_id": task_attempt_id,
                    "worker_id": worker_id,
                    "worker_device_id": worker_device_id,
                    "router_instance_id": router_instance_id,
                    "lease_token_hash": lease_token_hash,
                    "lease_seconds": lease_seconds,
                    "delivery_seconds": delivery_seconds,
                    "auto_start_grace_seconds": auto_start_grace_seconds,
                    "heartbeat_max_age_seconds": heartbeat_max_age_seconds,
                    "min_trust_bps": min_trust_bps,
                    "cpu_units": vector.cpu_units,
                    "memory_bytes": vector.memory_bytes,
                    "storage_bytes": vector.storage_bytes,
                    "accelerator_units": vector.accelerator_units,
                    "model_session_units": vector.model_session_units,
                    "exclusive_group": vector.exclusive_group,
                },
            )
        ).mappings().first()
        if row is None:
            raise router_error("WORKER_NOT_ELIGIBLE")

        if allocation_id is not None:
            await connection.execute(
                text(
                    """
                    UPDATE public.assignments
                    SET execution_allocation_id = :allocation_id
                    WHERE id = :assignment_id
                    """
                ),
                {
                    "allocation_id": allocation_id,
                    "assignment_id": row["assignment_id"],
                },
            )

        token_ciphertext = LeaseCredentialCipher.from_settings(self.settings).encrypt(
            lease_token,
            worker_device_id=worker_device_id,
        )
        await connection.execute(
            text(
                """
                INSERT INTO public.assignment_lease_credentials(
                    assignment_id, worker_device_id, lease_token_ciphertext
                )
                VALUES (:assignment_id, :worker_device_id, :lease_token_ciphertext)
                """
            ),
            {
                "assignment_id": row["assignment_id"],
                "worker_device_id": worker_device_id,
                "lease_token_ciphertext": token_ciphertext,
            },
        )
        return {
            "assignmentId": str(row["assignment_id"]),
            "reservationId": str(row["reservation_id"]),
            "fenceToken": int(row["fence_token"]),
            "leaseToken": lease_token,
            "leaseExpiresAt": row["lease_expires_at_utc"],
        }
