from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from uuid import UUID

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncConnection

from edgemint.building_blocks.ids import EntityId
from edgemint.tasks.errors import task_error


@dataclass(frozen=True, slots=True)
class ReservationRecord:
    reservation_id: UUID
    quote_id: UUID
    amount_micro_eur: int
    expires_at: datetime


async def ensure_prepaid_ledger_account(
    connection: AsyncConnection,
    *,
    workspace_id: UUID,
) -> UUID:
    existing = (
        await connection.execute(
            text(
                """
                SELECT id
                FROM public.ledger_accounts
                WHERE workspace_id = :workspace_id
                  AND owner_type = 'workspace'
                  AND account_code = '2000'
                LIMIT 1
                """
            ),
            {"workspace_id": workspace_id},
        )
    ).scalar_one_or_none()
    if existing is not None:
        return UUID(str(existing))
    account_id = EntityId.new().value
    await connection.execute(
        text(
            """
            INSERT INTO public.ledger_accounts(
                id, workspace_id, owner_type, owner_id, currency, account_code
            )
            VALUES (
                :id, :workspace_id, 'workspace', :owner_id, 'EUR', '2000'
            )
            """
        ),
        {
            "id": account_id,
            "workspace_id": workspace_id,
            "owner_id": str(workspace_id),
        },
    )
    return account_id


async def available_prepaid_micros(connection: AsyncConnection, *, workspace_id: UUID) -> int:
    row = (
        await connection.execute(
            text(
                """
                SELECT COALESCE(SUM(
                    CASE WHEN direction = 'credit' THEN amount_micros ELSE -amount_micros END
                ), 0) AS balance
                FROM public.ledger_entries AS entry
                JOIN public.ledger_accounts AS account
                  ON account.id = entry.ledger_account_id
                 AND account.workspace_id = entry.workspace_id
                WHERE entry.workspace_id = :workspace_id
                  AND account.account_code = '2000'
                """
            ),
            {"workspace_id": workspace_id},
        )
    ).scalar_one_or_none()
    if row is None:
        return 10_000_000_000
    return int(row)


async def reserve_credit(
    connection: AsyncConnection,
    *,
    workspace_id: UUID,
    task_id: UUID,
    task_revision_id: UUID,
    quote_id: UUID,
    amount_micro_eur: int,
    expires_at: datetime,
) -> ReservationRecord:
    if amount_micro_eur < 0:
        raise task_error("INPUT_SCHEMA_INVALID", detail="negative reservation amount")
    ledger_account_id = await ensure_prepaid_ledger_account(connection, workspace_id=workspace_id)
    available = await available_prepaid_micros(connection, workspace_id=workspace_id)
    reserved = (
        await connection.execute(
            text(
                """
                SELECT COALESCE(SUM(amount_micro_eur), 0)
                FROM public.credit_reservations
                WHERE workspace_id = :workspace_id
                  AND status = 'active'
                """
            ),
            {"workspace_id": workspace_id},
        )
    ).scalar_one()
    if available - int(reserved) < amount_micro_eur:
        raise task_error("INSUFFICIENT_CREDIT")
    reservation_id = EntityId.new().value
    await connection.execute(
        text(
            """
            INSERT INTO public.credit_reservations(
                id, workspace_id, quote_id, ledger_account_id,
                amount_micro_eur, status, task_id, task_revision_id, expires_at_utc
            )
            VALUES (
                :id, :workspace_id, :quote_id, :ledger_account_id,
                :amount_micro_eur, 'active', :task_id, :task_revision_id, :expires_at_utc
            )
            """
        ),
        {
            "id": reservation_id,
            "workspace_id": workspace_id,
            "quote_id": quote_id,
            "ledger_account_id": ledger_account_id,
            "amount_micro_eur": amount_micro_eur,
            "task_id": task_id,
            "task_revision_id": task_revision_id,
            "expires_at_utc": expires_at,
        },
    )
    return ReservationRecord(
        reservation_id=reservation_id,
        quote_id=quote_id,
        amount_micro_eur=amount_micro_eur,
        expires_at=expires_at,
    )


async def release_credit_reservation(
    connection: AsyncConnection,
    *,
    workspace_id: UUID,
    task_id: UUID,
) -> None:
    await connection.execute(
        text(
            """
            UPDATE public.credit_reservations
            SET status = 'released'
            WHERE workspace_id = :workspace_id
              AND task_id = :task_id
              AND status = 'active'
            """
        ),
        {"workspace_id": workspace_id, "task_id": task_id},
    )


async def count_active_draft_tasks(connection: AsyncConnection, *, workspace_id: UUID) -> int:
    value = (
        await connection.execute(
            text(
                """
                SELECT COUNT(*) AS count
                FROM public.tasks
                WHERE workspace_id = :workspace_id
                  AND lifecycle_status = 'draft'
                """
            ),
            {"workspace_id": workspace_id},
        )
    ).scalar_one()
    return int(value)
