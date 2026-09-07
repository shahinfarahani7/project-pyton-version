from __future__ import annotations

from uuid import UUID

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncConnection

from edgemint.workers.errors import worker_error
from edgemint.workers.resource_policy import ContributionMode, validate_contribution_mode_id


def assert_performance_opt_in_confirmed(
    mode: ContributionMode,
    *,
    performance_opt_in_confirmed: bool,
) -> None:
    if mode.requiresExplicitOptIn and not performance_opt_in_confirmed:
        raise worker_error(
            "CONSENT_OPT_IN_REQUIRED",
            detail=f"explicit opt-in required for contribution mode {mode.id}",
        )


async def record_contribution_opt_in_event(
    connection: AsyncConnection,
    *,
    worker_id: UUID,
    contribution_mode_id: str,
    opt_in_confirmed: bool,
    request_id: str | None = None,
) -> None:
    await connection.execute(
        text(
            """
            INSERT INTO public.worker_contribution_opt_in_events(
                worker_id, contribution_mode_id, opt_in_confirmed, request_id
            )
            VALUES (:worker_id, :contribution_mode_id, :opt_in_confirmed, :request_id)
            """
        ),
        {
            "worker_id": worker_id,
            "contribution_mode_id": contribution_mode_id,
            "opt_in_confirmed": opt_in_confirmed,
            "request_id": request_id,
        },
    )


async def worker_has_performance_opt_in(
    connection: AsyncConnection,
    *,
    worker_id: UUID,
) -> bool:
    row = (
        await connection.execute(
            text(
                """
                SELECT 1
                FROM public.worker_contribution_opt_in_events
                WHERE worker_id = :worker_id
                  AND contribution_mode_id = 'performance'
                  AND opt_in_confirmed = TRUE
                LIMIT 1
                """
            ),
            {"worker_id": worker_id},
        )
    ).first()
    return row is not None


def validate_contribution_mode_change(
    *,
    current_mode_id: str,
    requested_mode_id: str,
    performance_opt_in_confirmed: bool,
) -> ContributionMode:
    requested = validate_contribution_mode_id(requested_mode_id)
    if requested_mode_id == current_mode_id:
        return requested
    assert_performance_opt_in_confirmed(
        requested,
        performance_opt_in_confirmed=performance_opt_in_confirmed,
    )
    return requested
